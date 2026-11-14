import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_middle_ellipsis.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _longPath =
    r'C:\Repos\PiFrame\wt-p2-widgets-a\apps\pi_frame\lib\main.dart';
const _shortPath = r'appspi_frameibmain.dart';

Widget _host({required double width, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [FrameTokens.dark]),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('FrameMiddleEllipsis.middleEllipsize', () {
    // Fits when the string is at most 20 characters wide.
    bool fits(String s) => s.length <= 20;

    test('returns text unchanged when it fits', () {
      expect(
        FrameMiddleEllipsis.middleEllipsize('short/name.dart', fits),
        'short/name.dart',
      );
    });

    test('keeps the last path segment whole and cuts the head', () {
      final result = FrameMiddleEllipsis.middleEllipsize(_longPath, fits);
      expect(result.length <= 20, isTrue);
      expect(result, contains('…'));
      expect(result, endsWith(r'\main.dart'));
      expect(result.startsWith('C:'), isTrue);
    });

    test('handles forward slashes as separators too', () {
      final result = FrameMiddleEllipsis.middleEllipsize(
        '/home/user/projects/pi_frame/lib/main.dart',
        fits,
      );
      expect(result, endsWith('/main.dart'));
      expect(result, contains('…'));
    });

    test('falls back to an end ellipsis when there is no separator', () {
      final result = FrameMiddleEllipsis.middleEllipsize(
        'a_very_long_name_without_any_separator',
        fits,
      );
      expect(result.endsWith('…'), isTrue);
      expect(result.length <= 20, isTrue);
    });
  });

  testWidgets('shows full text without tooltip when it fits', (tester) async {
    await tester.pumpWidget(
      _host(
        width: 700,
        child: const FrameMiddleEllipsis(
          key: ValueKey('path'),
          text: _shortPath,
          style: TextStyle(fontSize: 14),
        ),
      ),
    );

    expect(find.text(_shortPath), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('truncates in the middle with a tooltip only when truncated', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        width: 200,
        child: const FrameMiddleEllipsis(
          key: ValueKey('path'),
          text: _longPath,
          style: TextStyle(fontSize: 14),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, _longPath);

    final shown = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('path')),
        matching: find.byType(Text),
      ),
    );
    expect(shown.data, contains('…'));
    expect(shown.data, endsWith(r'\main.dart'));
    expect(shown.data, isNot(_longPath));
    // Screen readers get the full path, not the shortened text.
    expect(shown.semanticsLabel, _longPath);

    final size = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('path')),
        matching: find.byType(Text),
      ),
    );
    expect(size.width <= 200, isTrue);
  });
}
