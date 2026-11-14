import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../data/language/language_settings.dart';
import '../data/language/strings_workspace.dart';

/// A compact search input: one border (`FrameTokens.inputBorder`), 32 px high,
/// a leading search glyph and a clear button shown while there is text.
///
/// Escape behaviour: the first Escape clears the text when there is some; when
/// the field is already empty, or on the second Escape, it removes focus.
///
/// Keys: `<keyPrefix>-field` on the text field and `<keyPrefix>-clear` on the
/// clear button. The clear button's tooltip is `strings.clearSearchTooltip`.
class FrameSearchField extends StatefulWidget {
  final String keyPrefix;
  final AppStrings strings;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final ValueChanged<String>? onChanged;

  /// Called after the text was cleared, by the clear button or Escape.
  final VoidCallback? onClear;
  final bool enabled;
  final bool autofocus;

  const FrameSearchField({
    super.key,
    required this.keyPrefix,
    required this.strings,
    this.controller,
    this.focusNode,
    this.hintText,
    this.onChanged,
    this.onClear,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<FrameSearchField> createState() => _FrameSearchFieldState();
}

class _FrameSearchFieldState extends State<FrameSearchField> {
  static const double _height = 32;
  static const double _focusBorderWidth = 2;

  late final TextEditingController _ownController = TextEditingController();
  late final FocusNode _ownFocus = FocusNode();
  bool _hovered = false;

  TextEditingController get _controller =>
      widget.controller ?? _ownController;
  FocusNode get _focusNode => widget.focusNode ?? _ownFocus;

  @override
  void dispose() {
    _ownController.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    _focusNode.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_controller.text.isNotEmpty) {
      _clear();
    } else {
      _focusNode.unfocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final prefix = widget.keyPrefix;
    final enabled = widget.enabled;
    final radius = BorderRadius.circular(tokens.radiusMd);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return SizedBox(
      height: _height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          onKeyEvent: _onKeyEvent,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final showClear = enabled && value.text.isNotEmpty;
              return TextField(
                key: ValueKey('$prefix-field'),
                controller: _controller,
                focusNode: _focusNode,
                enabled: enabled,
                autofocus: widget.autofocus,
                onChanged: widget.onChanged,
                textAlignVertical: TextAlignVertical.center,
                style: text.body.copyWith(color: tokens.textPrimary),
                cursorColor: tokens.accent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _hovered && enabled
                      ? tokens.surfaceElevated
                      : tokens.surface,
                  hintText: widget.hintText,
                  hintStyle: text.body.copyWith(color: tokens.textMuted),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FrameSpace.x2,
                    vertical: 0,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: FrameSize.icon,
                    color: tokens.textMuted,
                  ),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: FrameSize.hitMin,
                    height: FrameSize.hitMin,
                  ),
                  suffixIcon: showClear
                      ? IconButton(
                          key: ValueKey('$prefix-clear'),
                          tooltip: widget.strings.clearSearchTooltip,
                          onPressed: _clear,
                          icon: Icon(
                            Icons.close,
                            size: FrameSize.icon,
                            color: tokens.textSecondary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: FrameSize.hitMin,
                            height: FrameSize.hitMin,
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: FrameSize.hitMin,
                    height: FrameSize.hitMin,
                  ),
                  border: border(tokens.inputBorder),
                  enabledBorder: border(tokens.inputBorder),
                  disabledBorder: border(tokens.border),
                  focusedBorder: border(
                    tokens.focusRing,
                    _focusBorderWidth,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
