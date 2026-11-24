import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/changelog/changelog_service.dart';
import 'package:pi_frame/data/changelog/changelog_store.dart';
import 'package:pi_frame/domain/changelog/changelog_models.dart';

import 'support/fake_platform_services.dart';

void main() {
  group('ChangelogParser', () {
    const parser = ChangelogParser();

    const sampleMarkdown = '''
# Changelog

## [1.5.0](https://github.com/TrentiStefano/PiFrame/compare/v1.4.1...v1.5.0) (2026-11-20)

### Features

* add agents and workflows side panel ([6d84723](https://github.com/TrentiStefano/PiFrame/commit/6d84723))
* **chat:** add read-only /side conversations ([2e48ed2](https://github.com/TrentiStefano/PiFrame/commit/2e48ed2))
* **docs:** update manual guides ([1234567](https://github.com/TrentiStefano/PiFrame/commit/1234567))

### Bug Fixes

* **agentd:** reliable remote web delivery ([67eb888](https://github.com/TrentiStefano/PiFrame/commit/67eb888))
* **ci:** run verify in a worktree ([2cd9c7d](https://github.com/TrentiStefano/PiFrame/commit/2cd9c7d))
* **test:** decouple update tests ([6bdf73b](https://github.com/TrentiStefano/PiFrame/commit/6bdf73b))
* **transcript:** ignore nested scroll metrics ([4eb0b2d](https://github.com/TrentiStefano/PiFrame/commit/4eb0b2d))

### Documentation

* update readme ([abcdef1](https://github.com/TrentiStefano/PiFrame/commit/abcdef1))

## [1.4.1] (2026-11-08)

### Bug Fixes

* **web:** fix phone layout ([6fa857e](https://github.com/TrentiStefano/PiFrame/commit/6fa857e))
''';

    test('parseChangelog extracts releases and filters fix and feat only', () {
      final releases = parser.parseChangelog(sampleMarkdown);
      expect(releases.length, 2);

      final r150 = releases[0];
      expect(r150.version, '1.5.0');
      expect(r150.date, '2026-11-20');

      // Features: only feat, docs omitted
      expect(r150.features.length, 2);
      expect(r150.features[0].scope, isNull);
      expect(r150.features[0].message, 'add agents and workflows side panel');
      expect(r150.features[0].commitHash, '6d84723');
      expect(r150.features[0].isFeature, isTrue);

      expect(r150.features[1].scope, 'chat');
      expect(r150.features[1].message, 'add read-only /side conversations');
      expect(r150.features[1].commitHash, '2e48ed2');

      // Fixes: ci and test are filtered out!
      expect(r150.fixes.length, 2);
      expect(r150.fixes[0].scope, 'agentd');
      expect(r150.fixes[0].message, 'reliable remote web delivery');
      expect(r150.fixes[0].commitHash, '67eb888');
      expect(r150.fixes[0].isFeature, isFalse);

      expect(r150.fixes[1].scope, 'transcript');
      expect(r150.fixes[1].message, 'ignore nested scroll metrics');

      // Second release
      final r141 = releases[1];
      expect(r141.version, '1.4.1');
      expect(r141.features, isEmpty);
      expect(r141.fixes.length, 1);
      expect(r141.fixes[0].scope, 'web');
      expect(r141.fixes[0].message, 'fix phone layout');
    });

    test('parseReleaseBody parses single release body from GitHub API', () {
      const gitHubBody = '''
### Features

* **settings:** add provider subtitle to model dropdowns ([de5ece3](https://github.com/TrentiStefano/PiFrame/commit/de5ece3))

### Bug Fixes

* **workspace:** do not collapse git changes when opening agents sidecar ([0724323](https://github.com/TrentiStefano/PiFrame/commit/0724323))
* **chore:** bump dependencies ([1111111](https://github.com/TrentiStefano/PiFrame/commit/1111111))
''';

      final release = parser.parseReleaseBody('1.5.0', gitHubBody, date: '2026-11-20');
      expect(release.version, '1.5.0');
      expect(release.date, '2026-11-20');
      expect(release.features.length, 1);
      expect(release.features.first.scope, 'settings');
      expect(release.features.first.message, 'add provider subtitle to model dropdowns');
      expect(release.features.first.commitHash, 'de5ece3');

      expect(release.fixes.length, 1);
      expect(release.fixes.first.scope, 'workspace');
      expect(release.fixes.first.message, 'do not collapse git changes when opening agents sidecar');
    });
  });

  group('ChangelogStore', () {
    const statePath = '/fake/home/.piframe/changelog_state.json';
    const firstRunPath = '/fake/home/.piframe/app_first_run.json';
    late FakeFileSystemService files;
    final store = ChangelogStore.instance;

    setUp(() {
      files = FakeFileSystemService();
      store.setStorageForTesting(files: files, statePath: statePath, firstRunPath: firstRunPath);
    });

    tearDown(() {
      store.setStorageForTesting();
    });

    test('fresh install without firstRun file does not show changelog and marks version', () {
      expect(store.shouldShowChangelog('1.5.0'), isFalse);
      expect(store.getLastSeenVersion(), '1.5.0');
    });

    test('existing user upgrading version shows changelog', () {
      files.files[firstRunPath] = '{"introPlayed":true}';
      expect(store.shouldShowChangelog('1.5.0'), isTrue);

      store.setLastSeenVersion('1.5.0');
      expect(store.shouldShowChangelog('1.5.0'), isFalse);

      // Upgraded to next version
      expect(store.shouldShowChangelog('1.6.0'), isTrue);
    });
  });

  group('ChangelogService', () {
    test('loads matching release from custom loader', () async {
      final service = ChangelogService(
        customLoader: () async => '''
## [1.5.0] (2026-11-20)

### Features

* **git:** add sync button
''',
      );

      final release = await service.loadRelease(version: '1.5.0');
      expect(release, isNotNull);
      expect(release!.version, '1.5.0');
      expect(release.features.length, 1);
      expect(release.features.first.message, 'add sync button');
    });
  });
}
