import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../data/language/language_settings.dart';
import '../data/language/strings_settings.dart';
import '../domain/errors/user_facing_error.dart';
import 'frame_callout.dart';

/// An error block for a failed load or action, built on [FrameCallout] with
/// the danger tone.
///
/// Shows a context [title] ("Impossibile caricare i pacchetti"), the mapped
/// [error] title and hint, a Riprova action when the error is retryable and
/// [onRetry] is given, and the raw text behind a collapsed "Dettagli" toggle.
///
/// [keyPrefix] builds the widget keys (all from `<prefix>-error`):
/// `<prefix>-error` (root), `<prefix>-error-title`, `<prefix>-retry`,
/// `<prefix>-error-details-toggle` and `<prefix>-error-details`.
/// Task 8.2 changed the details keys from `<prefix>-details-toggle` and
/// `<prefix>-details` (now under `<prefix>-error-`).
class FrameErrorCallout extends StatelessWidget {
  final String keyPrefix;
  final String title;
  final UserFacingError error;
  final AppStrings strings;
  final VoidCallback? onRetry;

  const FrameErrorCallout({
    super.key,
    required this.keyPrefix,
    required this.title,
    required this.error,
    required this.strings,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final canRetry = error.retryable && onRetry != null;
    final hint = error.hint;
    return FrameCallout(
      keyPrefix: '$keyPrefix-error',
      tone: FrameCalloutTone.danger,
      title: title,
      strings: strings,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error.title, style: text.body),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: FrameSpace.x1),
              child: Text(
                hint,
                style: text.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
        ],
      ),
      action: canRetry
          ? OutlinedButton.icon(
              key: ValueKey('$keyPrefix-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: FrameSize.icon),
              label: Text(strings.retryAction),
            )
          : null,
      details: error.details,
    );
  }
}
