import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:window_manager/window_manager.dart';

// Set only after successful native initialization. Web and widget tests do not
// call platform channels or pretend to own an operating-system window.
final desktopChromeProvider = Provider<bool>((ref) => false);

class DesktopDragRegion extends ConsumerWidget {
  final Widget child;
  const DesktopDragRegion({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(desktopChromeProvider) ? DragToMoveArea(child: child) : child;
}

class DesktopCaptionButtons extends StatefulWidget {
  const DesktopCaptionButtons({super.key});
  @override
  State<DesktopCaptionButtons> createState() => _DesktopCaptionButtonsState();
}

class _DesktopCaptionButtonsState extends State<DesktopCaptionButtons>
    with WindowListener {
  bool _maximized = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refresh();
  }

  Future<void> _refresh() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget button(
      String label,
      IconData icon,
      VoidCallback action, {
      bool close = false,
    }) => Tooltip(
      message: label,
      child: SizedBox(
        width: 46,
        height: 42,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: tokens.textPrimary,
            shape: const RoundedRectangleBorder(),
            overlayColor: close ? tokens.signalDanger : tokens.textPrimary,
          ),
          onPressed: action,
          child: Icon(icon, size: 17),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('Riduci a icona', Icons.remove, () => windowManager.minimize()),
        button(
          _maximized ? 'Ripristina finestra' : 'Massimizza finestra',
          _maximized ? Icons.filter_none : Icons.crop_square,
          () => _maximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        button(
          'Chiudi finestra',
          Icons.close,
          () => windowManager.close(),
          close: true,
        ),
      ],
    );
  }
}
