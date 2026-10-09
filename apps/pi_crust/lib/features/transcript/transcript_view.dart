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
import '../workspace/repository_workspace.dart';
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
  List<SessionEntry>? _renderedEntries;
  CrustTokens? _renderedTokens;
  List<Widget> _historyWidgets = const [];

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
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : context.tokens.panelDuration,
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

  String _formatTokens(Object? value) {
    if (value is! num) return '—';
    final count = value.toInt();
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 10000) return '${(count / 1000).round()}k';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  Widget _metricChip(CrustTokens tokens, String label, String value) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label · ',
                style: TextStyle(color: tokens.textMuted),
              ),
              TextSpan(
                text: value,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final stats = sessionState.sessionStats;
    final contextUsage =
        stats?['contextUsage'] as Map? ??
        sessionState.usage?['contextUsage'] as Map?;
    final contextPercent = contextUsage?['percent'] as num?;
    final contextWindow = contextUsage?['contextWindow'];
    final contextLabel = contextUsage == null
        ? 'non disponibile'
        : contextPercent == null
        ? 'post-compattazione · —/${_formatTokens(contextWindow)}'
        : '${contextPercent.toStringAsFixed(1)}% · ${_formatTokens(contextUsage['tokens'])}/${_formatTokens(contextWindow)}';
    final cost = stats?['cost'] as num?;
    final extensionStatuses = sessionState.extensionStatuses.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Stream ticks rebuild only the live region; immutable history widgets are reused.
    if (!identical(_renderedEntries, sessionState.entries) ||
        !identical(_renderedTokens, tokens)) {
      _renderedEntries = sessionState.entries;
      _renderedTokens = tokens;
      _historyWidgets = [
        for (final entry in sessionState.entries)
          RepaintBoundary(
            key: ValueKey(entry.id),
            child: _buildEntryItem(entry, tokens),
          ),
      ];
    }

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
    final showLiveStream =
        sessionState.isStreaming ||
        liveText.isNotEmpty ||
        liveThinking.isNotEmpty ||
        hasActiveTools;

    return Stack(
      children: [
        Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              decoration: BoxDecoration(
                color: tokens.displaySurface,
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sessionState.sessionName ?? widget.sessionId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.displayText,
                                fontFamily: tokens.headingFontFamily,
                                fontSize: 28,
                                height: 1.05,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sessionState.cwd.isNotEmpty
                                  ? sessionState.cwd
                                  : 'Nessuna cartella aperta',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.displayText.withValues(
                                  alpha: 0.75,
                                ),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AgentStatusBadge(
                        status: sessionState.agentStatus,
                        onDisplay: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _metricChip(
                        tokens,
                        'Modello',
                        sessionState.currentModel ?? '—',
                      ),
                      _metricChip(
                        tokens,
                        'Thinking',
                        sessionState.currentThinkingLevel ?? '—',
                      ),
                      _metricChip(tokens, 'Contesto', contextLabel),
                      _metricChip(
                        tokens,
                        'Costo',
                        cost == null ? '—' : '\$${cost.toStringAsFixed(4)}',
                      ),
                      for (final status in extensionStatuses)
                        _metricChip(tokens, status.key, status.value),
                    ],
                  ),
                ],
              ),
            ),

            // Build only visible turns; long histories otherwise relayout in full on resize.
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                child: ListView(
                  key: const ValueKey('transcript-scroll'),
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  children: [
                    for (final entry in _historyWidgets)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: entry,
                        ),
                      ),
                    if (showLiveStream)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: _buildLiveStream(
                            sessionState,
                            tokens,
                            liveThinking,
                            liveText,
                            hasActiveTools,
                          ),
                        ),
                      ),
                  ],
                ),
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

  Widget _buildLiveStream(
    SessionState sessionState,
    CrustTokens tokens,
    String liveThinking,
    String liveText,
    bool hasActiveTools,
  ) {
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
                border: Border.all(color: tokens.borderStrong),
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
                    color: tokens.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _handleFork(String entryId) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    if (!await resolveDirtyRepository(
      context,
      ref,
      ref.read(activeSessionIdProvider),
    )) {
      return;
    }
    try {
      final res = await client.forkSession(widget.sessionId, entryId: entryId);
      if (!mounted || !context.mounted) return;
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (data['cancelled'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Fork annullato dall'extension"),
            backgroundColor: context.tokens.surfaceElevated,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      final newSid = data['sessionId'] as String? ?? data['id'] as String?;
      if (newSid != null) {
        if (!await switchSessionSafely(context, ref, newSid)) return;
        ref.invalidate(sessionListProvider);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nuovo ramo avviato: $newSid'),
            backgroundColor: context.tokens.surfaceElevated,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore fork: $e'),
          backgroundColor: context.tokens.danger,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildEntryItem(SessionEntry entry, CrustTokens tokens) {
    final isUser = entry.role == 'user';

    if (isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.userBubble,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
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
                      Icon(
                        Icons.person_outline,
                        size: 13,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tu',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _handleFork(entry.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_split,
                            size: 12,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Riparti da qui',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                border: Border.all(color: tokens.border),
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
                          Icon(
                            Icons.circle_outlined,
                            size: 14,
                            color: tokens.accent,
                          ),
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
                      IconButton(
                        tooltip: 'Copia messaggio',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: entry.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Messaggio copiato negli appunti'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.copy_outlined,
                          size: 16,
                          color: tokens.textMuted,
                        ),
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
