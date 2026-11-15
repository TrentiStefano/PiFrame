import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../ui/motion.dart';
import 'side_panel.dart';
import 'side_provider.dart';

/// Narrowest side conversation and narrowest chat beside it (plan task 10.1).
const double kSideMinWidth = 320;
const double kSideChatMinWidth = 720;

/// Width of the draggable divider between the chat and the side thread.
const double kSideDividerWidth = 6;

/// Share of the available width the side thread takes when the split opens.
const double kSideSplitFraction = 0.4;

/// Lays the chat and the side conversation side by side (plan task 10.1, Spec C).
///
/// The side thread takes [kSideSplitFraction] of the width, between a minimum of
/// [kSideMinWidth] for each side, and the chat never gets less than
/// [kSideChatMinWidth]. When the pane is too narrow for that, the side thread takes
/// the whole pane and the chat waits behind it, with a back button to return.
///
/// Opening animates the width with the panel curve (240 ms); closing takes 180 ms.
/// The content fades in once the width is past half way. Reduced motion
/// cross-fades in 120 ms with no movement. Ctrl+Shift+B toggles without animation.
class SideSplit extends ConsumerStatefulWidget {
  final String sessionId;
  final Widget main;

  const SideSplit({super.key, required this.sessionId, required this.main});

  @override
  ConsumerState<SideSplit> createState() => _SideSplitState();
}

class _SideSplitState extends ConsumerState<SideSplit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open;
  ProviderSubscription<SideThreadState>? _threadSub;
  bool _reduced = false;
  bool _lastOpen = false;

  /// Side share of the width, changed by dragging the divider.
  double _fraction = kSideSplitFraction;

  /// Width available to the two sides on the last layout, for drag maths.
  double _available = 1;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: FrameMotion.panel,
      reverseDuration: FrameMotion.panelExit,
    );
    _lastOpen = ref.read(sideThreadFamily(widget.sessionId)).isOpen;
    _open.value = _lastOpen ? 1 : 0;
    _threadSub = ref.listenManual<SideThreadState>(
      sideThreadFamily(widget.sessionId),
      (_, next) => _sync(next.isOpen),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = FrameMotion.reduced(context);
    _open.duration = _reduced ? FrameMotion.crossFade : FrameMotion.panel;
    _open.reverseDuration = _reduced
        ? FrameMotion.crossFade
        : FrameMotion.panelExit;
  }

  @override
  void dispose() {
    _threadSub?.close();
    _open.dispose();
    super.dispose();
  }

  void _sync(bool open) {
    if (open == _lastOpen) return;
    _lastOpen = open;
    final instant = ref.read(sideInstantToggleProvider);
    if (instant) {
      ref.read(sideInstantToggleProvider.notifier).state = false;
      _open.value = open ? 1 : 0;
    } else if (open) {
      _open.forward();
    } else {
      _open.reverse();
    }
  }

  /// Side width for a pane whose [available] width is shared with the chat.
  double _splitWidth(double available) {
    final desired = available * _fraction;
    return desired.clamp(kSideMinWidth, available - kSideChatMinWidth);
  }

  void _dragDivider(double dx) {
    if (_available <= 0) return;
    setState(() {
      _fraction = (_fraction - dx / _available).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final available = width - kSideDividerWidth;
        _available = available;
        final fullPane = available < kSideMinWidth + kSideChatMinWidth;
        final sideTarget = fullPane ? width : _splitWidth(available);

        return AnimatedBuilder(
          animation: _open,
          builder: (context, _) {
            final raw = _open.value;
            final shown = raw > 0;
            // Width follows the panel curve; reduced motion never moves the edge.
            final factor = _reduced
                ? (shown ? 1.0 : 0.0)
                : FrameMotion.panelCurve.transform(raw);
            // Content fades in only after the width is half way.
            final contentOpacity = _reduced
                ? raw
                : ((raw - 0.5) / 0.5).clamp(0.0, 1.0);

            final side = SizedBox(
              key: const ValueKey('side-split-panel'),
              width: sideTarget * factor,
              child: ClipRect(
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerStart,
                  minWidth: sideTarget,
                  maxWidth: sideTarget,
                  child: Opacity(
                    opacity: contentOpacity,
                    // A closed panel keeps its state but leaves Tab order and the
                    // accessibility tree (its controls sit at zero width).
                    child: ExcludeFocus(
                      excluding: !shown,
                      child: ExcludeSemantics(
                        excluding: !shown,
                        child: SidePanel(
                          key: ValueKey('side_panel_${widget.sessionId}'),
                          sessionId: widget.sessionId,
                          fullPane: fullPane,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            if (fullPane) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: Offstage(offstage: shown, child: widget.main),
                  ),
                  Align(alignment: AlignmentDirectional.centerEnd, child: side),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: widget.main),
                if (shown)
                  _SideDivider(
                    width: kSideDividerWidth * factor,
                    color: tokens.border,
                    onDrag: _dragDivider,
                  ),
                side,
              ],
            );
          },
        );
      },
    );
  }
}

/// The draggable edge between the chat and the side thread.
///
/// Uses a pointer listener rather than a gesture detector: it only follows a
/// drag with a button held, so the hover cursor stays a column resize.
class _SideDivider extends StatelessWidget {
  final double width;
  final Color color;
  final ValueChanged<double> onDrag;

  const _SideDivider({
    required this.width,
    required this.color,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerMove: (event) {
          if (event.buttons != 0) onDrag(event.delta.dx);
        },
        child: SizedBox(
          key: const ValueKey('side-split-divider'),
          width: width,
          child: Center(
            child: SizedBox(width: 1, child: ColoredBox(color: color)),
          ),
        ),
      ),
    );
  }
}
