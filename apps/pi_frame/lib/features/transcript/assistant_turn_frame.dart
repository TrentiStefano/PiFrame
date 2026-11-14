import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../ui/motion.dart';

/// Height of the meta line above every assistant turn (plan 4.1). It is fixed
/// and laid out from the first token, so a streaming turn and the same turn
/// once settled put their content at the same y.
const double kAssistantMetaLineHeight = 24;

/// Widest reading measure for assistant prose, centred in wide panes (4.1).
const double kAssistantReadingMeasure = 760;

/// Shared geometry for a streaming or settled assistant turn: a borderless
/// 24 px meta line (role label, optional status tag, elapsed chip, copy
/// action) above the turn [body].
///
/// Streaming and settled turns both render through this widget, so only the
/// meta-line contents change between them, never the height or position of
/// the body. The copy action stays in the tree at all times; it fades in while
/// the pointer is over the turn or focus is inside it, so keyboard users can
/// Tab to it.
class AssistantTurnFrame extends StatelessWidget {
  final String label;
  final Widget body;

  /// Optional status tag at the right of the meta line, for example the
  /// neutral "Interrotto" tag.
  final Widget? statusTag;

  /// Optional elapsed chip. While streaming this is the live timer; once
  /// settled it is the final duration.
  final Widget? elapsedChip;

  /// Copy action. Null while the turn is streaming.
  final VoidCallback? onCopy;
  final String? copyTooltip;
  final Key? copyKey;

  const AssistantTurnFrame({
    super.key,
    required this.label,
    required this.body,
    this.statusTag,
    this.elapsedChip,
    this.onCopy,
    this.copyTooltip,
    this.copyKey,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAssistantReadingMeasure),
        child: HoverRevealBuilder(
          builder: (context, revealed) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: kAssistantMetaLineHeight,
                child: Row(
                  children: [
                    // Icon size 14 sits inside the 24 px meta line; it is not a
                    // control icon.
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 14,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: FrameSpace.x1),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.label.copyWith(color: tokens.textSecondary),
                      ),
                    ),
                    const Spacer(),
                    if (statusTag != null) ...[
                      statusTag!,
                      const SizedBox(width: FrameSpace.x2),
                    ],
                    if (elapsedChip != null) ...[
                      elapsedChip!,
                      const SizedBox(width: FrameSpace.x2),
                    ],
                    if (onCopy != null)
                      AnimatedOpacity(
                        opacity: revealed ? 1 : 0,
                        duration: FrameMotion.micro,
                        child: SizedBox(
                          width: kAssistantMetaLineHeight,
                          height: kAssistantMetaLineHeight,
                          child: IconButton(
                            key: copyKey,
                            tooltip: copyTooltip,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: kAssistantMetaLineHeight,
                              height: kAssistantMetaLineHeight,
                            ),
                            iconSize: FrameSize.icon,
                            onPressed: onCopy,
                            icon: Icon(
                              Icons.copy_outlined,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: FrameSpace.x2),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// Small flat chip for the meta line: an [icon] and a [label], tinted with
/// [color]. Used for the elapsed time on both streaming and settled turns.
class AssistantMetaChip extends StatelessWidget {
  final Key? chipKey;
  final IconData icon;
  final String label;
  final Color? color;

  const AssistantMetaChip({
    super.key,
    this.chipKey,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tone = color ?? tokens.textMuted;
    return Container(
      key: chipKey,
      padding: const EdgeInsets.symmetric(
        horizontal: FrameSpace.x2 - 1,
        vertical: FrameSpace.x1 / 2,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tone),
          const SizedBox(width: 3),
          Text(
            label,
            style: FrameText.of(context).caption.copyWith(
              color: tone,
              fontFamily: tokens.monoFontFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds [builder] with `revealed`: true while the pointer is over the region
/// or focus is inside it. Used for hover-only actions (copy, fork) that must
/// stay reachable by keyboard.
class HoverRevealBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool revealed) builder;

  const HoverRevealBuilder({super.key, required this.builder});

  @override
  State<HoverRevealBuilder> createState() => _HoverRevealBuilderState();
}

class _HoverRevealBuilderState extends State<HoverRevealBuilder> {
  bool _hovered = false;
  bool _focusWithin = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focusWithin = focused),
        child: widget.builder(context, _hovered || _focusWithin),
      ),
    );
  }
}
