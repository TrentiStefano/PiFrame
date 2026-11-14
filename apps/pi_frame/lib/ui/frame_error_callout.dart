import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../data/language/language_settings.dart';
import '../data/language/strings_settings.dart';
import '../domain/errors/user_facing_error.dart';
import 'motion.dart';

/// An error block for a failed load or action.
///
/// Shows a context [title] ("Impossibile caricare i pacchetti"), the mapped
/// [error] title and hint, a Riprova action when the error is retryable and
/// [onRetry] is given, and the raw text behind a collapsed "Dettagli" toggle.
///
/// [keyPrefix] builds the widget keys: `<prefix>-error`, `<prefix>-error-title`,
/// `<prefix>-retry`, `<prefix>-details-toggle` and `<prefix>-details`.
class FrameErrorCallout extends StatefulWidget {
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
  State<FrameErrorCallout> createState() => _FrameErrorCalloutState();
}

class _FrameErrorCalloutState extends State<FrameErrorCallout> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = widget.strings;
    final error = widget.error;
    final prefix = widget.keyPrefix;
    final canRetry = error.retryable && widget.onRetry != null;
    return Container(
      key: ValueKey('$prefix-error'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.danger),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: tokens.danger, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  key: ValueKey('$prefix-error-title'),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error.title,
            style: TextStyle(color: tokens.textPrimary, fontSize: 13),
          ),
          if (error.hint != null) ...[
            const SizedBox(height: 4),
            Text(
              error.hint!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (canRetry)
                OutlinedButton.icon(
                  key: ValueKey('$prefix-retry'),
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(strings.retryAction),
                ),
              TextButton.icon(
                key: ValueKey('$prefix-details-toggle'),
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(strings.detailsAction),
              ),
            ],
          ),
          FrameExpandable(
            expanded: _showDetails,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                error.details,
                key: ValueKey('$prefix-details'),
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
