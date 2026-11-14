import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../data/language/language_settings.dart';
import '../data/language/strings_settings.dart';
import 'motion.dart';

/// Severity of a [FrameCallout]. Drives the icon, the border and the title tint.
enum FrameCalloutTone { info, warning, danger }

/// An inline message block: a [title], an optional [body], an optional
/// [action] widget and an optional raw [details] text behind a collapsed
/// "Dettagli" disclosure.
///
/// Keys (all derived from [keyPrefix]): the root is the prefix itself, the
/// title is `prefix-title`, the disclosure toggle is `prefix-details-toggle`
/// and the details text is `prefix-details`. The [action] keeps whatever key
/// the caller gives it.
///
/// [FrameErrorCallout] (task 1.6) can be rebuilt on this widget as
/// FrameCallout(tone: danger, title: title, body: the mapped error title and
/// hint, action: the Riprova button when retryable, details: error.details).
/// That changes its details key from `-details-toggle` to the prefix-derived
/// one, so its test keys need updating then.
class FrameCallout extends StatefulWidget {
  final String keyPrefix;
  final FrameCalloutTone tone;
  final String title;
  final Widget? body;
  final Widget? action;
  final String? details;
  final AppStrings strings;

  const FrameCallout({
    super.key,
    required this.keyPrefix,
    this.tone = FrameCalloutTone.info,
    required this.title,
    this.body,
    this.action,
    this.details,
    required this.strings,
  });

  @override
  State<FrameCallout> createState() => _FrameCalloutState();
}

class _FrameCalloutState extends State<FrameCallout> {
  bool _showDetails = false;

  Color _toneColor(FrameTokens tokens) => switch (widget.tone) {
        FrameCalloutTone.info => tokens.info,
        FrameCalloutTone.warning => tokens.warning,
        FrameCalloutTone.danger => tokens.danger,
      };

  IconData get _toneIcon => switch (widget.tone) {
        FrameCalloutTone.info => Icons.info_outline,
        FrameCalloutTone.warning => Icons.warning_amber_rounded,
        FrameCalloutTone.danger => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final prefix = widget.keyPrefix;
    final tone = _toneColor(tokens);
    final details = widget.details;
    return Container(
      key: ValueKey(prefix),
      padding: const EdgeInsets.all(FrameSpace.x4),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tone),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_toneIcon, color: tone, size: FrameSize.iconLg),
              const SizedBox(width: FrameSpace.x2),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    key: ValueKey('$prefix-title'),
                    style: text.bodyLarge.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (widget.body != null) ...[
            const SizedBox(height: FrameSpace.x2),
            DefaultTextStyle.merge(
              style: text.body.copyWith(color: tokens.textPrimary),
              child: widget.body!,
            ),
          ],
          if (widget.action != null || details != null) ...[
            const SizedBox(height: FrameSpace.x3),
            Wrap(
              spacing: FrameSpace.x2,
              runSpacing: FrameSpace.x1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.action != null) widget.action!,
                if (details != null)
                  TextButton.icon(
                    key: ValueKey('$prefix-details-toggle'),
                    onPressed: () =>
                        setState(() => _showDetails = !_showDetails),
                    icon: Icon(
                      _showDetails ? Icons.expand_less : Icons.expand_more,
                      size: FrameSize.icon,
                    ),
                    label: Text(widget.strings.detailsAction),
                  ),
              ],
            ),
          ],
          if (details != null)
            FrameExpandable(
              expanded: _showDetails,
              child: Padding(
                padding: const EdgeInsets.only(top: FrameSpace.x2),
                child: SelectableText(
                  details,
                  key: ValueKey('$prefix-details'),
                  style: text.mono.copyWith(color: tokens.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
