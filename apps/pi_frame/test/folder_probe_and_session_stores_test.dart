import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/dialogs/folder_probe.dart';
import 'package:pi_frame/features/sessions_sidebar/removed_repos_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/unread_sessions_provider.dart';

import 'support/fake_platform_services.dart';

void main() {
  group('folder probe reads the folder through the file-system service', () {
    test('an empty path is empty and a missing folder is not found', () {
      final files = FakeFileSystemService();
      expect(probeFolder('  ', files).status, FolderStatus.empty);
      expect(probeFolder('/missing', files).status, FolderStatus.notFound);
    });

    test('an existing folder without a .git marker is a plain folder', () {
      final files = FakeFileSystemService()..directories.add('/work/app');
      final probe = probeFolder('/work/app', files);
      expect(probe.status, FolderStatus.folder);
      expect(probe.isValid, isTrue);
    });

    test('a git repository reports the branch named by HEAD', () {
      final files = FakeFileSystemService()
        ..directories.addAll({'/work/app', '/work/app/.git'})
        ..files['/work/app/.git/HEAD'] = 'ref: refs/heads/main\n';
      final probe = probeFolder('/work/app', files);
      expect(probe.status, FolderStatus.gitRepo);
      expect(probe.branch, 'main');
    });

    test('a .git file (worktree) points at the real git directory', () {
      final files = FakeFileSystemService()
        ..directories.add('/work/wt')
        ..files['/work/wt/.git'] = 'gitdir: /repos/app/.git/worktrees/wt'
        ..files['/repos/app/.git/worktrees/wt/HEAD'] = 'ref: refs/heads/feature';
      final probe = probeFolder('/work/wt', files);
      expect(probe.status, FolderStatus.gitRepo);
      expect(probe.branch, 'feature');
    });

    test('a detached HEAD is a git repository without a branch', () {
      final files = FakeFileSystemService()
        ..directories.addAll({'/work/app', '/work/app/.git'})
        ..files['/work/app/.git/HEAD'] = '3f2a9c1d\n';
      final probe = probeFolder('/work/app', files);
      expect(probe.status, FolderStatus.gitRepo);
      expect(probe.branch, isNull);
    });
  });

  group('sidebar stores keep their state in the user data file', () {
    test('unread sessions load from and save to unread_sessions.json', () {
      final storage = FakeUserDataService()..files['unread_sessions.json'] = '["a"]';
      final notifier = UnreadSessionsNotifier(null, storage);
      expect(notifier.state, {'a'});

      notifier.markUnread('b');
      expect(storage.files['unread_sessions.json'], '["a","b"]');
    });

    test('unread sessions built from a set never touch the user data file', () {
      final storage = FakeUserDataService();
      final notifier = UnreadSessionsNotifier(const ['a'], null);
      notifier.markUnread('b');
      expect(storage.writes, isEmpty);
    });

    test('removed repos save to removed_repos.json', () {
      final storage = FakeUserDataService();
      final notifier = RemovedReposNotifier(storage);
      notifier.removeRepo('/work/app');
      expect(storage.files['removed_repos.json'], '["/work/app"]');

      notifier.restoreRepo('/work/app');
      expect(storage.files['removed_repos.json'], '[]');
    });
  });
}
