import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/update/github_update_client.dart';
import 'package:pi_frame/data/update/update_providers.dart';
import 'package:pi_frame/data/update/update_storage.dart';
import 'package:pi_frame/domain/update/update_models.dart';
import 'package:pi_frame/features/settings/updates_section.dart';
import 'package:pi_frame/ui/precision.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _NoopUpdateClient implements UpdateClient {
  @override
  Future<AppRelease?> fetchLatestRelease() async => null;

  @override
  Stream<DownloadProgress> downloadAsset({
    required ReleaseAsset asset,
    required String destinationPath,
    Future<void>? cancelSignal,
  }) async* {}
}

void main() {
  testWidgets('enabled filled button in Aggiornamenti gets press feedback', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateClientProvider.overrideWithValue(_NoopUpdateClient()),
          updateStorageProvider.overrideWithValue(MemoryUpdateStorage()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: const Scaffold(body: UpdatesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('check_for_updates_button'));
    expect(button, findsOneWidget);
    expect(find.ancestor(of: button, matching: find.byType(PressFeedback)), findsOneWidget);
    final feedback = tester.widget<PressFeedback>(find.ancestor(of: button, matching: find.byType(PressFeedback)));
    expect(feedback.enabled, isTrue);
  });
}
