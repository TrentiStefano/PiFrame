import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../ui/frame_section.dart';

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
    final text = FrameText.of(context);
    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        FrameSection(
          title: strings.privacyTitle,
          child: Text(
            strings.privacyCardContent,
            style: text.bodyLarge.copyWith(color: tokens.textPrimary),
          ),
        ),
        const SizedBox(height: FrameSpace.x4),
        Text(
          strings.privacyBulletPoints,
          style: text.caption.copyWith(color: tokens.textMuted, height: 1.8),
        ),
      ],
    );
  }
}
