import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/session_titles.dart';

void main() {
  const it = AppStrings(AppLanguage.it);
  const en = AppStrings(AppLanguage.en);

  group('hasChosenSessionName', () {
    test('a user rename or Pi title counts as chosen', () {
      expect(hasChosenSessionName('Refactor parser', 'sess_1'), isTrue);
    });

    test('empty, id-only and daemon default names are provisional', () {
      expect(hasChosenSessionName(null, 'sess_1'), isFalse);
      expect(hasChosenSessionName('  ', 'sess_1'), isFalse);
      expect(hasChosenSessionName('sess_1', 'sess_1'), isFalse);
      expect(hasChosenSessionName('Session 14:05:09', 'sess_1'), isFalse);
      expect(hasChosenSessionName('Session 2:05 PM', 'sess_1'), isFalse);
    });
  });

  group('truncateProvisionalTitle', () {
    test('short text is returned unchanged', () {
      expect(truncateProvisionalTitle('Fix the bug'), 'Fix the bug');
    });

    test('long text is cut to 60 characters with an ellipsis', () {
      final long = 'word ' * 30;
      final title = truncateProvisionalTitle(long);
      expect(title.length, provisionalTitleMaxLength);
      expect(title.endsWith('…'), isTrue);
    });

    test('line breaks and repeated spaces are collapsed', () {
      expect(truncateProvisionalTitle('one\n\n  two'), 'one two');
    });
  });

  group('sessionRailTitle', () {
    String title({
      String? name = 'Session 14:05:09',
      String? qualifiedName,
      String? prompt,
      int? messageCount,
      String? lastPreview,
      AppStrings strings = it,
    }) =>
        sessionRailTitle(
          id: 'sess_1',
          name: name,
          qualifiedName: qualifiedName,
          prompt: prompt,
          messageCount: messageCount,
          lastPreview: lastPreview,
          strings: strings,
        );

    test('a fresh session with no prompt is untitled, never a timestamp', () {
      expect(title(messageCount: 0), 'Nuova sessione');
      expect(title(messageCount: 0, strings: en), 'New session');
    });

    test('the first user prompt becomes the provisional title', () {
      expect(
        title(prompt: 'Add dark mode to the settings page', messageCount: 2),
        'Add dark mode to the settings page',
      );
    });

    test('a chosen name wins over the first prompt', () {
      expect(
        title(name: 'Settings work', prompt: 'Add dark mode', messageCount: 2),
        'Settings work',
      );
    });

    test('a chosen name is qualified by repository when names collide', () {
      expect(
        title(
          name: 'PiFrame',
          qualifiedName: 'v1 / PiFrame',
          messageCount: 2,
        ),
        'v1 / PiFrame',
      );
    });

    test('an unloaded session takes the first prompt the daemon lists', () {
      expect(
        sessionRailTitle(
          id: 'sess_1',
          name: 'Session 14:05:09',
          qualifiedName: null,
          prompt: null,
          listedPrompt: 'Fix the login redirect loop',
          messageCount: 6,
          lastPreview: 'Done, the redirect is fixed',
          strings: it,
        ),
        'Fix the login redirect loop',
      );
    });

    test('a loaded prompt wins over the listed one', () {
      expect(
        sessionRailTitle(
          id: 'sess_1',
          name: 'Session 14:05:09',
          qualifiedName: null,
          prompt: 'Loaded prompt',
          listedPrompt: 'Listed prompt',
          messageCount: 2,
          lastPreview: null,
          strings: it,
        ),
        'Loaded prompt',
      );
    });

    test('a long listed prompt is cut like a loaded one', () {
      final listed = 'word ' * 30;
      final title = sessionRailTitle(
        id: 'sess_1',
        name: null,
        qualifiedName: null,
        prompt: null,
        listedPrompt: listed,
        messageCount: 2,
        lastPreview: null,
        strings: it,
      );
      expect(title.length, provisionalTitleMaxLength);
      expect(title.endsWith('…'), isTrue);
    });

    test('without a loaded prompt, the last message preview is the stopgap', () {
      expect(
        title(messageCount: 4, lastPreview: 'Fixing stream buffer overflow'),
        'Fixing stream buffer overflow',
      );
    });
  });

  group('firstUserPrompt', () {
    test('returns the first non-empty user message', () {
      const state = SessionState(
        sessionId: 's',
        cwd: '/repo',
        entries: [
          SessionEntry(id: 'a', role: 'assistant', text: 'Hi', timestamp: 1),
          SessionEntry(id: 'b', role: 'user', text: '  ', timestamp: 2),
          SessionEntry(id: 'c', role: 'user', text: 'First prompt', timestamp: 3),
        ],
      );
      expect(firstUserPrompt(state), 'First prompt');
    });

    test('is null before any user message', () {
      const state = SessionState(sessionId: 's', cwd: '/repo', entries: []);
      expect(firstUserPrompt(state), isNull);
    });
  });

  group('relativeTimeLabel', () {
    const now = 1000000000000;

    test('unknown times have no label', () {
      expect(relativeTimeLabel(it, null, nowMs: now), isNull);
      expect(relativeTimeLabel(it, 0, nowMs: now), isNull);
    });

    test('scales from now to minutes, hours and days', () {
      expect(relativeTimeLabel(it, now - 10000, nowMs: now), 'ora');
      expect(relativeTimeLabel(it, now - 5 * 60000, nowMs: now), '5 min fa');
      expect(relativeTimeLabel(it, now - 2 * 3600000, nowMs: now), '2 h fa');
      expect(relativeTimeLabel(it, now - 3 * 86400000, nowMs: now), '3 g fa');
      expect(relativeTimeLabel(en, now - 2 * 3600000, nowMs: now), '2 h ago');
    });
  });
}
