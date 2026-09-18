import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  test('CrustTokens dark has required color values', () {
    const tokens = CrustTokens.dark;
    expect(tokens.background.value, 0xFF0E1116);
    expect(tokens.accent.value, 0xFF7C9CFF);
    expect(tokens.agentWorking.value, 0xFF7C9CFF);
  });
}
