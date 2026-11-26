import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../domain/session/session_reducer.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/snapshot_reducer.dart';

/// The label of a side conversation's model: the daemon sends Pi's model object ({provider, id, name}) or a plain id.
String? sideModelLabel(Object? model) {
  if (model is Map) {
    final label = model['name'] ?? model['id'];
    return label?.toString();
  }
  return model?.toString();
}

class SideConversationRecord {
  final String id;
  final String title;
  final DateTime createdAt;
  final String status; // 'opening', 'active', 'closed', 'error'
  final String? model;
  final String? closeReason;
  final String? errorMessage;
  final List<SessionEntry> entries;

  const SideConversationRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    this.status = 'active',
    this.model,
    this.closeReason,
    this.errorMessage,
    this.entries = const [],
  });

  SideConversationRecord copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    String? status,
    String? model,
    String? closeReason,
    bool clearCloseReason = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<SessionEntry>? entries,
  }) {
    return SideConversationRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      model: model ?? this.model,
      closeReason: clearCloseReason ? null : (closeReason ?? this.closeReason),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      entries: entries ?? this.entries,
    );
  }
}

class SideThreadState {
  final String parentSessionId;
  final String? sideId;
  final String? streamId;
  final String status; // 'idle', 'opening', 'active', 'closed', 'error'
  final String? model;
  final String? closeReason; // 'idle', 'parentClosed', 'error', 'user'
  final bool isOpen;
  final String? errorMessage;
  final List<SideConversationRecord> conversations;
  final String? selectedConversationId;

  const SideThreadState({
    required this.parentSessionId,
    this.sideId,
    this.streamId,
    this.status = 'idle',
    this.model,
    this.closeReason,
    this.isOpen = false,
    this.errorMessage,
    this.conversations = const [],
    this.selectedConversationId,
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
    List<SideConversationRecord>? conversations,
    String? selectedConversationId,
    bool clearSelectedConversationId = false,
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
      conversations: conversations ?? this.conversations,
      selectedConversationId: clearSelectedConversationId
          ? null
          : (selectedConversationId ?? this.selectedConversationId),
    );
  }
}

final sideThreadFamily = StateNotifierProvider.family<SideThreadNotifier, SideThreadState, String>(
  (ref, parentSessionId) => SideThreadNotifier(parentSessionId, ref),
);

/// Set by a toggle that must not animate (Ctrl+Shift+B). The split consumes and clears it.
final sideInstantToggleProvider = StateProvider<bool>((ref) => false);

enum ChatSidecarTab { agents, side, tasks }

/// The unsent text of a session's side conversation. Kept outside the panel,
/// so hiding the plugins pane (or switching tab) does not lose a draft.
final sideDraftFamily = StateProvider.family<String, String>((ref, parentSessionId) => '');

final chatSidecarTabFamily = StateProvider.family<ChatSidecarTab, String>((ref, sessionId) => ChatSidecarTab.side);

final sideSessionFamily = StateNotifierProvider.family<SideSessionNotifier, SessionState, String>(
  (ref, parentSessionId) => SideSessionNotifier(parentSessionId, ref),
);

class SideSessionNotifier extends StateNotifier<SessionState> {
  final String parentSessionId;
  final Ref ref;
  StreamSubscription<PcpEvent>? _eventSub;
  StreamSubscription<PcpSnapshot>? _snapSub;
  String? _streamId;

  SideSessionNotifier(this.parentSessionId, this.ref)
    : super(const SessionState(sessionId: '', cwd: '', readOnly: true, readOnlyReason: 'side'));

  void initStream(String streamId, PcpClient client) {
    if (_streamId == streamId && _eventSub != null) return;
    _streamId = streamId;
    unawaited(_eventSub?.cancel());
    unawaited(_snapSub?.cancel());

    final parentCwd = ref.read(sessionStateFamily(parentSessionId)).cwd;
    state = SessionState(sessionId: streamId, cwd: parentCwd, readOnly: true, readOnlyReason: 'side');

    _snapSub = client.snapshots(streamId).listen((snapshot) {
      final applied = applySessionSnapshot(streamId, snapshot.seq, snapshot.payload);
      state = applied.copyWith(readOnly: true, readOnlyReason: 'side');
    });

    _eventSub = client.events(streamId).listen((event) {
      state = reduceSessionState(state, event).copyWith(readOnly: true, readOnlyReason: 'side');
    });

    client.attach(streamId);
  }

  void reset() {
    unawaited(_eventSub?.cancel());
    unawaited(_snapSub?.cancel());
    _eventSub = null;
    _snapSub = null;
    _streamId = null;
    state = const SessionState(sessionId: '', cwd: '', readOnly: true, readOnlyReason: 'side');
  }

  @override
  void dispose() {
    unawaited(_eventSub?.cancel());
    unawaited(_snapSub?.cancel());
    super.dispose();
  }
}

class SideThreadNotifier extends StateNotifier<SideThreadState> {
  final String parentSessionId;
  final Ref ref;
  StreamSubscription<PcpEvent>? _streamEventSub;
  StreamSubscription<PcpEvent>? _parentEventSub;

  SideThreadNotifier(this.parentSessionId, this.ref) : super(SideThreadState(parentSessionId: parentSessionId));

  Future<void> openSide({String? question}) async {
    final client = ref.read(pcpClientProvider);
    final title = (question != null && question.trim().isNotEmpty)
        ? question.trim()
        : 'Discussione ${state.conversations.length + 1}';
    final tempRecordId = 'side_${DateTime.now().millisecondsSinceEpoch}';

    // If there was an active side thread, archive its entries
    final currentEntries = ref.read(sideSessionFamily(parentSessionId)).entries;
    final archivedList = state.conversations.map((c) {
      if (c.id == state.sideId) {
        return c.copyWith(entries: currentEntries, status: 'closed');
      }
      return c;
    }).toList();

    final newRecord = SideConversationRecord(
      id: tempRecordId,
      title: title,
      createdAt: DateTime.now(),
      status: 'opening',
    );

    final updatedConversations = [...archivedList, newRecord];

    if (client == null) {
      final withErr = updatedConversations.map((c) {
        if (c.id == tempRecordId) {
          return c.copyWith(status: 'error', errorMessage: ref.read(appStringsProvider).daemonNotConnected);
        }
        return c;
      }).toList();
      state = state.copyWith(
        status: 'error',
        errorMessage: ref.read(appStringsProvider).daemonNotConnected,
        isOpen: true,
        conversations: withErr,
        selectedConversationId: tempRecordId,
      );
      return;
    }

    state = state.copyWith(
      status: 'opening',
      isOpen: true,
      clearCloseReason: true,
      clearErrorMessage: true,
      conversations: updatedConversations,
      selectedConversationId: tempRecordId,
    );

    try {
      final res = await client.openSide(parentSessionId, question: question);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final sideId = (data['sideId'] ?? res['sideId'])?.toString() ?? tempRecordId;
      final streamId = (data['streamId'] ?? res['streamId'])?.toString() ?? sideId;
      final model = sideModelLabel(data['model'] ?? res['model']);

      final activeConversations = state.conversations.map((c) {
        if (c.id == tempRecordId) {
          return c.copyWith(id: sideId, model: model, status: 'active');
        }
        return c;
      }).toList();

      state = state.copyWith(
        sideId: sideId,
        streamId: streamId,
        status: 'active',
        model: model,
        isOpen: true,
        conversations: activeConversations,
        selectedConversationId: sideId,
      );

      ref.read(sideSessionFamily(parentSessionId).notifier).initStream(streamId, client);

      _listenToEvents(client, streamId, sideId);
    } catch (e) {
      final errorConversations = state.conversations.map((c) {
        if (c.id == tempRecordId) {
          return c.copyWith(status: 'error', errorMessage: e.toString());
        }
        return c;
      }).toList();

      state = state.copyWith(
        status: 'error',
        errorMessage: e.toString(),
        isOpen: true,
        conversations: errorConversations,
        selectedConversationId: tempRecordId,
      );
    }
  }

  void selectConversation(String id) {
    if (state.selectedConversationId == id) return;
    final currentEntries = ref.read(sideSessionFamily(parentSessionId)).entries;
    final updatedList = state.conversations.map((c) {
      if (c.id == state.sideId) {
        return c.copyWith(entries: currentEntries);
      }
      return c;
    }).toList();

    state = state.copyWith(conversations: updatedList, selectedConversationId: id);
  }

  void deleteConversation(String id) {
    final remaining = state.conversations.where((c) => c.id != id).toList();
    String? nextSelected = state.selectedConversationId;
    if (state.selectedConversationId == id) {
      nextSelected = remaining.isNotEmpty ? remaining.last.id : null;
    }
    state = state.copyWith(
      conversations: remaining,
      selectedConversationId: nextSelected,
      clearSelectedConversationId: nextSelected == null,
    );
  }

  Future<void> newConversation() async {
    await openSide();
  }

  void _listenToEvents(PcpClient client, String streamId, String sideId) {
    unawaited(_streamEventSub?.cancel());
    _streamEventSub = client.events(streamId).listen((event) {
      _handleSideEvent(event, sideId);
    });

    unawaited(_parentEventSub?.cancel());
    _parentEventSub = client.events(parentSessionId).listen((event) {
      _handleSideEvent(event, sideId);
    });
  }

  void _handleSideEvent(PcpEvent event, String sideId) {
    if (event is SideOpenedEvent) {
      if (event.sideId == sideId || event.sideId.isEmpty) {
        final newModel = sideModelLabel(event.model) ?? state.model;
        final updatedList = state.conversations.map((c) {
          if (c.id == sideId) {
            return c.copyWith(model: newModel, status: 'active');
          }
          return c;
        }).toList();
        state = state.copyWith(model: newModel, status: 'active', conversations: updatedList);
      }
    } else if (event is SideClosedEvent) {
      if (event.sideId == sideId || event.sideId.isEmpty) {
        final currentEntries = ref.read(sideSessionFamily(parentSessionId)).entries;
        final updatedList = state.conversations.map((c) {
          if (c.id == sideId) {
            return c.copyWith(
              status: 'closed',
              closeReason: event.reason,
              entries: currentEntries.isNotEmpty ? currentEntries : c.entries,
            );
          }
          return c;
        }).toList();
        state = state.copyWith(status: 'closed', closeReason: event.reason, conversations: updatedList);
      }
    }
  }

  Future<void> prompt(String text) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    final sideId = state.sideId;
    if (sideId == null || state.status != 'active' || state.selectedConversationId != sideId) {
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
    final currentEntries = ref.read(sideSessionFamily(parentSessionId)).entries;
    final updatedList = state.conversations.map((c) {
      if (c.id == sideId) {
        return c.copyWith(
          status: 'closed',
          closeReason: 'user',
          entries: currentEntries.isNotEmpty ? currentEntries : c.entries,
        );
      }
      return c;
    }).toList();
    state = state.copyWith(status: 'closed', closeReason: 'user', isOpen: false, conversations: updatedList);
  }

  void togglePanel({bool instant = false}) {
    if (instant) ref.read(sideInstantToggleProvider.notifier).state = true;
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
    unawaited(_streamEventSub?.cancel());
    unawaited(_parentEventSub?.cancel());
    super.dispose();
  }
}
