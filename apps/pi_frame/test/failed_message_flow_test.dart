import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/attachment_model.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_attachments_provider.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _PromptClient extends PcpClient {
  final prompts = <String>[];

  _PromptClient() : super(port: 0, token: 'test');

  @override
  Stream<PcpEvent> events(String sessionId) => const Stream.empty();

  @override
  Stream<PcpSnapshot> snapshots(String sessionId) => const Stream.empty();

  @override
  void attach(String sessionId, {int? lastSeq}) {}

  @override
  Future<Map<String, dynamic>> sendPrompt(
    String sessionId,
    String text, {
    String? streamingBehavior,
    List<dynamic>? images,
  }) async {
    prompts.add(text);
    return {'state': 'completed'};
  }
}

Widget _app(SessionStateNotifier session) => ProviderScope(
  overrides: [
    daemonEndpointProvider.overrideWith((ref) async => null),
    sessionStateFamily(session.sessionId).overrideWith((ref) => session),
  ],
  child: MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: Scaffold(
      body: Column(
        children: [
          Expanded(child: TranscriptView(sessionId: session.sessionId)),
          Composer(sessionId: session.sessionId),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('failed bubble shows error and retry resends the same message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final client = _PromptClient();
    addTearDown(client.dispose);
    final session = SessionStateNotifier('failed', client)
      ..state = const SessionState(
        sessionId: 'failed',
        cwd: '/repo',
        currentModel: 'test-model',
        currentThinkingLevel: 'off',
        entries: [
          SessionEntry(
            id: 'failed_1',
            role: 'user',
            text: 'retry me',
            timestamp: 1,
            metadata: {'sendError': 'Model unavailable'},
          ),
        ],
      );
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();

    expect(find.text('Invio non riuscito: Model unavailable'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('retry-user-message-failed_1')),
      findsOneWidget,
    );
    final bubble = tester.widget<Container>(
      find.byKey(const ValueKey('failed-message-bubble-failed_1')),
    );
    expect(
      (bubble.decoration! as BoxDecoration).border!.top.color,
      FrameTokens.dark.danger,
    );

    await tester.tap(find.byKey(const ValueKey('retry-user-message-failed_1')));
    await tester.pump();

    expect(client.prompts, ['retry me']);
    expect(session.state.entries, hasLength(1));
    expect(session.state.entries.single.metadata?['sendError'], isNull);
    expect(session.state.entries.single.id, startsWith('usr_'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-click restores failed text and attachments to composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    const failedAttachment = ChatAttachment(
      id: 'sent-file',
      type: AttachmentType.repoFile,
      name: 'main.dart',
      pathOrUrl: '/repo/lib/main.dart',
    );
    const existingAttachment = ChatAttachment(
      id: 'current-file',
      type: AttachmentType.repoFile,
      name: 'notes.md',
      pathOrUrl: '/repo/notes.md',
    );
    final failedText =
        '${encodeAttachmentsTag([failedAttachment])}\nReview this file';
    final session = SessionStateNotifier('restore', null)
      ..state = SessionState(
        sessionId: 'restore',
        cwd: '/repo',
        entries: [
          SessionEntry(
            id: 'failed_2',
            role: 'user',
            text: failedText,
            timestamp: 1,
            metadata: const {'sendError': 'Connection lost'},
          ),
        ],
      );
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Composer)),
    );
    container.read(composerDraftProvider('restore').notifier).state =
        'Keep this draft';
    container
        .read(composerAttachmentsProvider('restore').notifier)
        .add(existingAttachment);
    await tester.pump();

    final failedBubble = find.byKey(
      const ValueKey('failed-user-message-failed_2'),
    );
    await tester.tap(failedBubble);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(failedBubble);
    await tester.pumpAndSettle();

    expect(session.state.entries, isEmpty);
    expect(
      container.read(composerDraftProvider('restore')),
      'Review this file\nKeep this draft',
    );
    expect(find.text('Review this file\nKeep this draft'), findsOneWidget);
    expect(
      container.read(composerAttachmentsProvider('restore')),
      containsAll([failedAttachment, existingAttachment]),
    );
    expect(tester.takeException(), isNull);
  });
}
