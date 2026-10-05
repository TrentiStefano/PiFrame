import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';
import 'slash_menu.dart';
import '../../ui/precision.dart';

final composerDraftProvider = StateProvider.family<String, String>(
  (ref, sessionId) => '',
);
final composerSendingProvider = StateProvider.family<bool, String>(
  (ref, sessionId) => false,
);

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
    _controller.text = ref.read(composerDraftProvider(widget.sessionId));
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
    ref.read(composerDraftProvider(widget.sessionId).notifier).state = text;
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

  Future<void> _send({String? streamingBehavior}) async {
    final draft = _controller.text;
    final text = draft.trim();
    if (text.isEmpty || ref.read(composerSendingProvider(widget.sessionId))) {
      return;
    }
    final savedDraft = ref.read(
      composerDraftProvider(widget.sessionId).notifier,
    );
    final sending = ref.read(
      composerSendingProvider(widget.sessionId).notifier,
    );
    sending.state = true;
    try {
      await ref
          .read(sessionStateFamily(widget.sessionId).notifier)
          .sendPrompt(text, streamingBehavior: streamingBehavior);
      if (savedDraft.mounted && savedDraft.state == draft) {
        savedDraft.state = '';
      }
      if (mounted && _controller.text == draft) _controller.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invio non riuscito: $error')));
      }
    } finally {
      if (sending.mounted) sending.state = false;
    }
  }

  Future<void> _continueAmbiguousSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verifica la sessione Pi'),
        content: const Text(
          'Pi-Crust rileva Pi interattivo aperto in questa cartella, ma Pi non comunica quale file di sessione usa. '
          'Continua solo se questa sessione non è aperta nel terminale. Due processi sullo stesso file possono danneggiare la cronologia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continua qui'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final client = ref.read(pcpClientProvider);
      if (client == null) throw StateError('Daemon non connesso');
      await client.continueSession(widget.sessionId, confirmed: true);
      if (!mounted) return;
      ref.invalidate(sessionListProvider);
      ref.invalidate(sessionStateFamily(widget.sessionId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ripresa non riuscita: $error')));
      }
    }
  }

  Future<void> _runAction(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Azione non riuscita: $error')));
      }
    }
  }

  Future<void> _interrupt() async {
    if (_isInterrupting) return;
    setState(() {
      _isInterrupting = true;
    });

    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );
    Map<String, dynamic>? res;
    try {
      res = await sessionNotifier.interrupt();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Interruzione non riuscita: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isInterrupting = false);
    }
    if (!mounted) return;

    final data = res?['data'] as Map<String, dynamic>? ?? res;
    // Esc semantics: Restore any unexecuted queued text back into the composer
    if (data != null && data['queue'] is Map) {
      final q = data['queue'] as Map<String, dynamic>;
      final steering = (q['steering'] as List<dynamic>?)?.cast<String>() ?? [];
      final followUp = (q['followUp'] as List<dynamic>?)?.cast<String>() ?? [];
      final restored = [
        ...steering,
        ...followUp,
      ].where((s) => s.trim().isNotEmpty).join('\n');

      if (restored.isNotEmpty) {
        if (_controller.text.trim().isEmpty) {
          _controller.text = restored;
        } else {
          _controller.text = '${_controller.text}\n$restored';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Interrotto. I messaggi non eseguiti in coda sono stati ripristinati nel composer.',
              ),
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
    final isSending = ref.watch(composerSendingProvider(widget.sessionId));
    ref.listen<String>(composerDraftProvider(widget.sessionId), (
      previous,
      draft,
    ) {
      if (_controller.text != draft) {
        _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
      }
    });
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );
    if (sessionState.readOnly) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sessionState.readOnlyReason == 'terminal'
                  ? 'Pi ha una sessione interattiva aperta in questa cartella. Duplica per evitare scritture concorrenti.'
                  : 'Pi-Crust non può verificare che questa sessione sia chiusa. Duplica per continuare in sicurezza.',
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (sessionState.readOnlyReason == 'unknown') ...[
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Continua qui'),
                    onPressed: _continueAmbiguousSession,
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Duplica e continua'),
                  onPressed: () async {
                    try {
                      final client = ref.read(pcpClientProvider);
                      if (client == null) {
                        throw StateError('Daemon non connesso');
                      }
                      final result = await client.cloneSession(
                        widget.sessionId,
                      );
                      if (!mounted) return;
                      final data = result['data'] as Map<String, dynamic>;
                      ref.read(activeSessionIdProvider.notifier).state =
                          data['sessionId'] as String;
                      ref.invalidate(sessionListProvider);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Duplicazione non riuscita: $error'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }
    final isStreaming = sessionState.isStreaming;
    final isError = sessionState.agentStatus == AgentStatus.workerError;
    final totalQueued =
        sessionState.steeringQueue.length + sessionState.followUpQueue.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: tokens.displaySurface,
        border: Border(top: BorderSide(color: tokens.borderStrong, width: 1)),
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
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      Icons.clear_all,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    label: Text(
                      'Svuota coda',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    onPressed: () => _runAction(sessionNotifier.clearQueue),
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
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: tokens.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Il worker Pi è terminato inaspettatamente. Nessun comando è stato re-inviato automaticamente.',
                      style: TextStyle(
                        color: tokens.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.accentContrast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text(
                      'Riprendi sessione',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _runAction(sessionNotifier.recoverSession),
                  ),
                ],
              ),
            ),

          // Input area
          Padding(
            padding: const EdgeInsets.all(4),
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
                      (HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isControlPressed)) {
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    cursorColor: tokens.displayText,
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 2,
                    style: TextStyle(
                      color: tokens.displayText,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: isStreaming
                          ? 'Aggiungi istruzioni o prepara il prossimo turno...'
                          : 'Cosa vuoi realizzare? Digita / per i comandi.',
                      hintStyle: TextStyle(
                        color: tokens.displayText.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                      fillColor: tokens.displaySurface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(
                          color: tokens.displayText.withValues(alpha: 0.45),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(
                          color: tokens.displayText,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (MediaQuery.sizeOf(context).width > 600)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            isStreaming
                                ? 'Esc interrompe · Ctrl / Cmd + Invio: Steer'
                                : 'Ctrl / Cmd + Invio per inviare',
                            style: TextStyle(
                              color: tokens.displayText.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      // Stop button during streaming
                      if (isStreaming)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 4),
                          child: IconButton(
                            icon: _isInterrupting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.danger,
                                    ),
                                  )
                                : Icon(
                                    Icons.stop_circle_outlined,
                                    color: tokens.signalDanger,
                                  ),
                            tooltip: 'Interrompi (Esc) — recupera il testo non eseguito',
                            onPressed: _isInterrupting ? null : _interrupt,
                          ),
                        ),

                      // Dynamic action buttons
                      if (!isStreaming)
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          child: Tooltip(
                            message: 'Invia prompt (Ctrl+Invio)',
                            child: PressFeedback(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                label: Text(isSending ? 'Invio...' : 'Invia'),
                                onPressed: isSending ? null : () => _send(),
                              ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.bolt, size: 16),
                            label: const Text(
                              'Steer',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: isSending
                                ? null
                                : () => _send(streamingBehavior: 'steer'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Follow-up Button
                        Tooltip(
                          message: 'Follow-up: mette in coda per il prossimo turno completo',
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tokens.displayText,
                              side: BorderSide(
                                color: tokens.displayText.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.more_time, size: 16),
                            label: const Text(
                              'Follow-up',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: isSending
                                ? null
                                : () => _send(streamingBehavior: 'followUp'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
