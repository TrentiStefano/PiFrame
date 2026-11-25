import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/language/language_settings.dart';
import '../../data/errors/user_facing_error_mapping.dart';
import '../../ui/frame_error_callout.dart';

/// Strings for the repository pane. Falls back to Italian when the provider is unavailable.
AppStrings repositoryStrings(WidgetRef ref) {
  try {
    return ref.watch(appStringsProvider);
  } catch (_) {
    return const AppStrings(AppLanguage.defaultLanguage);
  }
}

Widget repositoryErrorCallout(AppStrings strings, String raw, String title) {
  return Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: FrameErrorCallout(
        keyPrefix: 'repo-files-error',
        title: title,
        error: describeError(raw, strings),
        strings: strings,
      ),
    ),
  );
}
