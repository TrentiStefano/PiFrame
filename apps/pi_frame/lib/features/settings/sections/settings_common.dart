import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// `dart:io` Platform throws `UnsupportedError` on the web build, so every OS
/// branch in settings goes through this web-safe helper.
bool get isWindowsOs => !kIsWeb && Platform.isWindows;

Widget buildSettingsInfoCard(FrameTokens tokens, List<Widget> children) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      border: Border.all(color: tokens.border),
    ),
    child: Column(children: children),
  );
}

Widget buildSettingsInfoRow(FrameTokens tokens, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: TextStyle(color: tokens.textSecondary, fontSize: 13),
        );
        final valueWidget = Text(
          value,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 4), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: valueWidget),
          ],
        );
      },
    ),
  );
}
