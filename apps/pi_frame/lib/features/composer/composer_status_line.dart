import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../ui/frame_activity_indicator.dart';
import '../../ui/motion.dart';

/// Status line above the composer field while Pi is answering (plan 4.3).
///
/// It takes 28 px only while [active] and reserves no space when idle. It enters with a 4 px
/// rise and a fade (`FrameMotion.small`) and leaves faster (`FrameMotion.smallExit`). Under
/// reduced motion it cross-fades without moving.
class ComposerRunStatusLine extends StatelessWidget {
  const ComposerRunStatusLine({
    super.key,
    required this.active,
    required this.startedAt,
    required this.label,
    required this.interruptLabel,
    required this.onInterrupt,
  });

  final bool active;

  /// Epoch milliseconds when the run started. Null counts from the moment the line appears.
  final int? startedAt;
  final String label;
  final String interruptLabel;
  final VoidCallback? onInterrupt;

  static const double _rise = FrameSpace.x1;

  @override
  Widget build(BuildContext context) {
    final reduced = FrameMotion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? FrameMotion.crossFade : FrameMotion.small,
      reverseDuration: reduced ? FrameMotion.crossFade : FrameMotion.smallExit,
      switchInCurve: FrameMotion.enterCurve,
      switchOutCurve: FrameMotion.enterCurve,
      transitionBuilder: (child, animation) {
        if (reduced) return FadeTransition(opacity: animation, child: child);
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, (1 - animation.value) * _rise),
              child: child,
            ),
          ),
        );
      },
      child: active
          ? _ComposerRunStatusRow(
              key: const ValueKey('composer-status-line'),
              startedAt: startedAt,
              label: label,
              interruptLabel: interruptLabel,
              onInterrupt: onInterrupt,
            )
          : const SizedBox(key: ValueKey('composer-status-idle')),
    );
  }
}

/// `m:ss`, or `h:mm:ss` from one hour on. Negative durations show as zero.
String formatRunElapsed(Duration elapsed) {
  final total = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

class _ComposerRunStatusRow extends StatefulWidget {
  const _ComposerRunStatusRow({
    super.key,
    required this.startedAt,
    required this.label,
    required this.interruptLabel,
    required this.onInterrupt,
  });

  final int? startedAt;
  final String label;
  final String interruptLabel;
  final VoidCallback? onInterrupt;

  @override
  State<_ComposerRunStatusRow> createState() => _ComposerRunStatusRowState();
}

class _ComposerRunStatusRowState extends State<_ComposerRunStatusRow> {
  late final int _fallbackStart = DateTime.now().millisecondsSinceEpoch;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final start = widget.startedAt ?? _fallbackStart;
    final elapsed = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - start,
    );
    // Tests get a static glyph: an endless spinner would keep pumpAndSettle from ever returning.
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    final danger = tokens.signalDanger;

    return SizedBox(
      height: FrameSize.rowList,
      child: Row(
        children: [
          SizedBox(
            width: FrameSize.icon - FrameSpace.x1,
            height: FrameSize.icon - FrameSpace.x1,
            child: isTest
                ? Icon(
                    Icons.sync_outlined,
                    size: FrameSize.icon - FrameSpace.x1,
                    color: tokens.agentWorking,
                  )
                : FrameActivityIndicator(size: FrameSize.icon - FrameSpace.x1, 
                    strokeWidth: 1.5,
                    color: tokens.agentWorking,
                  ),
          ),
          const SizedBox(width: FrameSpace.x2),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.label.copyWith(color: tokens.textSecondary),
            ),
          ),
          const SizedBox(width: FrameSpace.x2),
          Text(
            formatRunElapsed(elapsed),
            maxLines: 1,
            style: text.mono.copyWith(color: tokens.textMuted),
          ),
          if (widget.onInterrupt != null) ...[
            const SizedBox(width: FrameSpace.x2),
            TextButton.icon(
              key: const ValueKey('composer-status-interrupt'),
              onPressed: widget.onInterrupt,
              style: TextButton.styleFrom(
                foregroundColor: danger,
                minimumSize: const Size(0, FrameSize.hitMin),
                padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.stop_outlined, size: FrameSize.icon, color: danger),
              label: Text(
                widget.interruptLabel,
                maxLines: 1,
                style: text.label.copyWith(
                  color: danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
