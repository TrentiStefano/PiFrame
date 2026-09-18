import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../status/agent_status_badge.dart';
import '../tool_timeline/tool_timeline.dart';
import '../dialogs/extension_ui_dialog.dart';
import 'rich_content.dart';
import 'thinking_block.dart';

class TranscriptView extends ConsumerStatefulWidget {
  final String sessionId;

  const TranscriptView({super.key, required this.sessionId});

  @override
  ConsumerState<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends ConsumerState<TranscriptView> {
  final ScrollController _scrollController = ScrollController();
  bool _userScrolledUp = false;
  String? _lastHandledUiRequestId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final isNearBottom = (maxScroll - currentScroll) < 80;

    if (_userScrolledUp == isNearBottom) {
      setState(() {
        _userScrolledUp = !isNearBottom;
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(maxScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkPendingUiRequests(List<Map<String, dynamic>> requests) {
    if (requests.isEmpty) return;
    final req = requests.last;
    final reqId = req['requestId']?.toString();
    if (reqId != null && reqId != _lastHandledUiRequestId) {
      _lastHandledUiRequestId = reqId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (req['dialog'] == true) {
          ExtensionUiDialog.show(
            context,
            sessionId: widget.sessionId,
            request: req,
          );
        } else if (req['method'] == 'notify') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(req['message']?.toString() ?? 'Notifica'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));

    // Auto check pending extension UI requests
    _checkPendingUiRequests(sessionState.pendingUiRequests);

    // Auto-scroll on stream if user is near bottom
    if (!_userScrolledUp && sessionState.isStreaming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animate: false);
      });
    }

    final hasActiveTools = sessionState.activeToolCalls.isNotEmpty;
    final liveThinking = sessionState.currentStreamingThinking;
    final liveText = sessionState.currentStreamingText;
    final showLiveStream = sessionState.isStreaming ||
        liveText.isNotEmpty ||
        liveThinking.isNotEmpty ||
        hasActiveTools;

    return Stack(
      children: [
        Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sessionState.sessionName ?? widget.sessionId,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sessionState.cwd.isNotEmpty ? sessionState.cwd : 'Nessuna cartella aperta',
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                  AgentStatusBadge(status: sessionState.agentStatus),
                ],
              ),
            ),

            // Transcript Entries List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: sessionState.entries.length + (showLiveStream ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < sessionState.entries.length) {
                    final entry = sessionState.entries[index];
                    return _buildEntryItem(entry, tokens);
                  }

                  // Active Streaming Block
                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (liveThinking.isNotEmpty ||
                            sessionState.agentStatus == AgentStatus.working)
                          ThinkingBlock(
                            thinkingText: liveThinking,
                            isStreaming: sessionState.isStreaming,
                          ),
                        if (hasActiveTools)
                          ToolTimeline(
                            toolCalls: sessionState.activeToolCalls.values.toList(),
                          ),
                        if (liveText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: tokens.surfaceElevated,
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                              border: Border.all(
                                color: tokens.agentWorking.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: RichContent(text: liveText),
                          )
                        else if (sessionState.agentStatus == AgentStatus.working &&
                            liveThinking.isEmpty &&
                            !hasActiveTools)
                          Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: tokens.agentWorking,
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Elaborazione in corso...',
                                style: TextStyle(
                                  color: tokens.agentWorking,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // Floating Scroll-to-bottom Button
        if (_userScrolledUp)
          Positioned(
            right: 24,
            bottom: 24,
            child: FloatingActionButton.small(
              backgroundColor: tokens.surfaceElevated,
              foregroundColor: tokens.accent,
              onPressed: () => _scrollToBottom(animate: true),
              child: const Icon(Icons.arrow_downward, size: 18),
            ),
          ),
      ],
    );
  }

  Widget _buildEntryItem(SessionEntry entry, CrustTokens tokens) {
    final isUser = entry.role == 'user';

    if (isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.userBubble,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline, size: 13, color: tokens.accent),
                  const SizedBox(width: 4),
                  Text(
                    'Tu',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              RichContent(text: entry.text),
            ],
          ),
        ),
      );
    }

    // Assistant entry
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thinking block if present
          if (entry.thinking != null && entry.thinking!.isNotEmpty)
            ThinkingBlock(thinkingText: entry.thinking!),

          // Tool calls timeline if present
          if (entry.toolCalls.isNotEmpty)
            ToolTimeline(toolCalls: entry.toolCalls),

          // Message content
          if (entry.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 13, color: tokens.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Assistente',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: entry.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Messaggio copiato negli appunti'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Icon(Icons.copy, size: 13, color: tokens.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RichContent(text: entry.text),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
