import '../../domain/errors/user_facing_error.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'package:file_selector/file_selector.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/composer/composer_settings.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/attachment_model.dart';
import '../../domain/session/context_pricing_helper.dart';
import 'attachment_chips.dart';
import 'attachment_ingest.dart';
import '../../ui/escape_layers.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/phone_corners.dart';
import 'composer_attachments_provider.dart';
import 'composer_draft.dart';
import 'copilot_file_picker.dart';
import 'file_mention_menu.dart';
import 'slash_menu.dart';
import 'command_chip.dart';
import 'composer_focus_provider.dart';
import 'composer_review_button.dart';
import 'composer_status_line.dart';
import 'thinking_level_bars.dart';
import '../../ui/precision.dart';
import '../../ui/shimmer_border.dart';
import '../dialogs/extension_ui_dialog.dart';
import '../session_tree/session_tree_dialog.dart';
import '../sessions_sidebar/session_actions.dart' show createSession;
import '../workspace/repository_workspace.dart';
import '../workspace/pane_drag_state.dart';
import '../session_changes/session_changes_provider.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_icon_action.dart';
import '../../ui/motion.dart';
import '../context_panel/context_window_selector.dart';
import '../side/side_provider.dart';

final composerSendingProvider = StateProvider.family<bool, String>(
  (ref, sessionId) => false,
);

class _ComposerSizeAnimator extends ConsumerWidget {
  final Widget child;

  const _ComposerSizeAnimator({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a pane divider is dragged the composer follows it directly; AnimatedSize would
    // tween its size and trail the divider. Minimize/expand uses a 240 ms ease-out tween.
    if (ref.watch(paneDraggingProvider)) return child;
    return AnimatedSize(
      duration: FrameMotion.panel,
      curve: FrameMotion.enterCurve,
      alignment: Alignment.bottomCenter,
      child: child,
    );
  }
}

/// Chip row budget (audit R2 and the chip-overlap regression, plan 4.4), in logical px. The chip
/// row gets the width left after the send, attach, enlarge and review controls. Inside it the
/// model name takes whatever the other chips leave (clamped to the min and max below), and the
/// thinking label is dropped before the name is. Widths are estimates of the chips' fixed parts.
const double kComposerChipGap = 4;
const double kComposerModelChipMinWidth = 48;
const double kComposerModelChipMaxWidth = 200;
const double kComposerThinkingChipWidth = 40;
const double kComposerThinkingLabelWidth = 56;
const double kComposerThinkingLabelMinBox = 300;
const double kComposerContextChipWidth = 76;
const double kComposerContextIconChipWidth = 44;
const double kComposerChipArrowWidth = 15;

/// Below this chip-row width the picker chips drop their arrows and the context chip its label.
const double kComposerCompactChipBox = 200;

/// The review control shows its "Rivedi modifiche (n)" label from this width of the whole row.
const double kComposerReviewLabelMinRowWidth = 520;

class Composer extends ConsumerStatefulWidget {
  final String sessionId;

  /// Height the parent actually offers to the chat column (transcript + composer). When the
  /// on-screen keyboard is open this is what is left above it: the Scaffold already removed the
  /// keyboard inset from [MediaQuery], so it cannot be derived from the media query any more.
  final double? availableHeight;

  const Composer({super.key, required this.sessionId, this.availableHeight});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _availableCommands = [];
  bool _showSlashMenu = false;
  int _slashSelectedIndex = 0;
  /// Pi command staged as a chip. While set, the text field holds only its arguments.
  Map<String, dynamic>? _activeCommand;
  bool _commandRunning = false;
  bool _isInterrupting = false;
  int _pendingUploads = 0;
  bool _showFileMentionMenu = false;
  String _fileMentionQuery = '';
  int _fileMentionStartIndex = -1;
  int _fileMentionSelectedIndex = 0;
  List<Map<String, dynamic>> _matchingMentionFiles = [];
  bool _queueExpanded = true;
  bool _hasText = false;
  bool _isInputEnlarged = false;
  List<Map<String, dynamic>> _models = [];
  bool _isContextPickerLoading = false;
  // Model/thinking menus load their options asynchronously before opening: ignore re-taps meanwhile.
  bool _isPickerBusy = false;
  // Cards the user closed locally (timeout, stale or answered); the daemon event may arrive later or never.
  final Set<String> _dismissedUiRequestIds = {};
  int _modelLoadGeneration = 0;

  Future<void> _guardPicker(Future<void> Function() open) async {
    if (_isPickerBusy) return;
    _isPickerBusy = true;
    try {
      await open();
    } finally {
      _isPickerBusy = false;
    }
  }

  Future<void> _loadModels() async {
    final generation = ++_modelLoadGeneration;
    final sessionId = widget.sessionId;
    final notifier = ref.read(sessionStateFamily(sessionId).notifier);
    final models = await notifier.getAvailableModels();
    if (mounted &&
        widget.sessionId == sessionId &&
        generation == _modelLoadGeneration) {
      setState(() {
        _models = models
            .map((model) => Map<String, dynamic>.from(model))
            .toList();
      });
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showEditSteerDialog(
    BuildContext context,
    int index,
    String initialText,
  ) async {
    final strings = ref.read(appStringsProvider);
    final tokens = context.tokens;
    final textController = TextEditingController(text: initialText);
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );

    await showFrameDialog<void>(
      context: context,
      dialog: FrameDialog<void>(
        title: strings.steerEditDialogTitle(index),
        maxWidth: 480,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.steerEditDialogDesc,
              style: FrameText.of(context).label.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: FrameSpace.x3),
            TextField(
              key: const ValueKey('edit-steer-dialog-field'),
              controller: textController,
              maxLines: 4,
              style: FrameText.of(context).body.copyWith(
                color: tokens.textPrimary,
              ),
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
        actions: [
          FrameDialogAction<void>(
            label: strings.steerLoadToComposerAction,
            role: FrameDialogActionRole.cancel,
            key: const ValueKey('edit-steer-dialog-load'),
            onPressed: () {
              sessionNotifier.removeSteerMessage(index);
              _controller.text = textController.text;
              _focusNode.requestFocus();
              FrameSnackBar.show(
                context,
                message: strings.steerLoadedToComposer,
                duration: const Duration(seconds: 2),
              );
            },
          ),
          FrameDialogAction<void>(
            label: strings.cancel,
            role: FrameDialogActionRole.cancel,
          ),
          FrameDialogAction<void>(
            label: strings.steerUpdateAction,
            role: FrameDialogActionRole.primary,
            key: const ValueKey('edit-steer-dialog-save'),
            onPressed: () {
              final newText = textController.text.trim();
              if (newText.isNotEmpty) {
                sessionNotifier.updateSteerMessage(index, newText);
              }
            },
          ),
        ],
      ),
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
    _availableCommands = _mergeLocalCommands(const []);
    _loadCommands();
    _loadModels();
  }

  List<Map<String, dynamic>> _mergeLocalCommands(
    List<Map<String, dynamic>> cmds,
  ) {
    final strings = ref.read(appStringsProvider);
    final localCommands = [
      {
        'name': 'side',
        'description': strings.sideSlashDescription,
        'argumentHint': '[question]',
        'source': 'builtin',
      },
      {
        'name': 'btw',
        'description': strings.sideSlashDescription,
        'argumentHint': '[question]',
        'source': 'builtin',
      },
    ];
    final result = List<Map<String, dynamic>>.from(cmds);
    for (final local in localCommands) {
      final existingIndex = result.indexWhere(
        (c) => c['name'] == local['name'],
      );
      if (existingIndex >= 0) {
        result[existingIndex] = local;
      } else {
        result.add(local);
      }
    }
    return result;
  }

  Future<void> _loadCommands() async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final cmds = await notifier.getCommands();
    // A failed refresh returns []: keep the list we have instead of forgetting Pi's commands.
    if (mounted && (cmds.isNotEmpty || _availableCommands.length <= 2)) {
      setState(() {
        _availableCommands = _mergeLocalCommands(cmds);
      });
    }
  }

  bool _isInteractionRequest(Map<String, dynamic> request) {
    final method = request['method']?.toString();
    return request['dialog'] == true ||
        method == 'confirm' ||
        method == 'select' ||
        method == 'input' ||
        method == 'editor';
  }

  bool _hasPendingInteractionRequest() {
    return ref
        .read(sessionStateFamily(widget.sessionId))
        .pendingUiRequests
        .any(
          (request) =>
              _isInteractionRequest(request) &&
              !_dismissedUiRequestIds.contains(
                request['requestId']?.toString(),
              ),
        );
  }

  /// Text as of the last [_onTextChanged] pass. The controller also notifies for pure caret /
  /// selection moves (long-press selection, spacebar trackpad on iOS); those must not redo the
  /// slash/@-mention work, which calls setState and re-requests focus on every move.
  String _lastObservedText = '';

  void _onTextChanged() {
    final text = _controller.text;
    if (text == _lastObservedText) {
      // Caret-only move: just close the @-mention menu once the caret left the mention.
      if (_showFileMentionMenu) {
        final cursor = _controller.selection.baseOffset;
        final stillInMention =
            cursor > 0 &&
            cursor <= text.length &&
            RegExp(r'@([a-zA-Z0-9_\-\./]*)$').hasMatch(text.substring(0, cursor));
        if (!stillInMention) setState(() => _showFileMentionMenu = false);
      }
      return;
    }
    _lastObservedText = text;
    ref.read(composerDraftProvider(widget.sessionId).notifier).state = text;
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    if (_activeCommand == null) {
      final typed = _matchTypedCommand(text, requireArgsSeparator: true);
      if (typed != null) {
        _activateCommand(typed.$1, args: typed.$2);
        return;
      }
    }
    final show =
        _activeCommand == null && text.startsWith('/') && !text.contains('\n');
    if (show && !_showSlashMenu) unawaited(_loadCommands());
    if (show != _showSlashMenu || _slashSelectedIndex != 0) {
      setState(() {
        _showSlashMenu = show;
        _slashSelectedIndex = 0;
      });
    }

    final selection = _controller.selection;
    final cursor = selection.baseOffset;
    if (cursor > 0 && cursor <= text.length) {
      final beforeCursor = text.substring(0, cursor);
      final atMatch = RegExp(r'@([a-zA-Z0-9_\-\./]*)$')
          .firstMatch(beforeCursor);
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
    final repoNotifier = ref.read(
      repositoryStateProvider(widget.sessionId).notifier,
    );
    if (repoNotifier.currentState.files.isEmpty) {
      await repoNotifier.loadFiles();
    }
    if (!mounted) return;
    final allFiles = repoNotifier.currentState.files;
    final cleanQuery = query.toLowerCase();

    final matches = allFiles
        .where((f) {
          final p = (f['path']?.toString() ?? '').toLowerCase();
          if (cleanQuery.isEmpty) return true;
          return p.contains(cleanQuery);
        })
        .take(6)
        .toList();

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
        selection: TextSelection.collapsed(offset: newOffset),
      );
      ref.read(composerDraftProvider(widget.sessionId).notifier).state =
          newText;
    } else {
      final separator = text.isEmpty || text.endsWith(' ') ? '' : ' ';
      final newText = '$text$separator@$path ';
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      ref.read(composerDraftProvider(widget.sessionId).notifier).state =
          newText;
    }
    setState(() {
      _showFileMentionMenu = false;
      _matchingMentionFiles = [];
    });
    _focusNode.requestFocus();
  }

  void _insertNewlineAtSelection() {
    final text = _controller.text;
    final selection = _controller.selection;
    final int start;
    final int end;
    if (selection.isValid && selection.start >= 0) {
      start = selection.start < selection.end ? selection.start : selection.end;
      end = selection.start < selection.end ? selection.end : selection.start;
    } else {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, '\n');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Outer corners of the composer card. On rounded-corner iPhones the bottom corners are
  /// concentric with the panel (and so with the display): display radius - panel inset (8) -
  /// composer margin (14).
  BorderRadius _composerRadius(FrameTokens tokens) {
    final base = Radius.circular(tokens.radiusLg);
    final displayRadius = phoneDisplayCornerRadius(context);
    if (displayRadius == null) return BorderRadius.all(base);
    final bottom = Radius.circular(
      concentricRadius(displayRadius, 8 + 14, min: tokens.radiusLg),
    );
    return BorderRadius.only(
      topLeft: base,
      topRight: base,
      bottomLeft: bottom,
      bottomRight: bottom,
    );
  }

  Future<void> _send({String? streamingBehavior}) async {
    if (_hasPendingInteractionRequest()) return;

    final draft = _controller.text;
    final text = draft.trim();
    final attachments = ref.read(composerAttachmentsProvider(widget.sessionId));

    if (_pendingUploads > 0) {
      // An upload is still running: sending now would drop the attachment silently.
      FrameSnackBar.show(
        context,
        message: ref.read(appStringsProvider).composerUploadInProgress,
      );
      return;
    }

    if (ref.read(composerSendingProvider(widget.sessionId))) return;
    final command = _activeCommand;
    if (command != null) {
      return _runActiveCommand(command, text, attachments, streamingBehavior);
    }
    if (text.isEmpty && attachments.isEmpty) return;
    // A typed `/name` never leaves as text: it becomes a chip, and the next Enter runs it.
    final typed = _matchTypedCommand(text);
    if (typed != null) {
      _activateCommand(typed.$1, args: typed.$2);
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

      final isPrompt = streamingBehavior == null;
      if (isPrompt) {
        if (mounted && _controller.text == draft) _controller.clear();
        if (savedDraft.mounted && savedDraft.state == draft) {
          savedDraft.state = '';
        }
        if (attachmentsNotifier.mounted) attachmentsNotifier.clear();
      }

      await ref
          .read(sessionStateFamily(widget.sessionId).notifier)
          .sendPrompt(fullPrompt, streamingBehavior: streamingBehavior);

      if (!isPrompt) {
        if (attachmentsNotifier.mounted) attachmentsNotifier.clear();
        if (savedDraft.mounted && savedDraft.state == draft) {
          savedDraft.state = '';
        }
        if (mounted && _controller.text == draft) _controller.clear();
      }
    } catch (error) {
      if (mounted && streamingBehavior != null) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.composerSendFailed(error), isError: true);
      }
    } finally {
      if (sending.mounted) sending.state = false;
    }
  }

  Future<void> _continueAmbiguousSession() async {
    final strings = ref.read(appStringsProvider);
    final confirmed = await showFrameDialog<bool>(
      context: context,
      dialog: FrameDialog<bool>(
        title: strings.composerVerifySessionTitle,
        body: Text(strings.composerVerifySessionContent),
        actions: [
          FrameDialogAction<bool>(
            label: strings.cancel,
            role: FrameDialogActionRole.cancel,
            value: false,
          ),
          FrameDialogAction<bool>(
            label: strings.composerContinueHereAction,
            role: FrameDialogActionRole.primary,
            value: true,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final client = ref.read(pcpClientProvider);
      if (client == null) throw StateError(strings.composerDaemonNotConnected);
      await client.continueSession(widget.sessionId, confirmed: true);
      if (!mounted) return;
      ref.invalidate(sessionListProvider);
      ref.invalidate(sessionStateFamily(widget.sessionId));
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(context, message: strings.composerResumeFailed(error), isError: true);
      }
    }
  }

  Future<void> _runAction(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.composerActionFailed(error), isError: true);
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
    final strings = ref.read(appStringsProvider);
    if (state.files.isEmpty) {
      FrameSnackBar.show(
        context,
        message: state.error == null
            ? strings.composerNoFilesAvailable
            : describeError(state.error!, strings).summary,
        isError: state.error != null,
      );
      return;
    }

    final result = await CopilotFilePicker.show(context, files: state.files, strings: strings);
    if (result == null || !mounted) return;

    final isImg = isImageExtension(result.path);
    final fileName = result.path.replaceAll('\\', '/').split('/').last;
    ref
        .read(composerAttachmentsProvider(widget.sessionId).notifier)
        .add(
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

      await _ingestFiles(files, idPrefix: 'att_ext');
    } catch (e) {
      debugPrint('Selezione file annullata o non riuscita: $e');
    }
  }

  /// Adds picked files to the composer. In the browser the bytes are uploaded to the daemon first
  /// (a `blob:` URL means nothing to the agent); send is blocked until every upload has finished.
  Future<void> _ingestFiles(
    List<XFile> files, {
    required String idPrefix,
    bool forceImage = false,
  }) async {
    if (files.isEmpty || !mounted) return;
    final strings = ref.read(appStringsProvider);
    final notifier = ref.read(
      composerAttachmentsProvider(widget.sessionId).notifier,
    );
    if (kIsWeb) setState(() => _pendingUploads += files.length);
    for (var i = 0; i < files.length; i++) {
      try {
        final attachment = await ingestPickedFile(
          files[i],
          idPrefix: idPrefix,
          index: i,
          forceImage: forceImage,
        );
        if (!mounted) return;
        notifier.add(attachment);
      } catch (error) {
        if (mounted) {
          FrameSnackBar.show(
            context,
            message: strings.composerUploadFailed(files[i].name, error),
            isError: true,
          );
        }
      } finally {
        if (kIsWeb && mounted) {
          setState(() => _pendingUploads = math.max(0, _pendingUploads - 1));
        }
      }
    }
    if (mounted) _focusNode.requestFocus();
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
      final strings = ref.read(appStringsProvider);
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(
            label: strings.composerImagesFilterLabel,
            extensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'],
          ),
        ],
      );
      if (files.isEmpty || !mounted) return;

      await _ingestFiles(files, idPrefix: 'att_img', forceImage: true);
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
    try {
      await sessionNotifier.interrupt();
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(
          context,
          message: strings.composerInterruptFailed(error),
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isInterrupting = false);
    }
    if (!mounted) return;

    final strings = ref.read(appStringsProvider);
    FrameSnackBar.show(
      context,
      message: strings.composerAgentInterrupted,
      duration: const Duration(seconds: 3),
    );
  }

  void _onSelectSlashCommand(Map<String, dynamic> cmd) => _activateCommand(cmd);

  /// Stages [cmd] as a chip; the field keeps only [args].
  void _activateCommand(Map<String, dynamic> cmd, {String args = ''}) {
    setState(() {
      _activeCommand = cmd;
      _showSlashMenu = false;
      _slashSelectedIndex = 0;
    });
    _controller.value = TextEditingValue(
      text: args,
      selection: TextSelection.collapsed(offset: args.length),
    );
    _focusNode.requestFocus();
  }

  /// Drops the chip. With no arguments typed, `/name` returns as text so the name can be edited.
  void _removeCommand() {
    final command = _activeCommand;
    if (command == null || _commandRunning) return;
    final keepArgs = _controller.text.isNotEmpty;
    setState(() => _activeCommand = null);
    if (!keepArgs) {
      final text = '/${command['name']}';
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _focusNode.requestFocus();
  }

  /// `/name` or `/name args` where name is a known command. With [requireArgsSeparator] only a
  /// name already followed by whitespace matches, so typing `/re` does not grab `/reload` early.
  (Map<String, dynamic>, String)? _matchTypedCommand(
    String text, {
    bool requireArgsSeparator = false,
  }) {
    final match = RegExp(r'^/(\S+)(\s+([\s\S]*))?$').firstMatch(text);
    if (match == null || (requireArgsSeparator && match.group(2) == null)) {
      return null;
    }
    final name = match.group(1)!.toLowerCase();
    final command = _availableCommands
        .where((c) => (c['name'] as String? ?? '').toLowerCase() == name)
        .firstOrNull;
    return command == null ? null : (command, match.group(3) ?? '');
  }

  Future<void> _runActiveCommand(
    Map<String, dynamic> command,
    String args,
    List<ChatAttachment> attachments,
    String? streamingBehavior,
  ) async {
    final strings = ref.read(appStringsProvider);
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final sending = ref.read(composerSendingProvider(widget.sessionId).notifier);
    final name = command['name'] as String? ?? '';
    final source = command['source'] as String? ?? 'prompt';
    final line = args.isEmpty ? '/$name' : '/$name $args';
    sending.state = true;
    setState(() => _commandRunning = true);
    try {
      switch (source) {
        case 'builtin':
        case 'extension':
          if (attachments.isNotEmpty) {
            throw StateError(strings.composerRemoveAttachmentsBeforePiCommand);
          }
          if (source == 'builtin') {
            await _runPiBuiltin(name, args);
          } else {
            await notifier.runCommand(line);
          }
        default:
          // Prompt templates and skills expand into a real user message.
          await notifier.sendPrompt(
            attachments.isNotEmpty
                ? '${encodeAttachmentsTag(attachments)}\n$line'
                : line,
            streamingBehavior: streamingBehavior,
          );
          ref.read(composerAttachmentsProvider(widget.sessionId).notifier).clear();
      }
      if (!mounted) return;
      setState(() => _activeCommand = null);
      _controller.clear();
      ref.read(composerDraftProvider(widget.sessionId).notifier).state = '';
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(context, message: strings.composerCommandFailed(error), isError: true);
      }
    } finally {
      if (sending.mounted) sending.state = false;
      if (mounted) setState(() => _commandRunning = false);
    }
  }

  Future<void> _runPiBuiltin(String name, String args) async {
    final strings = ref.read(appStringsProvider);
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    switch (name) {
      case 'side':
      case 'btw':
        final sideNotifier =
            ref.read(sideThreadFamily(widget.sessionId).notifier);
        if (args.isEmpty) {
          await sideNotifier.openSide();
        } else {
          await sideNotifier.openSide(question: args);
        }
        return;
      case 'settings':
        ref.read(showSettingsProvider.notifier).state = true;
        return;
      case 'model':
        if (args.isEmpty) return _showModelPicker(context);
        final models = await notifier.getAvailableModels();
        final target = args.toLowerCase();
        final matches = models.where((model) {
          final id = model['id']?.toString() ?? '';
          final provider = model['provider']?.toString() ?? '';
          final display = model['name']?.toString() ?? id;
          return id.toLowerCase() == target ||
              display.toLowerCase() == target ||
              '$provider/$id'.toLowerCase() == target;
        }).toList();
        if (matches.isEmpty) {
          throw StateError(strings.composerModelNotFound(args));
        }
        if (matches.length > 1) {
          throw StateError(strings.composerModelAmbiguous);
        }
        final selected = matches.single;
        await notifier.setModel(
          selected['provider']?.toString() ?? 'default',
          selected['id']?.toString() ?? args,
        );
        return;
      case 'thinking':
        if (args.isEmpty) return _showThinkingPicker(context);
        final levels = await notifier.getAvailableThinkingLevels();
        if (!mounted) return;
        final level = levels
            .where((item) => item.toLowerCase() == args.toLowerCase())
            .firstOrNull;
        if (level == null) {
          throw StateError(strings.composerThinkingLevelNotAvailable(args));
        }
        await notifier.setThinkingLevel(level);
        return;
      case 'tree':
        return SessionTreeDialog.show(context, sessionId: widget.sessionId);
      case 'new':
        return createSession(context, ref);
      case 'compact':
        await notifier.compact();
        return;
      case 'reload':
        await notifier.runCommand('/reload');
        return;
      case 'login':
        if (args.isNotEmpty) {
          throw StateError(strings.composerLoginNoArgs);
        }
        await notifier.piAuthLogin();
        await _loadModels();
        return;
      case 'logout':
        if (args.isNotEmpty) {
          throw StateError(strings.composerLogoutNoArgs);
        }
        await notifier.piAuthLogout();
        await _loadModels();
        return;
      case 'copy':
        final latest = ref
            .read(sessionStateFamily(widget.sessionId))
            .entries
            .where(
              (entry) =>
                  entry.role == 'assistant' && entry.text.trim().isNotEmpty,
            )
            .lastOrNull;
        if (latest == null) {
          throw StateError(strings.composerNoAgentMessageToCopy);
        }
        await Clipboard.setData(ClipboardData(text: latest.text));
        if (!mounted) return;
        FrameSnackBar.show(
          context,
          message: strings.composerLastAgentMessageCopied,
        );
        return;
      case 'name':
        final current =
            ref.read(sessionStateFamily(widget.sessionId)).sessionName ?? '';
        final name = args.isEmpty ? await _askSessionName(current) : args;
        if (name == null || name.trim().isEmpty) return;
        await notifier.rename(name.trim());
        ref.invalidate(sessionListProvider);
        return;
      case 'session':
        await _showPiSessionInfo();
        return;
      case 'clone':
        await _cloneFromSlash();
        return;
      case 'fork':
        await _forkFromSlash(args);
        return;
      case 'resume':
        await _resumeFromSlash();
        return;
      case 'quit':
        if (!await resolveDirtyRepository(context, ref, widget.sessionId)) {
          return;
        }
        await windowManager.close();
        return;
      default:
        FrameSnackBar.show(
          context,
          message: strings.composerTuiCommandNotice(name),
          duration: const Duration(seconds: 5),
        );
    }
  }

  Future<String?> _askSessionName(String initial) async {
    final strings = ref.read(appStringsProvider);
    final controller = TextEditingController(text: initial);
    try {
      String? saved;
      final submitted = await showFrameDialogBuilder<String>(
        context: context,
        instant: true,
        builder: (dialogContext) => FrameDialog<String>(
          title: strings.composerSessionNameTitle,
          body: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            FrameDialogAction<String>(
              label: strings.cancel,
              role: FrameDialogActionRole.cancel,
            ),
            FrameDialogAction<String>(
              label: strings.save,
              role: FrameDialogActionRole.primary,
              onPressed: () => saved = controller.text,
            ),
          ],
        ),
      );
      return submitted ?? saved;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _cloneFromSlash() async {
    if (!await resolveDirtyRepository(context, ref, widget.sessionId)) return;
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    final client = ref.read(pcpClientProvider);
    if (client == null) throw StateError(strings.composerDaemonNotConnected);
    final result = await client.cloneSession(widget.sessionId);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final targetId = (data['sessionId'] ?? data['id']) as String?;
    if (targetId == null) {
      throw StateError(strings.composerCloneNotReturned);
    }
    if (!mounted || !await switchSessionSafely(context, ref, targetId)) return;
    ref.invalidate(sessionListProvider);
  }

  Future<void> _forkFromSlash(String args) async {
    if (!await resolveDirtyRepository(context, ref, widget.sessionId)) return;
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    final state = ref.read(sessionStateFamily(widget.sessionId));
    var entryId = args.isEmpty ? null : args;
    if (entryId == null) {
      final userEntries = state.entries
          .where((entry) => entry.role == 'user')
          .toList();
      if (userEntries.isEmpty) {
        throw StateError(strings.composerForkNoUserMessages);
      }
      entryId = await showFrameDialogBuilder<String>(
        context: context,
        instant: true,
        builder: (dialogContext) => FrameDialog<String>(
          title: strings.composerForkTitle,
          maxWidth: 460,
          body: SizedBox(
            height: 360,
            child: ListView.builder(
              itemCount: userEntries.length,
              itemBuilder: (_, index) {
                final entry = userEntries[userEntries.length - 1 - index];
                return ListTile(
                  title: Text(
                    entry.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(entry.id),
                  onTap: () => Navigator.pop(dialogContext, entry.id),
                );
              },
            ),
          ),
          actions: [
            FrameDialogAction<String>(
              label: strings.cancel,
              role: FrameDialogActionRole.cancel,
            ),
          ],
        ),
      );
      if (entryId == null) return;
    }
    final client = ref.read(pcpClientProvider);
    if (client == null) throw StateError(strings.composerDaemonNotConnected);
    final result = await client.forkSession(widget.sessionId, entryId: entryId);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final targetId = (data['sessionId'] ?? data['id']) as String?;
    if (targetId == null) throw StateError(strings.composerForkNotCreated);
    if (!mounted || !await switchSessionSafely(context, ref, targetId)) return;
    ref.invalidate(sessionListProvider);
  }

  Future<void> _resumeFromSlash() async {
    ref.invalidate(sessionListProvider);
    final strings = ref.read(appStringsProvider);
    final sessions = await ref.read(sessionListProvider.future);
    if (!mounted) return;
    final sessionNames = ref.read(sessionDisplayNamesProvider);
    final selectedId = await showFrameDialogBuilder<String>(
      context: context,
      instant: true,
      builder: (dialogContext) => FrameDialog<String>(
        title: strings.composerResumeTitle,
        maxWidth: 460,
        body: SizedBox(
          height: 360,
          child: sessions.isEmpty
              ? Center(child: Text(strings.composerNoSessionsAvailable))
              : ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (_, index) {
                    final session = sessions[index];
                    final id = session['id']?.toString() ?? '';
                    return ListTile(
                      title: Text(
                        sessionNames[id] ?? session['name']?.toString() ?? id,
                      ),
                      subtitle: Text(
                        session['cwd']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: id.isEmpty
                          ? null
                          : () => Navigator.pop(dialogContext, id),
                    );
                  },
                ),
        ),
        actions: [
          FrameDialogAction<String>(
            label: strings.cancel,
            role: FrameDialogActionRole.cancel,
          ),
        ],
      ),
    );
    if (selectedId == null || !mounted) return;
    await switchSessionSafely(context, ref, selectedId);
  }

  Future<void> _showPiSessionInfo() async {
    final strings = ref.read(appStringsProvider);
    final state = ref.read(sessionStateFamily(widget.sessionId));
    final stats = state.sessionStats ?? const <String, dynamic>{};
    await showFrameDialogBuilder<void>(
      context: context,
      instant: true,
      builder: (dialogContext) => FrameDialog<void>(
        title: strings.composerPiSessionTitle,
        maxWidth: 440,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.composerSessionInfoName(state.sessionName ?? '—')),
            Text(strings.composerSessionInfoSession(state.sessionId)),
            Text(strings.composerSessionInfoFolder(state.cwd)),
            Text(strings.composerSessionInfoModel(state.currentModel ?? '—')),
            Text(
              strings.composerSessionInfoThinking(
                state.currentThinkingLevel ?? '—',
              ),
            ),
            const SizedBox(height: FrameSpace.x3),
            for (final entry in stats.entries)
              Text('${entry.key}: ${entry.value}'),
          ],
        ),
        actions: [
          FrameDialogAction<void>(
            label: strings.close,
            role: FrameDialogActionRole.cancel,
          ),
        ],
      ),
    );
  }

  Future<void> _showModelPicker(BuildContext chipContext) async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final models = await notifier.getAvailableModels().timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <Map<String, dynamic>>[],
    );
    if (!mounted || !chipContext.mounted) return;
    final tokens = context.tokens;
    final currentState = ref.read(sessionStateFamily(widget.sessionId));
    final currentModelIndex = models.indexWhere(currentState.matchesModel);

    if (models.isEmpty) {
      final strings = ref.read(appStringsProvider);
      FrameSnackBar.show(
        context,
        message: strings.composerNoAlternativeModels,
      );
      return;
    }

    final renderBox = chipContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    final selected = await showMenu<Map<String, dynamic>>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        (offset.dy - (models.length * 40).clamp(100, 360).toDouble()).clamp(
          40.0,
          double.infinity,
        ),
        offset.dx + 260,
        offset.dy,
      ),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      items: models.asMap().entries.map((entry) {
        final m = entry.value;
        final id = m['id']?.toString() ?? '';
        final name = m['name']?.toString() ?? id;
        final isCurrent = entry.key == currentModelIndex;
        return PopupMenuItem<Map<String, dynamic>>(
          value: m,
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: FrameSize.icon,
                color: isCurrent ? tokens.accent : tokens.textMuted,
              ),
              const SizedBox(width: FrameSpace.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: FrameText.of(context).label.copyWith(color: isCurrent ? tokens.accent : tokens.textPrimary, fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (m['provider'] != null)
                      Text(
                        m['provider'].toString(),
                        style: FrameText.of(context).caption.copyWith(color: tokens.textMuted),
                      ),
                  ],
                ),
              ),
              if (isCurrent) Icon(Icons.check_outlined, size: FrameSize.icon, color: tokens.accent),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      final provider = selected['provider']?.toString() ?? 'default';
      final id = selected['id']?.toString() ?? '';
      await notifier.setModel(provider, id);
    }
  }

  Future<void> _showThinkingPicker(BuildContext chipContext) async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final levels = await notifier.getAvailableThinkingLevels().timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <String>[],
    );
    final effectiveLevels = levels.isNotEmpty
        ? levels
        : const ['off', 'low', 'medium', 'high'];
    if (!mounted || !chipContext.mounted) return;
    final tokens = context.tokens;
    final current = ref
        .read(sessionStateFamily(widget.sessionId))
        .currentThinkingLevel;

    final renderBox = chipContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        (offset.dy - (effectiveLevels.length * 36).toDouble() - 10).clamp(
          40.0,
          double.infinity,
        ),
        offset.dx + 160,
        offset.dy,
      ),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      items: effectiveLevels.map((lvl) {
        final isCurrent = lvl.toLowerCase() == (current ?? '').toLowerCase();
        return PopupMenuItem<String>(
          key: ValueKey('thinking-level-option-$lvl'),
          value: lvl,
          height: 34,
          child: Row(
            children: [
              ThinkingLevelBars(
                level: lvl,
                litColor: isCurrent ? tokens.thinking : tokens.textSecondary,
              ),
              const SizedBox(width: FrameSpace.x2),
              Expanded(
                child: Text(
                  ref.read(appStringsProvider).thinkingLevelLabel(lvl),
                  style: FrameText.of(context).label.copyWith(color: isCurrent ? tokens.thinking : tokens.textPrimary, fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500),
                ),
              ),
              if (isCurrent)
                Icon(Icons.check_outlined, size: FrameSize.icon, color: tokens.thinking),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      await notifier.setThinkingLevel(selected);
    }
  }

  Future<void> _showContextSizePicker() async {
    if (_isContextPickerLoading) return;
    final sessionId = widget.sessionId;
    setState(() => _isContextPickerLoading = true);
    try {
      // The first load can precede the daemon connection. Retry instead of silently using an empty catalogue.
      await _loadModels();
      if (!mounted || widget.sessionId != sessionId) return;
      final currentState = ref.read(sessionStateFamily(sessionId));
      final model = _models.firstWhere(
        currentState.matchesModel,
        orElse: () => const <String, dynamic>{},
      );
      final maximum = modelContextWindow(model);
      if (maximum == null || maximum <= 0) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(
          context,
          message: strings.composerModelContextNotAvailableDaemon,
          isError: true,
        );
        return;
      }
      final strings = ref.read(appStringsProvider);
      setState(() => _isContextPickerLoading = false);
      await showFrameDialog<void>(
        context: context,
        dialog: FrameDialog<void>(
          key: const ValueKey('composer-context-size-dialog'),
          title: strings.composerContextSizeTitle,
          maxWidth: 340,
          body: ContextWindowSelector(sessionId: sessionId, model: model),
          actions: [
            FrameDialogAction<void>(
              label: strings.close,
              role: FrameDialogActionRole.cancel,
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(
          context,
          message: strings.composerContextSelectionFailed(error),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isContextPickerLoading = false);
    }
  }

  Widget _buildAttachButton(FrameTokens tokens, AppStrings strings) {
    return PopupMenuButton<String>(
      key: const ValueKey('composer-attach-popup-btn'),
      tooltip: strings.composerAttachTooltip,
      icon: Icon(Icons.attach_file_outlined, size: FrameSize.icon, color: tokens.textSecondary),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
          padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_outlined, size: FrameSize.icon, color: tokens.accent),
              const SizedBox(width: FrameSpace.x2),
              Flexible(
                child: Text(
                  strings.composerAttachFromRepo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FrameText.of(context).label.copyWith(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('attach-option-external'),
          value: 'external',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: FrameSize.icon,
                color: tokens.syntaxFunction,
              ),
              const SizedBox(width: FrameSpace.x2),
              Flexible(
                child: Text(
                  strings.composerAttachExternalFile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FrameText.of(context).label.copyWith(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('attach-option-link'),
          value: 'link',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_outlined, size: FrameSize.icon, color: tokens.syntaxKeyword),
              const SizedBox(width: FrameSpace.x2),
              Flexible(
                child: Text(
                  strings.composerAttachWebLink,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FrameText.of(context).label.copyWith(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('attach-option-image'),
          value: 'image',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: FrameSize.icon, color: tokens.syntaxType),
              const SizedBox(width: FrameSpace.x2),
              Flexible(
                child: Text(
                  strings.composerAttachImage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FrameText.of(context).label.copyWith(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isMobile = screenWidth < 600;
    final horizontalMargin = isMobile ? 14.0 : 8.0;
    final bottomMargin = isMobile
        ? (bottomPadding > 0 ? bottomPadding + 4.0 : 12.0)
        : 8.0;
    final isSending = ref.watch(composerSendingProvider(widget.sessionId));
    final attachments = ref.watch(
      composerAttachmentsProvider(widget.sessionId),
    );
    // Keep the whole composer (text, attachments AND the button row) inside the space that is left
    // above the on-screen keyboard. A long message used to grow past it, which clipped the toolbar
    // and pushed the text being typed out of view.
    final visibleHeight =
        widget.availableHeight ??
        (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom);
    final chromeHeight =
        110.0 + (attachments.isNotEmpty ? 66.0 : 0.0) + (_pendingUploads > 0 ? 24.0 : 0.0);
    final inputBudget =
        visibleHeight * (_isInputEnlarged ? 0.85 : 0.7) - chromeHeight;
    final maxInputLines = (inputBudget / 21).floor().clamp(2, 16);
    ref.listen<int>(composerFocusRequestProvider(widget.sessionId), (
      previous,
      request,
    ) {
      if (request != previous) _focusNode.requestFocus();
    });
    ref.listen<String>(composerDraftProvider(widget.sessionId), (
      previous,
      draft,
    ) {
      if (_controller.text != draft) {
        final currentSelection = _controller.selection;
        final newOffset =
            currentSelection.isValid &&
                currentSelection.baseOffset <= draft.length
            ? currentSelection.baseOffset
            : draft.length;
        _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      }
    });
    final composerSettings = ref.watch(composerSettingsProvider);
    final strings = ref.watch(appStringsProvider);
    final (
      readOnly,
      readOnlyReason,
      isStreaming,
      agentStatus,
      steeringQueue,
      followUpQueue,
      pendingUiRequests,
      activeToolCallsNotEmpty,
      currentModel,
      currentModelProvider,
      currentModelId,
      currentThinkingLevel,
      contextOverride,
      runStartedAt,
    ) = ref.watch(
      sessionStateFamily(widget.sessionId).select(
        (s) => (
          s.readOnly,
          s.readOnlyReason,
          // A stopped worker has no run left to stop or steer, even if the stream flag was not cleared.
          s.agentStatus != AgentStatus.workerError &&
              // Compaction runs inside the agent run: the daemon rejects a plain prompt then, so steer instead.
              (s.isStreaming || s.agentStatus == AgentStatus.compacting),
          s.agentStatus,
          s.steeringQueue,
          s.followUpQueue,
          s.pendingUiRequests,
          s.agentStatus != AgentStatus.workerError &&
              s.activeToolCalls.isNotEmpty,
          s.currentModel,
          s.currentModelProvider,
          s.currentModelId,
          s.currentThinkingLevel,
          s.contextWindowOverride,
          s.runStartedAt,
        ),
      ),
    );
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );
    if (readOnly) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              readOnlyReason == 'terminal'
                  ? strings.composerReadOnlyTerminalNotice
                  : strings.composerReadOnlyUnknownNotice,
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: FrameSpace.x2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (readOnlyReason == 'unknown') ...[
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(strings.composerContinueHereAction),
                    onPressed: _continueAmbiguousSession,
                  ),
                  const SizedBox(width: FrameSpace.x2),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(strings.composerCloneAndContinueAction),
                  onPressed: () async {
                    try {
                      final client = ref.read(pcpClientProvider);
                      if (client == null) {
                        throw StateError(strings.composerDaemonNotConnected);
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
                      final data =
                          (result['data'] as Map<String, dynamic>?) ?? result;
                      final targetSessionId =
                          (data['sessionId'] ?? data['id']) as String?;
                      if (targetSessionId != null) {
                        if (!await switchSessionSafely(
                          context,
                          ref,
                          targetSessionId,
                        )) {
                          return;
                        }
                        ref.invalidate(sessionListProvider);
                      }
                    } catch (error) {
                      if (context.mounted) {
                        FrameSnackBar.show(
                          context,
                          message: strings.composerDuplicationFailed(error),
                          isError: true,
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
    final isError = agentStatus == AgentStatus.workerError;
    final totalQueued = steeringQueue.length + followUpQueue.length;

    final activeModelMap = _models.firstWhere(
      (model) => currentModelId != null
          ? model['id']?.toString() == currentModelId &&
              (currentModelProvider == null ||
                  model['provider']?.toString() == currentModelProvider)
          : model['name'] == currentModel || model['id'] == currentModel,
      orElse: () => const {},
    );
    final isVariablePricing =
        hasVariableContextPricing(activeModelMap) ||
        (currentModel != null &&
            (currentModel.toLowerCase().contains('luna') ||
                currentModel.toLowerCase().contains('haiku')));
    final effectiveContextWindow =
        contextOverride ?? modelContextWindow(activeModelMap);
    final isLongPrompt =
        _controller.text.length > 80 || _controller.text.contains('\n');

    final pendingInteractionRequests = pendingUiRequests
        .where(
          (request) =>
              !_dismissedUiRequestIds.contains(
                request['requestId']?.toString(),
              ) &&
              _isInteractionRequest(request),
        )
        .toList();

    final isReviewing = ref.watch(isReviewingChangesProvider);
    final hasModifiedFiles = ref.watch(
      sessionHasModifiedFilesProvider(widget.sessionId),
    );
    final changeCount = ref.watch(
      sessionChangesProvider(widget.sessionId).select((s) => s.files.length),
    );

    final isShimmerActive =
        isSending ||
        isStreaming ||
        agentStatus == AgentStatus.working ||
        agentStatus == AgentStatus.retrying ||
        agentStatus == AgentStatus.compacting ||
        activeToolCallsNotEmpty;

    final isAgentAnswering =
        isStreaming ||
        agentStatus == AgentStatus.working ||
        activeToolCallsNotEmpty;

    return AnimatedContainer(
      duration: FrameMotion.panel,
      curve: FrameMotion.panelCurve,
      margin: EdgeInsets.fromLTRB(
        horizontalMargin,
        4,
        horizontalMargin,
        bottomMargin,
      ),
      child: ShimmerBorder(
        isActive: isShimmerActive,
        borderRadius: _composerRadius(tokens),
        child: _ComposerSizeAnimator(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: _composerRadius(tokens),
            ),
            child: pendingInteractionRequests.isNotEmpty
                ? Padding(
                    key: const ValueKey('composer-extension-ui-card'),
                    padding: const EdgeInsets.only(bottom: FrameSpace.x2),
                    child: ExtensionUiDialog(
                      key: ValueKey(
                        'ext_ui_${pendingInteractionRequests.last['requestId']}',
                      ),
                      sessionId: widget.sessionId,
                      request: pendingInteractionRequests.last,
                      isCard: true,
                      onDismissed: () {
                        if (!mounted) return;
                        setState(
                          () => _dismissedUiRequestIds.add(
                            pendingInteractionRequests.last['requestId']
                                .toString(),
                          ),
                        );
                      },
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status line while Pi answers. The field below stays visible and usable.
                      ComposerRunStatusLine(
                        active: isAgentAnswering,
                        startedAt: runStartedAt,
                        label: strings.composerAgentAnswering,
                        interruptLabel: strings.composerStopAction,
                        onInterrupt: _isInterrupting ? null : _interrupt,
                      ),
                      // File Mention overlay if active
                      if (_showFileMentionMenu &&
                          _matchingMentionFiles.isNotEmpty)
                        Padding(
                          key: const ValueKey('composer-file-mention-menu'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: FileMentionMenu(
                            key: const ValueKey(
                              'composer-file-mention-list',
                            ),
                            files: _matchingMentionFiles,
                            query: _fileMentionQuery,
                            selectedIndex: _fileMentionSelectedIndex,
                            onSelect: _completeFileMention,
                            strings: strings,
                          ),
                        ),

                      // Slash Menu overlay if active
                      if (_showSlashMenu && _availableCommands.isNotEmpty)
                        Padding(
                          key: const ValueKey('composer-slash-menu'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: SlashMenu(
                            key: const ValueKey('composer-slash-list'),
                            commands: _availableCommands,
                            filter: _controller.text,
                            selectedIndex: _slashSelectedIndex,
                            onSelect: _onSelectSlashCommand,
                            sourceLabel: strings.composerCommandSourceLabel,
                          ),
                        ),

                      // Pending Queue bar (if any queue exists)
                      if (totalQueued > 0)
                        Container(
                          key: const ValueKey('composer-queue-bar'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          color: tokens.surfaceElevated,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.queue_outlined,
                                    size: FrameSize.icon,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: FrameSpace.x2),
                                  Expanded(
                                    child: Text(
                                      strings.composerQueuedSummary(totalQueued, steeringQueue.length, followUpQueue.length),
                                      style: FrameText.of(context).label.copyWith(color: tokens.textSecondary),
                                    ),
                                  ),
                                  if (steeringQueue.isNotEmpty)
                                    IconButton(
                                      key: const ValueKey(
                                        'composer-queue-toggle-expand',
                                      ),
                                      tooltip: strings.composerToggleQueueTooltip(_queueExpanded),
                                      icon: Icon(
                                        _queueExpanded
                                            ? Icons.keyboard_arrow_up_outlined
                                            : Icons.keyboard_arrow_down_outlined,
                                        size: FrameSize.icon,
                                        color: tokens.textSecondary,
                                      ),
                                      onPressed: () => setState(
                                        () => _queueExpanded =
                                            !_queueExpanded,
                                      ),
                                    ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: Icon(
                                      Icons.clear_all_outlined,
                                      size: 14,
                                      color: tokens.textMuted,
                                    ),
                                    label: Text(
                                      strings.composerClearQueueAction,
                                      style: FrameText.of(context).caption.copyWith(color: tokens.textMuted),
                                    ),
                                    onPressed: () => _runAction(
                                      sessionNotifier.clearQueue,
                                    ),
                                  ),
                                ],
                              ),
                              if (_queueExpanded &&
                                  steeringQueue.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                for (
                                  var i = 0;
                                  i < steeringQueue.length;
                                  i++
                                )
                                  Container(
                                    key: ValueKey('steer-queue-item-$i'),
                                    margin: const EdgeInsets.only(
                                      bottom: 4,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      4,
                                      6,
                                      4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.surface,
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      border: Border.all(
                                        color: tokens.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 2,
                                              ),
                                          decoration: BoxDecoration(
                                            color: tokens.accent.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(
                                                  tokens.radiusSm,
                                                ),
                                          ),
                                          child: Text(
                                            'STEER #${i + 1}',
                                            style: FrameText.of(context).caption.copyWith(color: tokens.accent, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: FrameSpace.x2),
                                        Expanded(
                                          child: Text(
                                            steeringQueue[i],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: FrameText.of(context).label.copyWith(color: tokens.textPrimary, fontFamily:
                                                  tokens.monoFontFamily),
                                          ),
                                        ),
                                        IconButton(
                                          key: ValueKey(
                                            'edit-steer-btn-$i',
                                          ),
                                          tooltip: strings.composerEditSteerTooltip,
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: 14,
                                            color: tokens.accent,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 26,
                                            minHeight: 26,
                                          ),
                                          padding: EdgeInsets.zero,
                                          onPressed: () =>
                                              _showEditSteerDialog(
                                                context,
                                                i,
                                                steeringQueue[i],
                                              ),
                                        ),
                                        IconButton(
                                          key: ValueKey(
                                            'delete-steer-btn-$i',
                                          ),
                                          tooltip: strings.composerDeleteFromQueueTooltip,
                                          icon: Icon(
                                            Icons.close_outlined,
                                            size: 14,
                                            color: tokens.textMuted,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 26,
                                            minHeight: 26,
                                          ),
                                          padding: EdgeInsets.zero,
                                          onPressed: () => sessionNotifier
                                              .removeSteerMessage(i),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: tokens.danger.withValues(alpha: 0.15),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_outlined,
                                size: FrameSize.iconLg,
                                color: tokens.danger,
                              ),
                              const SizedBox(width: FrameSpace.x2),
                              Expanded(
                                child: Text(
                                  strings.composerWorkerCrashBanner,
                                  style: FrameText.of(context).label.copyWith(color: tokens.danger, fontWeight: FontWeight.w500),
                                ),
                              ),
                              const SizedBox(width: FrameSpace.x2),
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
                                icon: const Icon(Icons.refresh_outlined, size: FrameSize.icon),
                                label: Text(
                                  strings.composerRecoverSessionAction,
                                  style: FrameText.of(context).label.copyWith(fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _runAction(
                                  sessionNotifier.recoverSession,
                                ),
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
                            if (event is KeyDownEvent ||
                                event is KeyRepeatEvent) {
                              final slashItems = _showSlashMenu
                                  ? SlashMenu.filtered(
                                      _availableCommands,
                                      _controller.text,
                                    )
                                  : const <Map<String, dynamic>>[];
                              final key = event.logicalKey;
                              if (slashItems.isNotEmpty) {
                                if (key == LogicalKeyboardKey.arrowDown ||
                                    key == LogicalKeyboardKey.arrowUp) {
                                  final step =
                                      key == LogicalKeyboardKey.arrowDown ? 1 : -1;
                                  setState(() {
                                    _slashSelectedIndex =
                                        (_slashSelectedIndex + step) %
                                        slashItems.length;
                                  });
                                  return KeyEventResult.handled;
                                }
                                if (event is KeyDownEvent &&
                                    (key == LogicalKeyboardKey.tab ||
                                        key == LogicalKeyboardKey.enter ||
                                        key == LogicalKeyboardKey.numpadEnter) &&
                                    !HardwareKeyboard.instance.isShiftPressed) {
                                  _activateCommand(
                                    slashItems[_slashSelectedIndex.clamp(
                                      0,
                                      slashItems.length - 1,
                                    )],
                                  );
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.escape) {
                                  setState(() => _showSlashMenu = false);
                                  return KeyEventResult.handled;
                                }
                              }
                              final selection = _controller.selection;
                              if (_activeCommand != null &&
                                  key == LogicalKeyboardKey.backspace &&
                                  selection.isCollapsed &&
                                  selection.baseOffset <= 0) {
                                _removeCommand();
                                return KeyEventResult.handled;
                              }
                            }
                            if (event is KeyDownEvent) {
                              // File Mention keyboard navigation
                              if (_showFileMentionMenu &&
                                  _matchingMentionFiles.isNotEmpty) {
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  setState(() {
                                    _fileMentionSelectedIndex =
                                        (_fileMentionSelectedIndex + 1) %
                                        _matchingMentionFiles.length;
                                  });
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                                  setState(() {
                                    _fileMentionSelectedIndex =
                                        (_fileMentionSelectedIndex -
                                            1 +
                                            _matchingMentionFiles.length) %
                                        _matchingMentionFiles.length;
                                  });
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.tab ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.numpadEnter) {
                                  final chosen =
                                      _matchingMentionFiles[_fileMentionSelectedIndex]['path']
                                          ?.toString() ??
                                      '';
                                  if (chosen.isNotEmpty) {
                                    _completeFileMention(chosen);
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.escape) {
                                  setState(
                                    () => _showFileMentionMenu = false,
                                  );
                                  return KeyEventResult.handled;
                                }
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.escape) {
                                // With a layer open (drawer, Review mode...), Escape
                                // goes to the shell, which closes that layer first.
                                if (isStreaming &&
                                    !ref.read(escapeLayersProvider).isOpen) {
                                  _interrupt();
                                  return KeyEventResult.handled;
                                }
                              }
                            }

                            final isEnter =
                                event.logicalKey ==
                                    LogicalKeyboardKey.enter ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.numpadEnter;

                            if (isEnter &&
                                (event is KeyDownEvent ||
                                    event is KeyRepeatEvent)) {
                              // b. IME composition active -> never send
                              if (_controller.value.composing.isValid) {
                                return KeyEventResult.ignored;
                              }

                              final isShift =
                                  HardwareKeyboard.instance.isShiftPressed;
                              final isCtrl =
                                  HardwareKeyboard.instance.isControlPressed;
                              final isMeta =
                                  HardwareKeyboard.instance.isMetaPressed;
                              final isAlt =
                                  HardwareKeyboard.instance.isAltPressed;
                              final sendWithEnter =
                                  composerSettings.sendWithEnter;

                              void triggerSend() {
                                if (isStreaming) {
                                  _send(streamingBehavior: 'steer');
                                } else {
                                  _send();
                                }
                              }

                              if (sendWithEnter) {
                                // ON mode:
                                // Shift+Enter -> newline (manual insertion kept: multiline TextField does not insert \n on Shift+Enter)
                                if (isShift) {
                                  _insertNewlineAtSelection();
                                  return KeyEventResult.handled;
                                }
                                // Ctrl/Cmd+Enter or plain Enter sends
                                if (isCtrl || isMeta || !isAlt) {
                                  if (event is KeyDownEvent) {
                                    triggerSend();
                                  }
                                  return KeyEventResult.handled;
                                }
                              } else {
                                // OFF mode:
                                // Ctrl/Cmd+Enter sends; everything else returns KeyEventResult.ignored
                                // so TextField inserts newlines natively (restore original behavior; numpadEnter included).
                                if (isCtrl || isMeta) {
                                  if (event is KeyDownEvent) {
                                    triggerSend();
                                  }
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_pendingUploads > 0)
                                Padding(
                                  key: const ValueKey(
                                    'composer-upload-progress',
                                  ),
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: FrameActivityIndicator(size: 12, color: Theme.of(context).colorScheme.primary, 
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: FrameSpace.x2),
                                      Text(
                                        strings.composerUploadingAttachments(
                                          _pendingUploads,
                                        ),
                                        style: FrameText.of(context).caption.copyWith(color: tokens.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              if (attachments.isNotEmpty)
                                AttachmentListBar(
                                  key: const ValueKey(
                                    'composer-attachments-bar',
                                  ),
                                  attachments: attachments,
                                  isEditable: true,
                                  onRemove: (a) => ref
                                      .read(
                                        composerAttachmentsProvider(
                                          widget.sessionId,
                                        ).notifier,
                                      )
                                      .remove(a.id),
                                ),
                              Stack(
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                  AnimatedSize(
                                    duration: MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : FrameMotion.small,
                                    curve: FrameMotion.enterCurve,
                                    child: AnimatedSwitcher(
                                      duration: MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : FrameMotion.small,
                                      transitionBuilder: (child, animation) => FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                                          alignment: Alignment.centerLeft,
                                          child: child,
                                        ),
                                      ),
                                      child: _activeCommand == null
                                          ? const SizedBox(key: ValueKey('no-command'))
                                          : Padding(
                                              key: ValueKey('command-${_activeCommand!['name']}'),
                                              padding: const EdgeInsets.fromLTRB(2, 2, 4, 0),
                                              child: ComposerCommandChip(
                                                key: const ValueKey('composer-command-chip'),
                                                name: _activeCommand!['name'] as String? ?? '',
                                                sourceLabel: strings.composerCommandSourceLabel(
                                                  _activeCommand!['source'] as String? ?? 'prompt',
                                                ),
                                                removeTooltip: strings.composerRemoveCommandTooltip,
                                                running: _commandRunning,
                                                onRemove: _removeCommand,
                                              ),
                                            ),
                                    ),
                                  ),
                                  Expanded(
                                    key: const ValueKey('composer-input'),
                                    child: TextField(
                                    key: const ValueKey(
                                      'composer-text-field',
                                    ),
                                    cursorColor: tokens.accent,
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    maxLines: math.min(
                                      _isInputEnlarged ? 16 : 5,
                                      maxInputLines,
                                    ),
                                    minLines: math.min(
                                      _isInputEnlarged ? 8 : 2,
                                      maxInputLines,
                                    ),
                                    onChanged: (_) {
                                      if (mounted) setState(() {});
                                    },
                                    // Phone browser: Flutter's text and the hidden native <textarea>
                                    // behind it must wrap identically, otherwise iOS (long-press
                                    // selection, spacebar trackpad) moves the caret by lines that
                                    // do not exist on screen. 16px is also what stops iOS from
                                    // zooming the page when the field gets focus; the 21px line
                                    // height is unchanged.
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: kIsWeb && isMobile ? 16 : 14.5,
                                      height: kIsWeb && isMobile ? 21 / 16 : 1.45,
                                    ),
                                    cursorWidth: kIsWeb && isMobile ? 2.5 : 2.0,
                                    decoration: InputDecoration(
                                      hintText: _activeCommand != null
                                          ? strings.composerCommandArgsHint(
                                              _activeCommand!['name'] as String? ?? '',
                                              _activeCommand!['argumentHint'] as String? ?? '',
                                            )
                                          : strings.composerInputHint(
                                              isStreaming: isStreaming,
                                              sendWithEnter: composerSettings.sendWithEnter,
                                            ),
                                      hintStyle: FrameText.of(context).body.copyWith(color: tokens.textMuted),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.fromLTRB(
                                        4,
                                        2,
                                        (!isMobile &&
                                                (isLongPrompt ||
                                                    _isInputEnlarged))
                                            ? 80
                                            : 4,
                                        6,
                                      ),
                                    ),
                                  ),
                                  ),
                                    ],
                                  ),
                                  if (!isMobile &&
                                      (isLongPrompt || _isInputEnlarged))
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Tooltip(
                                        message: strings.composerEnlargeTooltip(_isInputEnlarged),
                                        child: InkWell(
                                          key: const ValueKey(
                                            'composer-enlarge-prompt-btn',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(
                                                tokens.radiusSm,
                                              ),
                                          onTap: () => setState(
                                            () => _isInputEnlarged =
                                                !_isInputEnlarged,
                                          ),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 3,
                                                ),
                                            decoration: BoxDecoration(
                                              color: tokens.surfaceElevated,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    tokens.radiusSm,
                                                  ),
                                              border: Border.all(
                                                color: _isInputEnlarged
                                                    ? tokens.accent
                                                    : tokens.border,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _isInputEnlarged
                                                      ? Icons
                                                            .close_fullscreen
                                                      : Icons.open_in_full_outlined,
                                                  size: 11,
                                                  color: _isInputEnlarged
                                                      ? tokens.accent
                                                      : tokens
                                                            .textSecondary,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  strings.composerEnlargeLabel(_isInputEnlarged),
                                                  style: FrameText.of(context).caption.copyWith(color: _isInputEnlarged
                                                        ? tokens.accent
                                                        : tokens
                                                              .textSecondary, fontWeight:
                                                        FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: FrameSpace.x1),
                              LayoutBuilder(
                                builder: (context, rowBox) => Row(
                                children: [
                                  Expanded(
                                    // Chip budget (plan 4.4). The model name takes the width the other
                                    // chips leave. The thinking label drops before the name does. The
                                    // scroll view is only a last resort below the chips' floor width.
                                    child: LayoutBuilder(
                                      builder: (context, chipBox) {
                                        final showThinkingLabel =
                                            chipBox.maxWidth >=
                                            kComposerThinkingLabelMinBox;
                                        // Compact: no picker arrows, and the context chip shows its icon only.
                                        final compact =
                                            chipBox.maxWidth <
                                            kComposerCompactChipBox;
                                        final thinkingWidth =
                                            (kComposerThinkingChipWidth -
                                                (compact
                                                    ? kComposerChipArrowWidth
                                                    : 0)) +
                                            (showThinkingLabel
                                                ? kComposerThinkingLabelWidth
                                                : 0);
                                        final showContextLabel = !compact;
                                        final contextWidth = isVariablePricing
                                            ? kComposerChipGap +
                                                  (showContextLabel
                                                      ? kComposerContextChipWidth
                                                      : kComposerContextIconChipWidth -
                                                            kComposerChipArrowWidth)
                                            : 0.0;
                                        final modelWidth =
                                            (chipBox.maxWidth -
                                                    thinkingWidth -
                                                    contextWidth -
                                                    kComposerChipGap)
                                                .clamp(
                                                  kComposerModelChipMinWidth,
                                                  kComposerModelChipMaxWidth,
                                                )
                                                .toDouble();
                                        return SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: modelWidth,
                                                ),
                                                child: Builder(
                                                  builder: (chipCtx) => Tooltip(
                                                    message: strings.composerChangeModelTooltip,
                                                    child: InkWell(
                                                      key: const ValueKey(
                                                        'composer-model-picker-btn',
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            tokens.radiusSm,
                                                          ),
                                                      onTap: () => _guardPicker(
                                                        () => _showModelPicker(
                                                          chipCtx,
                                                        ),
                                                      ),
                                                      child: Container(
                                                        height: 26,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 7,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: tokens
                                                              .surfaceElevated,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                tokens.radiusSm,
                                                              ),
                                                          border: Border.all(
                                                            color: tokens.border,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.smart_toy_outlined,
                                                              size: 13,
                                                              color: tokens.accent,
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            // The name truncates to the chip's budget; it is never hidden.
                                                            Flexible(
                                                              child: Text(
                                                                currentModel ??
                                                                    strings.composerModelDefaultLabel,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: FrameText.of(context).caption.copyWith(color: tokens
                                                                      .textSecondary, fontWeight:
                                                                      FontWeight
                                                                          .w500),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Icon(
                                                              Icons
                                                                  .keyboard_arrow_down,
                                                              size: 13,
                                                              color: tokens
                                                                  .textMuted,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(
                                                width: kComposerChipGap,
                                              ),
                                              Builder(
                                                builder: (chipCtx) => Tooltip(
                                                  message: strings.composerThinkingLevelTooltip,
                                                  child: InkWell(
                                                    key: const ValueKey(
                                                      'composer-thinking-picker-btn',
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          tokens.radiusSm,
                                                        ),
                                                    onTap: () => _guardPicker(
                                                      () => _showThinkingPicker(
                                                        chipCtx,
                                                      ),
                                                    ),
                                                    child: Container(
                                                      height: 26,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: tokens
                                                            .surfaceElevated,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              tokens.radiusSm,
                                                            ),
                                                        border: Border.all(
                                                          color: tokens.border,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          // The bars show the level in four steps. The label drops first when space is short.
                                                          ThinkingLevelBars(
                                                            level: currentThinkingLevel,
                                                            litColor: tokens.thinking,
                                                          ),
                                                          if (showThinkingLabel) ...[
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              strings.thinkingLevelLabel(
                                                                currentThinkingLevel ??
                                                                    'medium',
                                                              ),
                                                              maxLines: 1,
                                                              style: FrameText.of(context).caption.copyWith(color: tokens
                                                                    .textSecondary, fontWeight:
                                                                    FontWeight
                                                                        .w500),
                                                            ),
                                                          ],
                                                          if (!compact) ...[
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .keyboard_arrow_down,
                                                            size: 13,
                                                            color: tokens
                                                                .textMuted,
                                                          ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (isVariablePricing) ...[
                                                const SizedBox(
                                                  width: kComposerChipGap,
                                                ),
                                                Builder(
                                                  builder: (chipCtx) => Tooltip(
                                                    message: strings.composerVariablePricingContextTooltip,
                                                    child: InkWell(
                                                      key: const ValueKey(
                                                        'composer-context-size-picker-btn',
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            tokens.radiusSm,
                                                          ),
                                                      onTap:
                                                          _showContextSizePicker,
                                                      child: Container(
                                                        height: 26,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 7,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: tokens
                                                              .surfaceElevated,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                tokens.radiusSm,
                                                              ),
                                                          border: Border.all(
                                                            color: tokens.accent
                                                                .withValues(
                                                                  alpha: 0.35,
                                                                ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            if (_isContextPickerLoading)
                                                              SizedBox(
                                                                width: 12,
                                                                height: 12,
                                                                child: FrameActivityIndicator(size: 12, 
                                                                  strokeWidth:
                                                                      1.5,
                                                                  color: tokens
                                                                      .accent,
                                                                ),
                                                              )
                                                            else
                                                              Icon(
                                                                Icons.tune_outlined,
                                                                size: 12,
                                                                color: tokens
                                                                    .accent,
                                                              ),
                                                            if (showContextLabel) ...[
                                                              const SizedBox(
                                                                width: 3,
                                                              ),
                                                              Text(
                                                                formatTokens(
                                                                  effectiveContextWindow,
                                                                ),
                                                                maxLines: 1,
                                                                style: FrameText.of(context).caption.copyWith(color: tokens
                                                                      .accent, fontWeight:
                                                                      FontWeight
                                                                          .w600),
                                                              ),
                                                            ],
                                                            if (!compact) ...[
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Icon(
                                                              Icons
                                                                  .keyboard_arrow_down,
                                                              size: 12,
                                                              color: tokens
                                                                  .textMuted,
                                                            ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  // A 28 px target like the other row controls (the padded IconButton is 40).
                                  FrameIconAction(
                                    key: const ValueKey(
                                      'composer-enlarge-toggle-btn',
                                    ),
                                    icon: _isInputEnlarged
                                        ? Icons.close_fullscreen_outlined
                                        : Icons.open_in_full_outlined,
                                    tooltip: strings.composerEnlargeTooltip(
                                      _isInputEnlarged,
                                    ),
                                    selected: _isInputEnlarged || isLongPrompt,
                                    onPressed: () => setState(
                                      () => _isInputEnlarged = !_isInputEnlarged,
                                    ),
                                  ),
                                  const SizedBox(width: FrameSpace.x1),
                                  _buildAttachButton(tokens, strings),
                                  const SizedBox(width: FrameSpace.x1),
                                  if (isStreaming ||
                                      agentStatus == AgentStatus.working ||
                                      activeToolCallsNotEmpty) ...[
                                    IconButton(
                                      icon: _isInterrupting
                                          ? SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  FrameActivityIndicator(size: FrameSize.icon, 
                                                    strokeWidth: 2,
                                                    color: tokens.danger,
                                                  ),
                                            )
                                          : Icon(
                                              Icons.stop_circle_outlined,
                                              color: tokens.signalDanger,
                                              size: FrameSize.iconLg,
                                            ),
                                      tooltip: strings.composerStopEscTooltip,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed: _isInterrupting
                                          ? null
                                          : _interrupt,
                                    ),
                                    const SizedBox(width: FrameSpace.x1),
                                    Tooltip(
                                      message: strings.composerSteerTooltip(
                                        sendWithEnter:
                                            composerSettings.sendWithEnter,
                                      ),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: tokens.accent,
                                          borderRadius:
                                              BorderRadius.circular(
                                                tokens.radiusSm,
                                              ),
                                        ),
                                        child: IconButton(
                                          key: const ValueKey(
                                            'composer-steer-btn',
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Icon(
                                                Icons.bolt_outlined,
                                                size: FrameSize.icon,
                                                color:
                                                    tokens.accentContrast,
                                              ),
                                              SizedBox(
                                                width: 0,
                                                height: 0,
                                                child: Text(
                                                  'Steer',
                                                  style: FrameText.of(context).caption.copyWith(color: tokens.background
                                                        .withValues(
                                                          alpha: 0,
                                                        )),
                                                ),
                                              ),
                                            ],
                                          ),
                                          onPressed: isSending
                                              ? null
                                              : () => _send(
                                                  streamingBehavior:
                                                      'steer',
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: FrameSpace.x1),
                                    Tooltip(
                                      message: strings.composerFollowUpTooltip,
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceElevated,
                                          borderRadius:
                                              BorderRadius.circular(
                                                tokens.radiusSm,
                                              ),
                                          border: Border.all(
                                            color: tokens.border,
                                          ),
                                        ),
                                        child: IconButton(
                                          key: const ValueKey(
                                            'composer-followup-btn',
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Icon(
                                                Icons.more_time_outlined,
                                                size: FrameSize.icon,
                                                color: tokens.textPrimary,
                                              ),
                                              SizedBox(
                                                width: 0,
                                                height: 0,
                                                child: Text(
                                                  'Follow-up',
                                                  style: FrameText.of(context).caption.copyWith(color: tokens.background
                                                        .withValues(
                                                          alpha: 0,
                                                        )),
                                                ),
                                              ),
                                            ],
                                          ),
                                          onPressed: isSending
                                              ? null
                                              : () => _send(
                                                  streamingBehavior:
                                                      'followUp',
                                                ),
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    ComposerReviewButton(
                                      label: strings.composerReviewChangesLabel(
                                        changeCount,
                                      ),
                                      showLabel:
                                          rowBox.maxWidth >=
                                          kComposerReviewLabelMinRowWidth,
                                      reviewing: isReviewing,
                                      enabledTooltip: strings.composerReviewChangesTooltip(
                                        isReviewing,
                                      ),
                                      disabledTooltip:
                                          strings.composerReviewChangesNoneTooltip,
                                      onPressed: !hasModifiedFiles
                                          ? null
                                          : () => ref
                                                .read(isReviewingChangesProvider.notifier)
                                                .update((v) => !v),
                                    ),
                                    const SizedBox(width: FrameSpace.x1),
                                    Tooltip(
                                      key: const ValueKey('composer-send'),
                                      message: strings.composerSendTooltip(
                                        sendWithEnter:
                                            composerSettings.sendWithEnter,
                                      ),
                                      child: PressFeedback(
                                        child: FilledButton(
                                          key: const ValueKey(
                                            'composer-send-btn',
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: tokens.accent,
                                            foregroundColor:
                                                tokens.accentContrast,
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(28, 28),
                                            tapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    tokens.radiusSm,
                                                  ),
                                            ),
                                          ),
                                          onPressed: isSending
                                              ? null
                                              : () => _send(),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              if (isSending)
                                                SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      FrameActivityIndicator(size: 14, 
                                                        strokeWidth: 2,
                                                        color: tokens
                                                            .accentContrast,
                                                      ),
                                                )
                                              else
                                                Icon(
                                                  Icons.arrow_upward_outlined,
                                                  size: FrameSize.icon,
                                                  color:
                                                      tokens.accentContrast,
                                                ),
                                              SizedBox(
                                                width: 0,
                                                height: 0,
                                                child: Text(
                                                  strings.composerSendLabel,
                                                  style: FrameText.of(context).caption.copyWith(color: tokens.background
                                                        .withValues(
                                                          alpha: 0,
                                                        )),
                                                ),
                                              ),
                                              if (isSending)
                                                const SizedBox(
                                                  width: 0,
                                                  height: 0,
                                                  child: Icon(
                                                    Icons.arrow_upward_outlined,
                                                    size: 0,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
