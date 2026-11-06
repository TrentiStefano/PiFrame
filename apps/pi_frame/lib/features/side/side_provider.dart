import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../domain/session/session_reducer.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/snapshot_reducer.dart';

class SideThreadState {
  final String parentSessionId;
  final String? sideId;
  final String? streamId;
  final String status; // 'idle', 'opening', 'active', 'closed', 'error'
  final String? model;
  final String? closeReason; // 'idle', 'parentClosed', 'error', 'user'
  final bool isOpen;
  final String? errorMessage;

  const SideThreadState({
    required this.parentSessionId,
    this.sideId,
    this.streamId,
    this.status = 'idle',
    this.model,
    this.closeReason,
    this.isOpen = false,
    this.errorMessage,
  });

  bool get isClosed => status == 'closed';
  bool get isActive => status == 'active';
  bool get isOpening => status == 'opening';
  bool get isError => status == 'error';

  SideThreadState copyWith({
    String? sideId,
    String? streamId,
    String? status,
    String? model,
    String? closeReason,
    bool clearCloseReason = false,
    bool? isOpen,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return SideThreadState(
      parentSessionId: parentSessionId,
      sideId: sideId ?? this.sideId,
      streamId: streamId ?? this.streamId,
      status: status ?? this.status,
      model: model ?? this.model,
      closeReason: clearCloseReason ? null : (closeReason ?? this.closeReason),
      isOpen: isOpen ?? this.isOpen,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final sideThreadFamily =
    StateNotifierProvider.family<SideThreadNotifier, SideThreadState, String>(
  (ref, parentSessionId) => SideThreadNotifier(parentSessionId, ref),
);

final sideSessionFamily =
    StateNotifierProvider.family<SideSessionNotifier, SessionState, String>(
  (ref, parentSessionId) => SideSessionNotifier(parentSessionId, ref),
);

class SideSessionNotifier extends StateNotifier<SessionState> {
  final String parentSessionId;
  final Ref ref;
  StreamSubscription? _eventSub;
  StreamSubscription? _snapSub;
  String? _streamId;

  SideSessionNotifier(this.parentSessionId, this.ref)
      : super(
          const SessionState(
            sessionId: '',
            cwd: '',
            readOnly: true,
            readOnlyReason: 'side',
          ),
        );

  void initStream(String streamId, PcpClient client) {
    if (_streamId == streamId && _eventSub != null) return;
    _streamId = streamId;
    _eventSub?.cancel();
    _snapSub?.cancel();

    final parentCwd = ref.read(sessionStateFamily(parentSessionId)).cwd;
    state = SessionState(
      sessionId: streamId,
      cwd: parentCwd,
      readOnly: true,
      readOnlyReason: 'side',
    );

    _snapSub = client.snapshots(streamId).listen((snapshot) {
      final applied = applySessionSnapshot(
        streamId,
        snapshot.seq,
        snapshot.payload,
      );
      state = applied.copyWith(readOnly: true, readOnlyReason: 'side');
    });

    _eventSub = client.events(streamId).listen((event) {
      state = reduceSessionState(state, event).copyWith(
        readOnly: true,
        readOnlyReason: 'side',
      );
    });

    client.attach(streamId);
  }

  void reset() {
    _eventSub?.cancel();
    _snapSub?.cancel();
    _eventSub = null;
    _snapSub = null;
    _streamId = null;
    state = const SessionState(
      sessionId: '',
      cwd: '',
      readOnly: true,
      readOnlyReason: 'side',
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _snapSub?.cancel();
    super.dispose();
  }
}

class SideThreadNotifier extends StateNotifier<SideThreadState> {
  final String parentSessionId;
  final Ref ref;
  StreamSubscription? _streamEventSub;
  StreamSubscription? _parentEventSub;

  SideThreadNotifier(this.parentSessionId, this.ref)
      : super(SideThreadState(parentSessionId: parentSessionId));

  Future<void> openSide({String? question}) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      state = state.copyWith(
        status: 'error',
        errorMessage: 'Daemon non connesso',
        isOpen: true,
      );
      return;
    }
    state = state.copyWith(
      status: 'opening',
      isOpen: true,
      clearCloseReason: true,
      clearErrorMessage: true,
    );
    try {
      final res = await client.openSide(parentSessionId, question: question);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final sideId = (data['sideId'] ?? res['sideId'])?.toString() ?? '';
      final streamId = (data['streamId'] ?? res['streamId'])?.toString() ?? '';
      final model = (data['model'] ?? res['model'])?.toString();

      state = state.copyWith(
        sideId: sideId,
        streamId: streamId,
        status: 'active',
        model: model,
        isOpen: true,
      );

      ref
          .read(sideSessionFamily(parentSessionId).notifier)
          .initStream(streamId, client);

      _listenToEvents(client, streamId, sideId);
    } catch (e) {
      state = state.copyWith(
        status: 'error',
        errorMessage: e.toString(),
        isOpen: true,
      );
    }
  }

  void _listenToEvents(PcpClient client, String streamId, String sideId) {
    _streamEventSub?.cancel();
    _streamEventSub = client.events(streamId).listen((event) {
      _handleSideEvent(event, sideId);
    });

    _parentEventSub?.cancel();
    _parentEventSub = client.events(parentSessionId).listen((event) {
      _handleSideEvent(event, sideId);
    });
  }

  void _handleSideEvent(PcpEvent event, String sideId) {
    if (event is SideOpenedEvent) {
      if (event.sideId == sideId || event.sideId.isEmpty) {
        state = state.copyWith(
          model: event.model?.toString() ?? state.model,
          status: 'active',
        );
      }
    } else if (event is SideClosedEvent) {
      if (event.sideId == sideId || event.sideId.isEmpty) {
        state = state.copyWith(
          status: 'closed',
          closeReason: event.reason,
        );
      }
    }
  }

  Future<void> prompt(String text) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    final sideId = state.sideId;
    if (sideId == null || state.status != 'active') {
      await openSide(question: text);
      return;
    }
    await client.sidePrompt(sideId, text);
  }

  Future<void> abort() async {
    final client = ref.read(pcpClientProvider);
    final sideId = state.sideId;
    if (client != null && sideId != null) {
      await client.sideAbort(sideId);
    }
  }

  Future<void> close() async {
    final client = ref.read(pcpClientProvider);
    final sideId = state.sideId;
    if (client != null && sideId != null && state.status == 'active') {
      try {
        await client.sideClose(sideId);
      } catch (_) {}
    }
    state = state.copyWith(
      status: 'closed',
      closeReason: 'user',
      isOpen: false,
    );
  }

  void togglePanel() {
    state = state.copyWith(isOpen: !state.isOpen);
  }

  void openPanel() {
    if (!state.isOpen) {
      state = state.copyWith(isOpen: true);
    }
  }

  void closePanel() {
    if (state.isOpen) {
      state = state.copyWith(isOpen: false);
    }
  }

  @override
  void dispose() {
    _streamEventSub?.cancel();
    _parentEventSub?.cancel();
    super.dispose();
  }
}
