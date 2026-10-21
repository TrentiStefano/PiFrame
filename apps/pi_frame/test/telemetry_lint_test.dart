import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Strict D16 Telemetry Ban: No remote analytics or external network calls in apps/pi_frame/lib', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final violations = <String>[];

    // Disallowed telemetry import patterns
    final telemetryImportRegex = RegExp(
      r'''import\s+['"].*(sentry|firebase_analytics|mixpanel|amplitude|posthog|segment).*['"]''',
      caseSensitive: false,
    );

    // Disallowed telemetry SDK invocations
    final telemetrySdkRegex = RegExp(
      r'''\b(Sentry|FirebaseAnalytics|Mixpanel|AmplitudeClient|PosthogClient)\.''',
    );

    // External outbound URL pattern (allow only loopback, localhost, and json schemas)
    final remoteUrlRegex = RegExp(
      r'''(http\.get|http\.post|http\.put|http\.delete|HttpClient|WebSocket\.connect)\s*\(\s*Uri\.parse\(\s*['"]https?:\/\/(?!127\.0\.0\.1|localhost|json-schema\.org)''',
    );

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

        if (telemetryImportRegex.hasMatch(line)) {
          violations.add('${file.path}:${i + 1}: Contains prohibited telemetry package import: $line');
        }

        if (telemetrySdkRegex.hasMatch(line)) {
          violations.add('${file.path}:${i + 1}: Contains prohibited telemetry SDK call: $line');
        }

        if (remoteUrlRegex.hasMatch(line)) {
          violations.add('${file.path}:${i + 1}: Found prohibited external network call: $line');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'D16 strictly prohibits any remote telemetry or external network calls. Violations found:\n${violations.join('\n')}',
    );
  });
}
