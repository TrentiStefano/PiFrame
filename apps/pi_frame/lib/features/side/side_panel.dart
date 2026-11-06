import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/composer/composer_settings.dart';
import '../../data/language/language_settings.dart';
import '../../domain/session/session_state.dart';
import '../../ui/frame_snack_bar.dart';
import '../composer/composer_draft.dart';
import '../tool_timeline/tool_card.dart';
import '../transcript/rich_content.dart';
import '../transcript/thinking_block.dart';
import 'side_provider.dart';

class SidePanel extends ConsumerStatefulWidget {
  final String sessionId;

  const SidePanel({
    super.key,
    required this.sessionId,
  });

  @override
  ConsumerState<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends ConsumerState<SidePanel> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
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

  Future<void> _confirmClose(BuildContext context) async {
    final strings = ref.read(appStringsProvider);
    final tokens = context.tokens;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: tokens.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.borderStrong),
        ),
        title: Text(
          strings.sideCloseConfirmTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          strings.sideCloseConfirmContent,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              strings.cancel,
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            key: const ValueKey('side-confirm-close-btn'),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.textPrimary,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.close),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sideThreadFamily(widget.sessionId).notifier).close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sideThread = ref.watch(sideThreadFamily(widget.sessionId));
    if (!sideThread.isOpen) {
      return const SizedBox.shrink();
    }

    final sideSession = ref.watch(sideSessionFamily(widget.sessionId));
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final composerSettings = ref.watch(composerSettingsProvider);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final panelWidth = isMobile ? screenWidth : 420.0;

    final isStreaming = sideSession.isStreaming || sideThread.isOpening;

    // Listen to changes in entries or streaming text to scroll down
    ref.listen(sideSessionFamily(widget.sessionId), (_, next) {
      if (next.entries.isNotEmpty || next.isStreaming) {
        _scrollToBottom();
      }
    });

    return Container(
      key: const ValueKey('side-panel-container'),
      width: panelWidth,
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        border: Border(
          left: BorderSide(color: tokens.borderStrong, width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.overlay.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(-3, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(tokens, strings, sideThread, isStreaming),

          // Notice banner if side.closed
          if (sideThread.closeReason != null || sideThread.isClosed)
            _buildClosedNotice(tokens, strings, sideThread),

          // Transcript
          Expanded(
            child: _buildTranscript(
              tokens,
              strings,
              sideThread,
              sideSession,
              isStreaming,
            ),
          ),

          // Mini Composer
          _buildMiniComposer(
            tokens,
            strings,
            composerSettings,
            isStreaming,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    FrameTokens tokens,
    AppStrings strings,
    SideThreadState sideThread,
    bool isStreaming,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          bottom: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Badge 'Side · read-only'
              Container(
                key: const ValueKey('side-read-only-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.syntaxFunction.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(
                    color: tokens.syntaxFunction.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.call_split,
                      size: 13,
                      color: tokens.syntaxFunction,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      strings.sideReadOnlyBadge,
                      style: TextStyle(
                        color: tokens.syntaxFunction,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                  ],
                ),
              ),

              // Model chip
              if (sideThread.model != null && sideThread.model!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      sideThread.model!,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 10,
                        fontFamily: tokens.monoFontFamily,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Stop button if streaming
              if (isStreaming)
                IconButton(
                  key: const ValueKey('side-abort-btn'),
                  visualDensity: VisualDensity.compact,
                  tooltip: strings.sideStopTooltip,
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    size: 18,
                    color: tokens.danger,
                  ),
                  onPressed: () => ref
                      .read(sideThreadFamily(widget.sessionId).notifier)
                      .abort(),
                ),

              // Close button
              IconButton(
                key: const ValueKey('side-close-btn'),
                visualDensity: VisualDensity.compact,
                tooltip: strings.sideCloseTooltip,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: tokens.textSecondary,
                ),
                onPressed: () => _confirmClose(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            strings.sideNotPartOfMain,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosedNotice(
    FrameTokens tokens,
    AppStrings strings,
    SideThreadState sideThread,
  ) {
    final reason = sideThread.closeReason ?? 'user';
    final String noticeText;
    final IconData noticeIcon;
    final Color noticeColor;

    switch (reason) {
      case 'idle':
        noticeText = strings.sideClosedNoticeIdle;
        noticeIcon = Icons.timer_outlined;
        noticeColor = tokens.warning;
        break;
      case 'parentClosed':
        noticeText = strings.sideClosedNoticeParentClosed;
        noticeIcon = Icons.cancel_outlined;
        noticeColor = tokens.textMuted;
        break;
      case 'error':
        noticeText = strings.sideClosedNoticeError;
        noticeIcon = Icons.error_outline;
        noticeColor = tokens.danger;
        break;
      case 'user':
      default:
        noticeText = strings.sideClosedNoticeUser;
        noticeIcon = Icons.info_outline;
        noticeColor = tokens.syntaxFunction;
        break;
    }

    return Container(
      key: const ValueKey('side-closed-notice'),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: noticeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: noticeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(noticeIcon, size: 16, color: noticeColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              noticeText,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 12,
              ),
            ),
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
  ) {
    final entries = sideSession.entries;
    final streamingThinking = sideSession.currentStreamingThinking;
    final streamingText = sideSession.currentStreamingText;
    final activeTools = sideSession.activeToolCalls.values.toList();

    if (entries.isEmpty &&
        streamingThinking.isEmpty &&
        streamingText.isEmpty &&
        activeTools.isEmpty &&
        !sideThread.isOpening) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 36,
                color: tokens.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                strings.sideConversationTitle,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.sideNotPartOfMain,
                style: TextStyle(
                  color: tokens.textMuted.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            padding: const EdgeInsets.only(bottom: 8),
            child: ThinkingBlock(
              thinkingText: streamingThinking,
              isStreaming: true,
            ),
          ),

        for (final tool in activeTools)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ToolCard(tool: tool),
          ),

        if (streamingText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RichContent(
              text: streamingText,
              cwd: sideSession.cwd,
            ),
          ),

        if (sideThread.isOpening)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(tokens.syntaxFunction),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  strings.sideOpening,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 12,
                  ),
                ),
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
        margin: const EdgeInsets.only(bottom: 10, left: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.chassis,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          entry.text,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(
    FrameTokens tokens,
    AppStrings strings,
    SessionEntry entry,
    String cwd,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entry.thinking != null && entry.thinking!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ThinkingBlock(
                thinkingText: entry.thinking!,
                isStreaming: false,
              ),
            ),

          for (final tool in entry.toolCalls)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ToolCard(tool: tool),
            ),

          if (entry.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('side-insert-into-composer-${entry.id}'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: tokens.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      side: BorderSide(color: tokens.border),
                    ),
                  ),
                  icon: Icon(
                    Icons.input_outlined,
                    size: 13,
                    color: tokens.accent,
                  ),
                  label: Text(
                    strings.sideInsertIntoComposer,
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    appendComposerContext(ref, widget.sessionId, entry.text);
                    FrameSnackBar.show(
                      context,
                      message: strings.sideInsertedIntoComposer,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniComposer(
    FrameTokens tokens,
    AppStrings strings,
    ComposerSettings settings,
    bool isStreaming,
  ) {
    final sendWithEnter = settings.sendWithEnter;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          top: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter;

          if (!isEnter) return KeyEventResult.ignored;

          final isShift = HardwareKeyboard.instance.isShiftPressed;
          final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

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
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: strings.sideMiniComposerHint,
                    hintStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
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
                style: IconButton.styleFrom(
                  backgroundColor: tokens.danger,
                  foregroundColor: tokens.textPrimary,
                ),
                tooltip: strings.sideStopTooltip,
                icon: const Icon(Icons.stop, size: 16),
                onPressed: () => ref
                    .read(sideThreadFamily(widget.sessionId).notifier)
                    .abort(),
              )
            else
              IconButton.filled(
                key: const ValueKey('side-mini-composer-send'),
                style: IconButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.textPrimary,
                ),
                tooltip: sendWithEnter ? 'Invia (Invio)' : 'Invia (Ctrl+Invio)',
                icon: const Icon(Icons.send_rounded, size: 16),
                onPressed: _send,
              ),
          ],
        ),
      ),
    );
  }
}
