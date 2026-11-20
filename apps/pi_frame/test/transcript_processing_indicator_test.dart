// While the agent works on the first step of a turn, the running step group
// already shows a shimmering "Working…" header. The live answer below it must
// not add a second "Processing…" spinner.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_transcript.dart';
import 'package:pi_frame/data/transcript/step_grouping_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _sid = 'processing_indicator';

Future<AppStrings> _pumpTranscript(WidgetTester tester, StepGroupingMode mode) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final notifier = SessionStateNotifier(_sid, null)
    ..state = SessionState(
      sessionId: _sid,
      cwd: '/repo',
      entries: [
        SessionEntry(id: 'u1', role: 'user', text: 'Fix the bug', timestamp: now),
      ],
      agentStatus: AgentStatus.working,
      runStartedAt: now,
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily(_sid).overrideWith((ref) => notifier),
        stepGroupingSettingsProvider.overrideWith(
          (ref) => StepGroupingSettingsNotifier()..setMode(mode),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: TranscriptView(sessionId: _sid)),
      ),
    ),
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return ProviderScope.containerOf(tester.element(find.byType(TranscriptView)))
      .read(appStringsProvider);
}

/// The step group header drops the label's own trailing dots and adds "...".
String _workingHeader(AppStrings strings) =>
    '${strings.stepGroupWorking.replaceAll(RegExp(r'[\.…]+$'), '').trimRight()}...';

void main() {
  testWidgets('first step shows "Working…" without a second "Processing…" spinner', (tester) async {
    final strings = await _pumpTranscript(tester, StepGroupingMode.full);
    expect(find.text(_workingHeader(strings), findRichText: true), findsOneWidget);
    expect(find.text(strings.transcriptProcessing, findRichText: true), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without a step group the live answer keeps its "Processing…" spinner', (tester) async {
    final strings = await _pumpTranscript(tester, StepGroupingMode.off);
    expect(find.text(_workingHeader(strings), findRichText: true), findsNothing);
    expect(find.text(strings.transcriptProcessing, findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
