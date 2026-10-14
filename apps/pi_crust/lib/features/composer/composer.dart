import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import 'package:file_selector/file_selector.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/attachment_model.dart';
import '../../domain/session/session_state.dart';
import 'attachment_chips.dart';
import 'composer_attachments_provider.dart';
import 'composer_draft.dart';
import 'copilot_file_picker.dart';
import 'file_mention_menu.dart';
import 'slash_menu.dart';
import '../../ui/precision.dart';
import '../../ui/shimmer_border.dart';
import '../dialogs/extension_ui_dialog.dart';
import '../workspace/repository_workspace.dart';

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
  bool _showFileMentionMenu = false;
  String _fileMentionQuery = '';
  int _fileMentionStartIndex = -1;
  int _fileMentionSelectedIndex = 0;
  List<Map<String, dynamic>> _matchingMentionFiles = [];
  bool _queueExpanded = true;
  bool _isHovered = false;
  Timer? _hoverGraceTimer;
  bool _hasText = false;

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showEditSteerDialog(
    BuildContext context,
    int index,
    String initialText,
  ) async {
    final tokens = context.tokens;
    final textController = TextEditingController(text: initialText);
    final sessionNotifier =
        ref.read(sessionStateFamily(widget.sessionId).notifier);

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            side: BorderSide(color: tokens.borderStrong),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: tokens.accent),
              const SizedBox(width: 8),
              Text(
                'Modifica messaggio in coda (Steer #${index + 1})',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Modifica il testo del messaggio in coda prima che venga inviato all\'agente:',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('edit-steer-dialog-field'),
                  controller: textController,
                  maxLines: 4,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: tokens.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                sessionNotifier.removeSteerMessage(index);
                _controller.text = textController.text;
                _focusNode.requestFocus();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Messaggio caricato nel composer per la modifica'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                'Carica nel composer',
                style: TextStyle(color: tokens.accent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Annulla',
                style: TextStyle(color: tokens.textMuted),
              ),
            ),
            FilledButton(
              key: const ValueKey('edit-steer-dialog-save'),
              onPressed: () async {
                final newText = textController.text.trim();
                Navigator.of(dialogCtx).pop();
                if (newText.isNotEmpty) {
                  await sessionNotifier.updateSteerMessage(index, newText);
                }
              },
              child: const Text('Aggiorna'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    final initialText = ref.read(composerDraftProvider(widget.sessionId));
    _controller.text = initialText;
    _hasText = initialText.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
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
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    final show = text.startsWith('/') && !text.contains('\n');
    if (show != _showSlashMenu) {
      setState(() {
        _showSlashMenu = show;
      });
    }

    final selection = _controller.selection;
    final cursor = selection.baseOffset;
    if (cursor > 0 && cursor <= text.length) {
      final beforeCursor = text.substring(0, cursor);
      final atMatch = RegExp(r'@([a-zA-Z0-9_\-\./]*)$').firstMatch(beforeCursor);
      if (atMatch != null) {
        final query = atMatch.group(1)!;
        final start = atMatch.start;
        _updateFileMentions(query, start);
      } else if (_showFileMentionMenu) {
        setState(() => _showFileMentionMenu = false);
        _focusNode.requestFocus();
      }
    } else if (_showFileMentionMenu) {
      setState(() => _showFileMentionMenu = false);
      _focusNode.requestFocus();
    }
  }

  Future<void> _updateFileMentions(String query, int startIndex) async {
    final repoNotifier = ref.read(repositoryStateProvider(widget.sessionId).notifier);
    if (repoNotifier.currentState.files.isEmpty) {
      await repoNotifier.loadFiles();
    }
    if (!mounted) return;
    final allFiles = repoNotifier.currentState.files;
    final cleanQuery = query.toLowerCase();

    final matches = allFiles.where((f) {
      final p = (f['path']?.toString() ?? '').toLowerCase();
      if (cleanQuery.isEmpty) return true;
      return p.contains(cleanQuery);
    }).take(6).toList();

    setState(() {
      _showFileMentionMenu = matches.isNotEmpty;
      _fileMentionQuery = query;
      _fileMentionStartIndex = startIndex;
      _matchingMentionFiles = matches;
      _fileMentionSelectedIndex = 0;
    });
    _focusNode.requestFocus();
  }

  void _completeFileMention(String path) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (_fileMentionStartIndex >= 0 && cursor >= _fileMentionStartIndex) {
      final prefix = text.substring(0, _fileMentionStartIndex);
      final suffix = cursor < text.length ? text.substring(cursor) : '';
      final newText = '$prefix@$path $suffix';
      final newOffset = prefix.length + path.length + 2;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: newOffset,
        ),
      );
      ref.read(composerDraftProvider(widget.sessionId).notifier).state = newText;
    } else {
      final separator = text.isEmpty || text.endsWith(' ') ? '' : ' ';
      final newText = '$text$separator@$path ';
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      ref.read(composerDraftProvider(widget.sessionId).notifier).state = newText;
    }
    setState(() {
      _showFileMentionMenu = false;
      _matchingMentionFiles = [];
    });
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _hoverGraceTimer?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send({String? streamingBehavior}) async {
    final draft = _controller.text;
    final text = draft.trim();
    final attachments =
        ref.read(composerAttachmentsProvider(widget.sessionId));

    if ((text.isEmpty && attachments.isEmpty) ||
        ref.read(composerSendingProvider(widget.sessionId))) {
      return;
    }
    final savedDraft = ref.read(
      composerDraftProvider(widget.sessionId).notifier,
    );
    final sending = ref.read(
      composerSendingProvider(widget.sessionId).notifier,
    );
    final attachmentsNotifier = ref.read(
      composerAttachmentsProvider(widget.sessionId).notifier,
    );
    sending.state = true;
    try {
      final fullPrompt = attachments.isNotEmpty
          ? '${encodeAttachmentsTag(attachments)}${text.isNotEmpty ? '\n$text' : ''}'
          : text;

      await ref
          .read(sessionStateFamily(widget.sessionId).notifier)
          .sendPrompt(fullPrompt, streamingBehavior: streamingBehavior);

      if (attachmentsNotifier.mounted) {
        attachmentsNotifier.clear();
      }

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

  void _onAttachSelected(String value) {
    switch (value) {
      case 'repo':
        _addFileToContext();
        break;
      case 'external':
        _addExternalFiles();
        break;
      case 'link':
        _addWebLink();
        break;
      case 'image':
        _addImageFiles();
        break;
    }
  }

  Future<void> _addFileToContext() async {
    final repository = ref.read(
      repositoryStateProvider(widget.sessionId).notifier,
    );
    if (repository.currentState.files.isEmpty) await repository.loadFiles();
    if (!mounted) return;
    final state = repository.currentState;
    if (state.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.error ?? 'Nessun file disponibile nella sessione.',
          ),
        ),
      );
      return;
    }

    final result = await CopilotFilePicker.show(context, files: state.files);
    if (result == null || !mounted) return;

    final isImg = isImageExtension(result.path);
    final fileName = result.path.replaceAll('\\', '/').split('/').last;
    ref.read(composerAttachmentsProvider(widget.sessionId).notifier).add(
          ChatAttachment(
            id: 'att_repo_${DateTime.now().microsecondsSinceEpoch}',
            type: isImg ? AttachmentType.image : AttachmentType.repoFile,
            name: fileName,
            pathOrUrl: result.path,
          ),
        );
    _completeFileMention(result.path);
    _focusNode.requestFocus();
  }

  Future<void> _addExternalFiles() async {
    try {
      final files = await openFiles();
      if (files.isEmpty || !mounted) return;

      final attachments = <ChatAttachment>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final isImg = isImageExtension(f.path);
        attachments.add(
          ChatAttachment(
            id: 'att_ext_${DateTime.now().microsecondsSinceEpoch}_$i',
            type: isImg ? AttachmentType.image : AttachmentType.externalFile,
            name: f.name,
            pathOrUrl: f.path,
          ),
        );
      }

      ref
          .read(composerAttachmentsProvider(widget.sessionId).notifier)
          .addAll(attachments);
      _focusNode.requestFocus();
    } catch (e) {
      debugPrint('Selezione file annullata o non riuscita: $e');
    }
  }

  Future<void> _addWebLink() async {
    final attachment = await WebLinkInputDialog.show(context);
    if (attachment == null || !mounted) return;

    ref
        .read(composerAttachmentsProvider(widget.sessionId).notifier)
        .add(attachment);
    _focusNode.requestFocus();
  }

  Future<void> _addImageFiles() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Immagini',
            extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'],
          ),
        ],
      );
      if (files.isEmpty || !mounted) return;

      final attachments = <ChatAttachment>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        attachments.add(
          ChatAttachment(
            id: 'att_img_${DateTime.now().microsecondsSinceEpoch}_$i',
            type: AttachmentType.image,
            name: f.name,
            pathOrUrl: f.path,
          ),
        );
      }

      ref
          .read(composerAttachmentsProvider(widget.sessionId).notifier)
          .addAll(attachments);
      _focusNode.requestFocus();
    } catch (e) {
      debugPrint('Selezione immagini annullata o non riuscita: $e');
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
    final attachments =
        ref.watch(composerAttachmentsProvider(widget.sessionId));
    ref.listen<String>(composerDraftProvider(widget.sessionId), (
      previous,
      draft,
    ) {
      if (_controller.text != draft) {
        final currentSelection = _controller.selection;
        final newOffset = currentSelection.isValid && currentSelection.baseOffset <= draft.length
            ? currentSelection.baseOffset
            : draft.length;
        _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: newOffset),
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
                      if (!await resolveDirtyRepository(
                        context,
                        ref,
                        ref.read(activeSessionIdProvider),
                      )) {
                        return;
                      }
                      final result = await client.cloneSession(
                        widget.sessionId,
                      );
                      if (!mounted || !context.mounted) return;
                      final data = result['data'] as Map<String, dynamic>;
                      if (!await switchSessionSafely(
                        context,
                        ref,
                        data['sessionId'] as String,
                      )) {
                        return;
                      }
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

    final pendingInteractionRequests = sessionState.pendingUiRequests.where((r) {
      final method = r['method']?.toString();
      return r['dialog'] == true ||
          method == 'confirm' ||
          method == 'select' ||
          method == 'input' ||
          method == 'editor';
    }).toList();

    final isShimmerActive = isSending ||
        isStreaming ||
        sessionState.agentStatus == AgentStatus.working ||
        sessionState.agentStatus == AgentStatus.retrying ||
        sessionState.agentStatus == AgentStatus.compacting ||
        sessionState.activeToolCalls.isNotEmpty;

    final isAgentAnswering = sessionState.isStreaming ||
        sessionState.agentStatus == AgentStatus.working ||
        sessionState.activeToolCalls.isNotEmpty;
    final isFocused = _focusNode.hasFocus;
    final hasInputtedText = _hasText || _controller.text.trim().isNotEmpty;
    final hasAttachments = attachments.isNotEmpty;
    final shouldMinimize = isAgentAnswering &&
        !isFocused &&
        !_isHovered &&
        !hasInputtedText &&
        !hasAttachments &&
        pendingInteractionRequests.isEmpty;

    return MouseRegion(
      key: const ValueKey('composer-mouse-region'),
      onEnter: (_) {
        _hoverGraceTimer?.cancel();
        _hoverGraceTimer = null;
        if (!_isHovered) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        _hoverGraceTimer?.cancel();
        _hoverGraceTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted && _isHovered) {
            setState(() => _isHovered = false);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: ShimmerBorder(
          isActive: isShimmerActive,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Container(
                key: ValueKey('composer_box_${shouldMinimize ? 'min' : 'max'}'),
                padding: shouldMinimize
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                    : const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(
                  color: shouldMinimize
                      ? tokens.agentWorking.withValues(alpha: 0.3)
                      : tokens.surfaceElevated.withValues(alpha: 0),
                  width: 1,
                ),
              ),
              child: shouldMinimize
                  ? _buildMinimizedBar(tokens, isStreaming, sessionState)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
              // Pending model question card docked non-invasively on top of chat input
              if (pendingInteractionRequests.isNotEmpty)
                Padding(
                  key: const ValueKey('composer-extension-ui-card'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExtensionUiDialog(
                    key: ValueKey('ext_ui_${pendingInteractionRequests.last['requestId']}'),
                    sessionId: widget.sessionId,
                    request: pendingInteractionRequests.last,
                    isCard: true,
                  ),
                ),

              // File Mention overlay if active
              if (_showFileMentionMenu && _matchingMentionFiles.isNotEmpty)
                Padding(
                  key: const ValueKey('composer-file-mention-menu'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: FileMentionMenu(
                    key: const ValueKey('composer-file-mention-list'),
                    files: _matchingMentionFiles,
                    query: _fileMentionQuery,
                    selectedIndex: _fileMentionSelectedIndex,
                    onSelect: _completeFileMention,
                  ),
                ),

              // Slash Menu overlay if active
              if (_showSlashMenu && _availableCommands.isNotEmpty)
                Padding(
                  key: const ValueKey('composer-slash-menu'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SlashMenu(
                    key: const ValueKey('composer-slash-list'),
                    commands: _availableCommands,
                    filter: _controller.text,
                    onSelect: _onSelectSlashCommand,
                  ),
                ),

          // Pending Queue bar (if any queue exists)
          if (totalQueued > 0)
            Container(
              key: const ValueKey('composer-queue-bar'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: tokens.surfaceElevated,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                      if (sessionState.steeringQueue.isNotEmpty)
                        IconButton(
                          key: const ValueKey('composer-queue-toggle-expand'),
                          tooltip: _queueExpanded
                              ? 'Nascondi messaggi in coda'
                              : 'Mostra messaggi in coda',
                          icon: Icon(
                            _queueExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                            color: tokens.textSecondary,
                          ),
                          onPressed: () =>
                              setState(() => _queueExpanded = !_queueExpanded),
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
                  if (_queueExpanded && sessionState.steeringQueue.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (var i = 0; i < sessionState.steeringQueue.length; i++)
                      Container(
                        key: ValueKey('steer-queue-item-$i'),
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(tokens.radiusSm),
                              ),
                              child: Text(
                                'STEER #${i + 1}',
                                style: TextStyle(
                                  color: tokens.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                sessionState.steeringQueue[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 12,
                                  fontFamily: tokens.monoFontFamily,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('edit-steer-btn-$i'),
                              tooltip: 'Modifica messaggio steer in coda',
                              icon: Icon(Icons.edit_outlined, size: 14, color: tokens.accent),
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              padding: EdgeInsets.zero,
                              onPressed: () => _showEditSteerDialog(
                                context,
                                i,
                                sessionState.steeringQueue[i],
                              ),
                            ),
                            IconButton(
                              key: ValueKey('delete-steer-btn-$i'),
                              tooltip: 'Elimina dalla coda',
                              icon: Icon(Icons.close, size: 14, color: tokens.textMuted),
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              padding: EdgeInsets.zero,
                              onPressed: () => sessionNotifier.removeSteerMessage(i),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

          // Worker Crash Recovery Banner
          if (isError)
            Container(
              key: const ValueKey('composer-crash-banner'),
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
            key: const ValueKey('composer-input-area'),
            padding: const EdgeInsets.all(4),
            child: Focus(
              key: const ValueKey('composer-input-focus'),
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  // File Mention keyboard navigation
                  if (_showFileMentionMenu && _matchingMentionFiles.isNotEmpty) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      setState(() {
                        _fileMentionSelectedIndex =
                            (_fileMentionSelectedIndex + 1) %
                            _matchingMentionFiles.length;
                      });
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      setState(() {
                        _fileMentionSelectedIndex =
                            (_fileMentionSelectedIndex - 1 + _matchingMentionFiles.length) %
                            _matchingMentionFiles.length;
                      });
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.tab ||
                        event.logicalKey == LogicalKeyboardKey.enter) {
                      final chosen =
                          _matchingMentionFiles[_fileMentionSelectedIndex]['path']
                              ?.toString() ??
                          '';
                      if (chosen.isNotEmpty) {
                        _completeFileMention(chosen);
                        return KeyEventResult.handled;
                      }
                    }
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      setState(() => _showFileMentionMenu = false);
                      return KeyEventResult.handled;
                    }
                  }

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
                  if (attachments.isNotEmpty)
                    AttachmentListBar(
                      key: const ValueKey('composer-attachments-bar'),
                      attachments: attachments,
                      isEditable: true,
                      onRemove: (a) => ref
                          .read(
                            composerAttachmentsProvider(widget.sessionId).notifier,
                          )
                          .remove(a.id),
                    ),
                  TextField(
                    key: const ValueKey('composer-text-field'),
                    cursorColor: tokens.accent,
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 2,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: isStreaming
                          ? 'Aggiungi istruzioni o prepara il prossimo turno...'
                          : 'Cosa vuoi realizzare? Digita / per i comandi.',
                      hintStyle: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 14,
                      ),
                      fillColor: tokens.background,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(
                          color: tokens.focusRing,
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
                      PopupMenuButton<String>(
                        key: const ValueKey('composer-attach-popup-btn'),
                        tooltip: 'Allega file, link o immagine',
                        icon: const Icon(Icons.attach_file, size: 18),
                        color: tokens.surfaceElevated,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          side: BorderSide(color: tokens.borderStrong),
                        ),
                        offset: const Offset(0, -170),
                        onSelected: _onAttachSelected,
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            key: const ValueKey('attach-option-repo'),
                            value: 'repo',
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_open_outlined,
                                  size: 16,
                                  color: tokens.accent,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'File dal repository',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            key: const ValueKey('attach-option-external'),
                            value: 'external',
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.upload_file_outlined,
                                  size: 16,
                                  color: tokens.syntaxFunction,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'File esterno',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            key: const ValueKey('attach-option-link'),
                            value: 'link',
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link,
                                  size: 16,
                                  color: tokens.syntaxKeyword,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Link web',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            key: const ValueKey('attach-option-image'),
                            value: 'image',
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                  color: tokens.syntaxNumber,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Immagine',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
    ),
  ),
),
),
),
);
  }

  Widget _buildMinimizedBar(
    CrustTokens tokens,
    bool isStreaming,
    SessionState sessionState,
  ) {
    return InkWell(
      key: const ValueKey('composer-minimized-bar'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      onTap: () {
        setState(() => _isHovered = true);
        _focusNode.requestFocus();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.agentWorking,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'L\'agente sta rispondendo... Passa il mouse o clicca per scrivere',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontFamily: tokens.uiFontFamily,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('composer-minimized-interrupt'),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: _interrupt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_circle_outlined,
                        size: 13,
                        color: tokens.agentWorking,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Interrompi',
                        style: TextStyle(
                          color: tokens.agentWorking,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(
              Icons.unfold_more,
              size: 16,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
