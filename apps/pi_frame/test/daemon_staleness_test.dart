import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/update/daemon_staleness.dart';

void main() {
  final startedAt = DateTime(2026, 11, 26, 7, 42);

  group('isRunningDaemonStale', () {
    test('an older daemon version is stale', () {
      expect(isRunningDaemonStale(appVersion: '1.5.1', runningVersion: '1.5.0', runningStartedAt: startedAt), isTrue);
    });

    // Regression for #103: rebuilding or updating the app with the same version number left the
    // daemon started from the previous build running.
    test('a same-version daemon started before the current daemon build is stale', () {
      expect(
        isRunningDaemonStale(
          appVersion: '1.5.1',
          runningVersion: '1.5.1',
          runningStartedAt: startedAt,
          sidecarBuiltAt: startedAt.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
    });

    test('a same-version daemon started after the current daemon build is kept', () {
      expect(
        isRunningDaemonStale(
          appVersion: '1.5.1',
          runningVersion: '1.5.1',
          runningStartedAt: startedAt,
          sidecarBuiltAt: startedAt.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('a newer daemon version is kept, so two installed versions never restart each other', () {
      expect(
        isRunningDaemonStale(
          appVersion: '1.5.1',
          runningVersion: '1.6.0',
          runningStartedAt: startedAt,
          sidecarBuiltAt: startedAt.add(const Duration(minutes: 30)),
        ),
        isFalse,
      );
    });

    test('unknown versions and an unknown build time are never stale', () {
      expect(isRunningDaemonStale(appVersion: '1.5.1', runningVersion: null, runningStartedAt: null), isFalse);
      expect(isRunningDaemonStale(appVersion: '1.5.1', runningVersion: '1.5.1', runningStartedAt: startedAt), isFalse);
    });
  });
}
