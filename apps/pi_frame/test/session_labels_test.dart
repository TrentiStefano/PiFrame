import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_labels.dart';

void main() {
  test('unique session and folder names are unchanged', () {
    expect(folderDisplayNames([r'C:\projects\PiFrame', '/projects/other']), {
      r'C:\projects\PiFrame': 'PiFrame',
      '/projects/other': 'other',
    });
    expect(
      sessionDisplayNames([
        {'id': 'one', 'name': 'PiFrame', 'cwd': r'C:\projects\PiFrame'},
        {'id': 'two', 'name': 'My custom title', 'cwd': '/projects/other'},
      ]),
      {'one': 'PiFrame', 'two': 'My custom title'},
    );
  });

  test('same product versions include their different parent folders', () {
    final sessions = [
      {'id': 'one', 'name': 'PiFrame', 'cwd': r'C:\versions\v1\PiFrame'},
      {'id': 'two', 'name': 'PiFrame', 'cwd': r'C:\versions\v2\PiFrame'},
    ];
    expect(sessionDisplayNames(sessions), {
      'one': 'v1 / PiFrame',
      'two': 'v2 / PiFrame',
    });
    expect(sessions.first['name'], 'PiFrame');
  });

  test('only conflicting suffixes expand to further ancestors', () {
    expect(
      folderDisplayNames([
        '/releases/v1/PiFrame',
        '/branches/v1/PiFrame',
        '/releases/v2/PiFrame',
      ]),
      {
        '/releases/v1/PiFrame': 'releases / v1 / PiFrame',
        '/branches/v1/PiFrame': 'branches / v1 / PiFrame',
        '/releases/v2/PiFrame': 'v2 / PiFrame',
      },
    );
  });

  test('equivalent custom titles retain their name and add folder context', () {
    expect(
      sessionDisplayNames([
        {'id': 'one', 'name': ' Fix   bug ', 'cwd': '/v1/PiFrame'},
        {'id': 'two', 'name': 'fix bug', 'cwd': '/v2/PiFrame'},
      ]),
      {'one': ' Fix   bug  · v1 / PiFrame', 'two': 'fix bug · v2 / PiFrame'},
    );
  });

  test('sessions in the same normalized Windows folder are not relabeled', () {
    expect(
      sessionDisplayNames([
        {'id': 'one', 'name': 'PiFrame', 'cwd': r'C:\versions\v1\PiFrame\'},
        {'id': 'two', 'name': 'PiFrame', 'cwd': 'c:/versions/v1/piframe'},
      ]),
      {'one': 'PiFrame', 'two': 'PiFrame'},
    );
  });

  test('different Windows drives and UNC roots can disambiguate folders', () {
    expect(
      folderDisplayNames([
        r'C:\versions\PiFrame',
        r'D:\versions\PiFrame',
        r'\\server-a\share\PiFrame',
        r'\\server-b\share\PiFrame',
      ]),
      {
        r'C:\versions\PiFrame': 'C: / versions / PiFrame',
        r'D:\versions\PiFrame': 'D: / versions / PiFrame',
        r'\\server-a\share\PiFrame': 'server-a / share / PiFrame',
        r'\\server-b\share\PiFrame': 'server-b / share / PiFrame',
      },
    );
  });

  test('UNC aliases and dot segments are treated as the same folder', () {
    expect(
      sessionDisplayNames([
        {
          'id': 'one',
          'name': 'PiFrame',
          'cwd': r'\\server\share\version\..\PiFrame',
        },
        {'id': 'two', 'name': 'PiFrame', 'cwd': '//SERVER/share/PiFrame/'},
      ]),
      {'one': 'PiFrame', 'two': 'PiFrame'},
    );
  });

  test('missing folders and names retain safe existing fallbacks', () {
    expect(
      sessionDisplayNames([
        {'id': 'one', 'name': 'PiFrame'},
        {'id': 'two', 'name': 'PiFrame', 'cwd': '/v1/PiFrame'},
        {'id': 'three'},
      ]),
      {'one': 'PiFrame', 'two': 'PiFrame', 'three': 'three'},
    );
    expect(folderDisplayNames(['']), {'': 'Sessioni'});
  });

  test('working directories distinguish sessions inside the same git root', () {
    expect(
      sessionDisplayNames([
        {
          'id': 'one',
          'name': 'Product',
          'cwd': '/repo/v1/Product',
          'gitRoot': '/repo',
        },
        {
          'id': 'two',
          'name': 'Product',
          'cwd': '/repo/v2/Product',
          'gitRoot': '/repo',
        },
      ]),
      {'one': 'v1 / Product', 'two': 'v2 / Product'},
    );
  });

  test('live rename metadata wins over the stale session list', () async {
    final container = ProviderContainer(
      overrides: [
        pcpClientProvider.overrideWithValue(null),
        sessionListProvider.overrideWith(
          (ref) async => [
            {'id': 'one', 'name': 'PiFrame', 'cwd': '/v1/PiFrame'},
            {'id': 'two', 'name': 'PiFrame', 'cwd': '/v2/PiFrame'},
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionListProvider.future);
    expect(container.read(sessionDisplayNameProvider('one')), 'v1 / PiFrame');

    final notifier = container.read(sessionStateFamily('one').notifier);
    notifier.state = notifier.state.copyWith(
      sessionName: 'Renamed product',
      cwd: '/v1/PiFrame',
    );
    expect(
      container.read(sessionDisplayNameProvider('one')),
      'Renamed product',
    );
  });
}
