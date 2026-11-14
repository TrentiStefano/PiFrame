import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';

/// Privacy tab (D16, zero telemetry).
class PrivacySection extends StatelessWidget {
  const PrivacySection({
    super.key,
    required this.tokens,
    required this.strings,
  });

  final FrameTokens tokens;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 24, color: tokens.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.privacyTitle,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Text(
            strings.privacyCardContent,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          strings.privacyBulletPoints,
          style: TextStyle(color: tokens.textMuted, fontSize: 12, height: 1.8),
        ),
      ],
    );
  }
}
