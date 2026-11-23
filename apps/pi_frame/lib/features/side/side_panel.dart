import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/composer/composer_settings.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../domain/session/session_state.dart';
import '../../ui/escape_layers.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/motion.dart';
import '../composer/composer_draft.dart';
import '../tool_timeline/tool_card.dart';
import '../transcript/rich_content.dart';
import '../transcript/thinking_block.dart';
import 'side_provider.dart';

class SidePanel extends ConsumerStatefulWidget {
  final String sessionId;

  /// True when the side thread fills the whole pane (chat too narrow to share it).
  /// The header then shows a back button that returns to the chat.
  final bool fullPane;
  final VoidCallback? onClose;

  /// False inside the plugins pane, whose header hides the whole pane.
  final bool showCloseButton;

  const SidePanel({
    super.key,
    required this.sessionId,
    this.fullPane = false,
    this.onClose,
    this.showCloseButton = true,
  });

  @override
  ConsumerState<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends ConsumerState<SidePanel> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  ProviderSubscription<SideThreadState>? _threadSub;
  void Function()? _unregisterEscape;

  @override
  void initState() {
    super.initState();
    // The draft outlives the panel: hiding the plugins pane must not lose it.
    _textController.text = ref.read(sideDraftFamily(widget.sessionId));
    _textController.addListener(_saveDraft);
    // Escape closes the side conversation while it is open (plan task 10.1).
    _threadSub = ref.listenManual<SideThreadState>(
      sideThreadFamily(widget.sessionId),
      (_, next) => _syncEscape(next.isOpen),
      fireImmediately: true,
    );
  }

  void _saveDraft() {
    final draft = ref.read(sideDraftFamily(widget.sessionId).notifier);
    if (draft.state != _textController.text) draft.state = _textController.text;
  }

  void _syncEscape(bool open) {
    if (open) {
      _unregisterEscape ??= ref.read(escapeLayersProvider).register(EscapeLayer.drawer, _escapeClose);
    } else {
      _unregisterEscape?.call();
      _unregisterEscape = null;
    }
  }

  bool _escapeClose() {
    if (!mounted) return false;
    // Opened from the keyboard: an instant dialog takes focus at once, so the
    // next Escape dismisses it.
    unawaited(_requestClose(context, fromKeyboard: true));
    return true;
  }

  @override
  void dispose() {
    _unregisterEscape?.call();
    _threadSub?.close();
    _textController.removeListener(_saveDraft);
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: FrameMotion.small,
          curve: FrameMotion.enterCurve,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await ref.read(sideThreadFamily(widget.sessionId).notifier).prompt(text);
    _scrollToBottom();
  }

  /// Closes the side thread. Asks first only when the mini composer holds a draft,
  /// since closing discards it (plan task 10.1).
  Future<void> _requestClose(BuildContext context, {bool fromKeyboard = false}) async {
    final hasDraft = _textController.text.trim().isNotEmpty;
    if (!hasDraft) {
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        await ref.read(sideThreadFamily(widget.sessionId).notifier).close();
      }
      return;
    }
    final strings = ref.read(appStringsProvider);

    final confirmed = await showFrameDialog<bool>(
      context: context,
      instant: fromKeyboard,
      dialog: FrameDialog<bool>(
        title: strings.sideCloseConfirmTitle,
        body: Text(strings.sideCloseConfirmContent),
        actions: [
          FrameDialogAction<bool>(label: strings.cancel, role: FrameDialogActionRole.cancel, value: false),
          FrameDialogAction<bool>(
            label: strings.close,
            role: FrameDialogActionRole.destructive,
            key: const ValueKey('side-confirm-close-btn'),
            value: true,
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        await ref.read(sideThreadFamily(widget.sessionId).notifier).close();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rendered even while closed: SideSplit animates the width, and the content
    // fades out with it. The draft in the mini composer survives a hide.
    final sideThread = ref.watch(sideThreadFamily(widget.sessionId));
    final sideSession = ref.watch(sideSessionFamily(widget.sessionId));
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final composerSettings = ref.watch(composerSettingsProvider);

    final isStreaming = sideSession.isStreaming || sideThread.isOpening;

    // Listen to changes in entries or streaming text to scroll down
    ref.listen(sideSessionFamily(widget.sessionId), (_, next) {
      if (next.entries.isNotEmpty || next.isStreaming) {
        _scrollToBottom();
      }
    });

    final selectedId = sideThread.selectedConversationId;
    final isLive = selectedId == null || selectedId == sideThread.sideId;
    final SideConversationRecord? selectedRecord = sideThread.conversations.cast<SideConversationRecord?>().firstWhere(
      (c) => c?.id == selectedId,
      orElse: () => sideThread.conversations.isNotEmpty ? sideThread.conversations.last : null,
    );

    final isClosed =
        (isLive && (sideThread.closeReason != null || sideThread.isClosed)) ||
        (!isLive && selectedRecord?.status == 'closed');

    return Container(
      key: const ValueKey('side-panel-container'),
      // Flat surface: the split divider draws the edge, so no shadow (task 2.4).
      decoration: BoxDecoration(color: tokens.surfaceElevated),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(tokens, strings, sideThread, isStreaming),

          // Notice banner if side.closed
          if (isClosed) _buildClosedNotice(tokens, strings, sideThread),

          // Error banner if in error state
          if (sideThread.isError || selectedRecord?.status == 'error')
            _buildErrorNotice(
              tokens,
              sideThread.errorMessage ?? selectedRecord?.errorMessage ?? strings.sideConversationError,
            ),

          // Transcript
          Expanded(
            child: _buildTranscript(tokens, strings, sideThread, sideSession, isStreaming, selectedRecord, isLive),
          ),

          // Mini Composer
          _buildMiniComposer(tokens, strings, composerSettings, isStreaming),
        ],
      ),
    );
  }

  Widget _buildHeader(FrameTokens tokens, AppStrings strings, SideThreadState sideThread, bool isStreaming) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Full-pane view: back to the chat. Hides the side without closing it.
              if (widget.fullPane) ...[
                IconButton(
                  key: const ValueKey('side-back-btn'),
                  visualDensity: VisualDensity.compact,
                  tooltip: strings.sideBackTooltip,
                  icon: Icon(Icons.arrow_back_outlined, size: FrameSize.iconLg, color: tokens.textSecondary),
                  onPressed: () => ref.read(sideThreadFamily(widget.sessionId).notifier).closePanel(),
                ),
                const SizedBox(width: FrameSpace.x1),
              ],
              // Badge 'Side · read-only'. Flexible so a narrow pane ellipsizes
              // it instead of overflowing the header row.
              Flexible(
                child: Container(
                  key: const ValueKey('side-read-only-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_split_outlined, size: 13, color: tokens.textSecondary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          strings.sideReadOnlyBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FrameText.of(context).caption.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Model chip
              if (sideThread.model != null && sideThread.model!.isNotEmpty) ...[
                const SizedBox(width: FrameSpace.x2),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      sideThread.model!,
                      style: FrameText.of(context).caption
                          .copyWith(color: tokens.textSecondary, fontFamily: tokens.monoFontFamily),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // New conversation button
              IconButton(
                key: const ValueKey('side-new-conversation-btn'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                tooltip: strings.sideNewConversationTooltip,
                icon: Icon(Icons.add_outlined, size: FrameSize.iconLg, color: tokens.accent),
                onPressed: () => ref.read(sideThreadFamily(widget.sessionId).notifier).newConversation(),
              ),

              // Stop button if streaming
              if (isStreaming)
                IconButton(
                  key: const ValueKey('side-abort-btn'),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: strings.sideStopTooltip,
                  icon: Icon(Icons.stop_circle_outlined, size: FrameSize.iconLg, color: tokens.danger),
                  onPressed: () => ref.read(sideThreadFamily(widget.sessionId).notifier).abort(),
                ),

              // Close button
              if (widget.showCloseButton)
                IconButton(
                  key: const ValueKey('side-close-btn'),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: strings.sideCloseTooltip,
                  icon: Icon(Icons.close_outlined, size: FrameSize.iconLg, color: tokens.textSecondary),
                  onPressed: () => _requestClose(context),
                ),
            ],
          ),
          const SizedBox(height: FrameSpace.x1),
          Text(
            strings.sideNotPartOfMain,
            style: FrameText.of(context).caption.copyWith(color: tokens.textMuted, fontStyle: FontStyle.italic),
          ),
          if (sideThread.conversations.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildConversationSelector(tokens, strings, sideThread),
          ],
        ],
      ),
    );
  }

  Widget _buildConversationSelector(FrameTokens tokens, AppStrings strings, SideThreadState sideThread) {
    final selectedId = sideThread.selectedConversationId;
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sideThread.conversations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final conv = sideThread.conversations[index];
          final isSelected =
              conv.id == selectedId || (selectedId == null && index == sideThread.conversations.length - 1);
          final isConvActive = conv.status == 'active';
          return InkWell(
            key: ValueKey('side-conv-pill-${conv.id}'),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            onTap: () => ref.read(sideThreadFamily(widget.sessionId).notifier).selectConversation(conv.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accent.withValues(alpha: 0.15) : tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: isSelected ? tokens.accent : tokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConvActive
                          ? tokens.syntaxFunction
                          : (conv.status == 'error' ? tokens.danger : tokens.textMuted),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FrameText.of(context).caption.copyWith(
                        color: isSelected ? tokens.textPrimary : tokens.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (sideThread.conversations.length > 1) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      key: ValueKey('side-conv-delete-${conv.id}'),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      onTap: () => ref.read(sideThreadFamily(widget.sessionId).notifier).deleteConversation(conv.id),
                      child: Icon(Icons.close, size: 12, color: tokens.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorNotice(FrameTokens tokens, String error) {
    return Container(
      key: const ValueKey('side-error-notice'),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: FrameSpace.x2),
      decoration: BoxDecoration(
        color: tokens.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: FrameSize.icon, color: tokens.danger),
          const SizedBox(width: FrameSpace.x2),
          Expanded(
            child: Text(error, style: FrameText.of(context).caption.copyWith(color: tokens.danger)),
          ),
        ],
      ),
    );
  }

  Widget _buildClosedNotice(FrameTokens tokens, AppStrings strings, SideThreadState sideThread) {
    final reason = sideThread.closeReason ?? 'user';
    final String noticeText;
    final IconData noticeIcon;
    final Color noticeColor;

    switch (reason) {
      case 'idle':
        noticeText = strings.sideClosedNoticeIdle;
        noticeIcon = Icons.timer_outlined;
        noticeColor = tokens.textSecondary;
        break;
      case 'parentClosed':
        noticeText = strings.sideClosedNoticeParentClosed;
        noticeIcon = Icons.cancel_outlined;
        noticeColor = tokens.textMuted;
        break;
      case 'error':
        noticeText = strings.sideClosedNoticeError;
        noticeIcon = Icons.error_outlined;
        noticeColor = tokens.danger;
        break;
      case 'user':
      default:
        noticeText = strings.sideClosedNoticeUser;
        noticeIcon = Icons.info_outlined;
        noticeColor = tokens.syntaxFunction;
        break;
    }

    return Container(
      key: const ValueKey('side-closed-notice'),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: FrameSpace.x2),
      decoration: BoxDecoration(
        color: noticeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: noticeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(noticeIcon, size: FrameSize.icon, color: noticeColor),
          const SizedBox(width: FrameSpace.x2),
          Expanded(
            child: Text(noticeText, style: FrameText.of(context).label.copyWith(color: tokens.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscript(
    FrameTokens tokens,
    AppStrings strings,
    SideThreadState sideThread,
    SessionState sideSession,
    bool isStreaming,
    SideConversationRecord? selectedRecord,
    bool isLive,
  ) {
    final entries = isLive ? sideSession.entries : (selectedRecord?.entries ?? const []);
    final streamingThinking = isLive ? sideSession.currentStreamingThinking : '';
    final streamingText = isLive ? sideSession.currentStreamingText : '';
    final activeTools = isLive ? sideSession.activeToolCalls.values.toList() : const [];
    final isOpening = isLive && sideThread.isOpening;

    if (entries.isEmpty && streamingThinking.isEmpty && streamingText.isEmpty && activeTools.isEmpty && !isOpening) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 36, color: tokens.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: FrameSpace.x2),
              Text(
                strings.sideConversationTitle,
                style: FrameText.of(context).body.copyWith(color: tokens.textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: FrameSpace.x1),
              Text(
                strings.sideNotPartOfMain,
                style: FrameText.of(context).caption.copyWith(color: tokens.textMuted.withValues(alpha: 0.7)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: FrameSpace.x2),
      children: [
        for (final entry in entries) ...[
          if (entry.role == 'user')
            _buildUserMessage(tokens, entry)
          else if (entry.role == 'assistant')
            _buildAssistantMessage(tokens, strings, entry, sideSession.cwd),
        ],

        // Live streaming content
        if (streamingThinking.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FrameSpace.x2),
            child: ThinkingBlock(thinkingText: streamingThinking, isStreaming: true),
          ),

        for (final tool in activeTools)
          Padding(
            padding: const EdgeInsets.only(bottom: FrameSpace.x2),
            child: ToolCard(tool: tool),
          ),

        if (streamingText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FrameSpace.x2),
            child: RichContent(text: streamingText, cwd: sideSession.cwd),
          ),

        if (sideThread.isOpening)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FrameSpace.x4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: FrameActivityIndicator(size: 14, strokeWidth: 2, color: tokens.syntaxFunction),
                ),
                const SizedBox(width: FrameSpace.x2),
                Text(strings.sideOpening, style: FrameText.of(context).label.copyWith(color: tokens.textMuted)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildUserMessage(FrameTokens tokens, SessionEntry entry) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: FrameSpace.x8),
        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: FrameSpace.x2),
        decoration: BoxDecoration(
          color: tokens.chassis,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(color: tokens.border),
        ),
        child: Text(entry.text, style: FrameText.of(context).body.copyWith(color: tokens.textPrimary, height: 1.4)),
      ),
    );
  }

  Widget _buildAssistantMessage(FrameTokens tokens, AppStrings strings, SessionEntry entry, String cwd) {
    return Container(
      margin: const EdgeInsets.only(bottom: FrameSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entry.thinking != null && entry.thinking!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ThinkingBlock(thinkingText: entry.thinking!, isStreaming: false),
            ),

          for (final tool in entry.toolCalls)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ToolCard(tool: tool),
            ),

          if (entry.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: FrameSpace.x2),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: RichContent(text: entry.text, cwd: cwd),
            ),

          // Insert into composer action
          if (entry.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FrameSpace.x1, bottom: FrameSpace.x1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('side-insert-into-composer-${entry.id}'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: tokens.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      side: BorderSide(color: tokens.border),
                    ),
                  ),
                  icon: Icon(Icons.input_outlined, size: 13, color: tokens.accent),
                  label: Text(
                    strings.sideInsertIntoComposer,
                    style: FrameText.of(context).caption.copyWith(color: tokens.accent, fontWeight: FontWeight.w500),
                  ),
                  onPressed: () {
                    appendComposerContext(ref, widget.sessionId, entry.text);
                    FrameSnackBar.show(context, message: strings.sideInsertedIntoComposer);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniComposer(FrameTokens tokens, AppStrings strings, ComposerSettings settings, bool isStreaming) {
    final sendWithEnter = settings.sendWithEnter;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final isEnter =
              event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;

          if (!isEnter) return KeyEventResult.ignored;

          final isShift = HardwareKeyboard.instance.isShiftPressed;
          final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

          if (sendWithEnter) {
            if (!isShift && !isCtrlOrCmd) {
              _send();
              return KeyEventResult.handled;
            }
          } else {
            if (isCtrlOrCmd) {
              _send();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: TextField(
                  key: const ValueKey('side-mini-composer-input'),
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  style: FrameText.of(context).body.copyWith(color: tokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: strings.sideMiniComposerHint,
                    hintStyle: FrameText.of(context).label.copyWith(color: tokens.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (isStreaming)
              IconButton.filled(
                key: const ValueKey('side-mini-abort-button'),
                style: IconButton.styleFrom(backgroundColor: tokens.danger, foregroundColor: tokens.textPrimary),
                tooltip: strings.sideStopTooltip,
                icon: const Icon(Icons.stop_outlined, size: FrameSize.icon),
                onPressed: () => ref.read(sideThreadFamily(widget.sessionId).notifier).abort(),
              )
            else
              IconButton.filled(
                key: const ValueKey('side-mini-composer-send'),
                style: IconButton.styleFrom(backgroundColor: tokens.accent, foregroundColor: tokens.textPrimary),
                tooltip: strings.sideSendTooltip(sendWithEnter: sendWithEnter),
                icon: const Icon(Icons.send_outlined, size: FrameSize.icon),
                onPressed: _send,
              ),
          ],
        ),
      ),
    );
  }
}
