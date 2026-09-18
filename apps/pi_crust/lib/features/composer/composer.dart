import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';
import 'slash_menu.dart';

class Composer extends ConsumerStatefulWidget {
  final String sessionId;

  const Composer({super.key, required this.sessionId});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _availableCommands = [];
  bool _showSlashMenu = false;
  bool _isInterrupting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadCommands();
  }

  Future<void> _loadCommands() async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final cmds = await notifier.getCommands();
    if (mounted) {
      setState(() {
        _availableCommands = cmds;
      });
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final show = text.startsWith('/') && !text.contains('\n');
    if (show != _showSlashMenu) {
      setState(() {
        _showSlashMenu = show;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send({String? streamingBehavior}) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    sessionNotifier.sendPrompt(text, streamingBehavior: streamingBehavior);

    _controller.clear();
    setState(() {
      _showSlashMenu = false;
    });
  }

  Future<void> _interrupt() async {
    if (_isInterrupting) return;
    setState(() {
      _isInterrupting = true;
    });

    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final res = await sessionNotifier.interrupt();

    setState(() {
      _isInterrupting = false;
    });

    // Esc semantics: Restore any unexecuted queued text back into the composer
    if (res != null && res['queue'] is Map) {
      final q = res['queue'] as Map<String, dynamic>;
      final steering = (q['steering'] as List<dynamic>?)?.cast<String>() ?? [];
      final followUp = (q['followUp'] as List<dynamic>?)?.cast<String>() ?? [];
      final restored = [...steering, ...followUp].where((s) => s.trim().isNotEmpty).join('\n');

      if (restored.isNotEmpty) {
        if (_controller.text.trim().isEmpty) {
          _controller.text = restored;
        } else {
          _controller.text = '${_controller.text}\n$restored';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Interrotto. I messaggi non eseguiti in coda sono stati ripristinati nel composer.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _onSelectSlashCommand(Map<String, dynamic> cmd) {
    final name = cmd['name'] as String? ?? '';
    _controller.text = '/$name ';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {
      _showSlashMenu = false;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final isStreaming = sessionState.isStreaming;
    final isError = sessionState.agentStatus == AgentStatus.workerError;
    final totalQueued = sessionState.steeringQueue.length + sessionState.followUpQueue.length;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slash Menu overlay if active
          if (_showSlashMenu && _availableCommands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SlashMenu(
                commands: _availableCommands,
                filter: _controller.text,
                onSelect: _onSelectSlashCommand,
              ),
            ),

          // Pending Queue bar (if any queue exists)
          if (totalQueued > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: tokens.surfaceElevated,
              child: Row(
                children: [
                  Icon(Icons.queue, size: 16, color: tokens.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'In coda ($totalQueued): ${sessionState.steeringQueue.length} steer, ${sessionState.followUpQueue.length} follow-up',
                      style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(Icons.clear_all, size: 14, color: tokens.textMuted),
                    label: Text(
                      'Svuota coda',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    onPressed: () => sessionNotifier.clearQueue(),
                  ),
                ],
              ),
            ),

          // Worker Crash Recovery Banner
          if (isError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: tokens.danger.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: tokens.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Il worker Pi è terminato inaspettatamente. Nessun comando è stato re-inviato automaticamente.',
                      style: TextStyle(color: tokens.danger, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.accentContrast,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Riprendi sessione', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => sessionNotifier.recoverSession(),
                  ),
                ],
              ),
            ),

          // Input area
          Padding(
            padding: const EdgeInsets.all(16),
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    if (isStreaming) {
                      _interrupt();
                      return KeyEventResult.handled;
                    }
                  }
                  if (event.logicalKey == LogicalKeyboardKey.enter &&
                      (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
                    if (isStreaming) {
                      _send(streamingBehavior: 'steer');
                    } else {
                      _send();
                    }
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Stop button during streaming
                  if (isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: IconButton(
                        icon: _isInterrupting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: tokens.danger),
                              )
                            : Icon(Icons.stop_circle_outlined, color: tokens.danger),
                        tooltip: 'Interrompi (Esc) — recupera il testo non eseguito',
                        onPressed: _isInterrupting ? null : _interrupt,
                      ),
                    ),

                  // Text input field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: tokens.background,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.border, width: 1),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 5,
                        minLines: 1,
                        style: TextStyle(color: tokens.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: isStreaming
                              ? 'Digita per Steer (interrompe dopo i tool) o Follow-up...'
                              : 'Scrivi un messaggio o digita / per i comandi (Ctrl+Invio per inviare)...',
                          hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Dynamic action buttons
                  if (!isStreaming)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      child: Tooltip(
                        message: 'Invia prompt (Ctrl+Invio)',
                        child: IconButton.filled(
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: tokens.accent,
                            foregroundColor: tokens.accentContrast,
                          ),
                          onPressed: () => _send(),
                        ),
                      ),
                    )
                  else ...[
                    // Steer Button
                    Tooltip(
                      message: 'Steer: interrompe subito dopo i tool correnti e applica le istruzioni',
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.accentContrast,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm)),
                        ),
                        icon: const Icon(Icons.bolt, size: 16),
                        label: const Text('Steer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () => _send(streamingBehavior: 'steer'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Follow-up Button
                    Tooltip(
                      message: 'Follow-up: mette in coda per il prossimo turno completo',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.textPrimary,
                          side: BorderSide(color: tokens.border),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm)),
                        ),
                        icon: const Icon(Icons.more_time, size: 16),
                        label: const Text('Follow-up', style: TextStyle(fontSize: 12)),
                        onPressed: () => _send(streamingBehavior: 'followUp'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
