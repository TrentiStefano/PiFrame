import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// `dart:io` Platform throws `UnsupportedError` on the web build, so every OS
/// branch in settings goes through this web-safe helper.
bool get isWindowsOs => !kIsWeb && Platform.isWindows;

/// A form field box at the form row height (`FrameSize.rowForm`), with the
/// input outline. Dropdowns and text fields in settings sit inside one.
Widget buildSettingsFieldBox(FrameTokens tokens, Widget child) {
  return Container(
    height: FrameSize.rowForm,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
    decoration: BoxDecoration(
      color: tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      border: Border.all(color: tokens.inputBorder),
    ),
    child: child,
  );
}

/// A group of label/value rows inside a bordered box. It has no background
/// of its own, so a list tile placed inside it keeps its ink and splashes.
Widget buildSettingsInfoCard(FrameTokens tokens, List<Widget> children) {
  return Container(
    padding: const EdgeInsets.all(FrameSpace.x4),
    decoration: BoxDecoration(
      border: Border.all(color: tokens.border),
      borderRadius: BorderRadius.circular(tokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

Widget buildSettingsInfoRow(FrameTokens tokens, String label, String value) {
  final text = FrameText.fromTokens(tokens);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: FrameSpace.x2),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: text.body.copyWith(color: tokens.textSecondary),
        );
        final valueWidget = Text(
          value,
          style: text.body.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: FrameSpace.x1),
              valueWidget,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: FrameSpace.x6),
            Expanded(flex: 2, child: valueWidget),
          ],
        );
      },
    ),
  );
}
