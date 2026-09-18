import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';

class Composer extends ConsumerStatefulWidget {
  final String sessionId;

  const Composer({super.key, required this.sessionId});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final sessionState = ref.read(sessionStateFamily(widget.sessionId));

    if (sessionState.isStreaming) {
      // Send as followUp during active streaming
      sessionNotifier.sendPrompt(text, streamingBehavior: 'followUp');
    } else {
      sessionNotifier.sendPrompt(text);
    }

    _controller.clear();
  }

  void _interrupt() {
    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    sessionNotifier.interrupt();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _interrupt();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
              _send();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (sessionState.isStreaming)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: IconButton(
                  icon: Icon(Icons.stop_circle_outlined, color: tokens.danger),
                  tooltip: 'Interrompi (Esc)',
                  onPressed: _interrupt,
                ),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.border, width: 1),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 5,
                  minLines: 1,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: sessionState.isStreaming
                        ? 'Scrivi messaggio in coda (follow-up) o premi Esc per interrompere...'
                        : 'Scrivi un messaggio a Pi (Ctrl+Invio per inviare)...',
                    hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              child: IconButton.filled(
                icon: const Icon(Icons.arrow_upward, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.accentContrast,
                ),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
