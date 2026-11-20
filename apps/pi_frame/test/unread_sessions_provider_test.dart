import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/sessions_sidebar/unread_sessions_provider.dart';

void main() {
  Map<String, dynamic> listed(String id, int at) => {'id': id, 'lastActivityAt': at};

  test('activity in a session that is not open marks it unread', () {
    final unread = UnreadSessionsNotifier(const []);
    // The first listing is only a baseline: nothing lights up at startup.
    unread.noteListing([listed('a', 100), listed('b', 100)], activeId: 'a');
    expect(unread.state, isEmpty);

    unread.noteListing([listed('a', 200), listed('b', 200)], activeId: 'a');
    expect(unread.state, {'b'}, reason: 'the open session is never unread');

    // No new activity: unchanged. A brand-new session is not flagged.
    unread.noteListing([listed('a', 200), listed('b', 200), listed('c', 300)], activeId: 'a');
    expect(unread.state, {'b'});

    unread.markRead('b');
    expect(unread.state, isEmpty);
  });

  test('deleted sessions are forgotten', () {
    final unread = UnreadSessionsNotifier(const ['gone', 'kept']);
    unread.noteListing([listed('kept', 1)]);
    expect(unread.state, {'kept'});
  });
}
