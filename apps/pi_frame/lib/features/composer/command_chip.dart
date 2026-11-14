import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../ui/frame_icon_action.dart';

/// A Pi slash command staged in the composer. It is a separate token, never text: what is left in
/// the text field is only the command's arguments.
class ComposerCommandChip extends StatefulWidget {
  const ComposerCommandChip({
    super.key,
    required this.name,
    required this.sourceLabel,
    required this.removeTooltip,
    required this.running,
    required this.onRemove,
  });

  final String name;
  final String sourceLabel;
  final String removeTooltip;
  final bool running;
  final VoidCallback onRemove;

  @override
  State<ComposerCommandChip> createState() => _ComposerCommandChipState();
}

class _ComposerCommandChipState extends State<ComposerCommandChip>
    with SingleTickerProviderStateMixin {
  // One pass: pop in (first 40%), then the accent glow fades out.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();
  late final Animation<double> _scale = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.4, curve: Curves.easeOutBack),
  );
  late final Animation<double> _glow = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.15, 1, curve: Curves.easeOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _intro.value = 1;
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: '/${widget.name}',
      button: false,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, child) => Transform.scale(
          scale: 0.7 + 0.3 * _scale.value,
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: _scale.value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radiusSm + 2),
                boxShadow: [
                  BoxShadow(
                    color: tokens.accent.withValues(
                      alpha: 0.45 * (1 - _glow.value),
                    ),
                    blurRadius: 14 * (1 - _glow.value),
                    spreadRadius: 1.5 * (1 - _glow.value),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          // No vertical padding: the 28 px remove control sets the chip height.
          padding: const EdgeInsets.fromLTRB(6, 0, 2, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tokens.accent.withValues(alpha: widget.running ? 0.32 : 0.22),
                tokens.accent.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm + 2),
            border: Border.all(color: tokens.accent.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: widget.running
                    ? SizedBox(
                        key: const ValueKey('running'),
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: tokens.accent,
                        ),
                      )
                    : Icon(
                        Icons.terminal_rounded,
                        key: const ValueKey('idle'),
                        size: 14,
                        color: tokens.accent,
                      ),
              ),
              const SizedBox(width: 5),
              Text(
                '/${widget.name}',
                style: FrameText.of(context).label.copyWith(color: tokens.textPrimary, fontFamily: tokens.monoFontFamily, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  widget.sourceLabel,
                  style: FrameText.of(context).caption.copyWith(color: tokens.accent, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                ),
              ),
              const SizedBox(width: 2),
              // A focusable 28 px control (plan 6.1, 2.6): reachable by Tab and Enter.
              FrameIconAction(
                key: const ValueKey('composer-command-chip-remove'),
                icon: Icons.close_rounded,
                tooltip: widget.removeTooltip,
                onPressed: widget.running ? null : widget.onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
