import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../status/agent_status_badge.dart';
import '../tool_timeline/tool_timeline.dart';
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

  static const int _pageSize = 35;
  int _visibleCount = _pageSize;

  bool _initialScrollDone = false;

  bool _isRenaming = false;
  final TextEditingController _renameController = TextEditingController();
  final FocusNode _renameFocusNode = FocusNode();
  final Set<String> _expandedThinkingBlocks = <String>{};
  int _lastTotalEntries = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _isRenaming = false;
      _expandedThinkingBlocks.clear();
      _lastTotalEntries = 0;
      _visibleCount = _pageSize;
      _initialScrollDone = false;
      _userScrolledUp = false;
    }
  }

  void _startRenaming(String currentName) {
    setState(() {
      _isRenaming = true;
      _renameController.text = currentName;
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: currentName.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _renameFocusNode.canRequestFocus) {
        _renameFocusNode.requestFocus();
      }
    });
  }

  void _cancelRename() {
    if (!_isRenaming) return;
    setState(() {
      _isRenaming = false;
    });
  }

  Future<void> _submitRename() async {
    if (!_isRenaming) return;
    final newName = _renameController.text.trim();
    setState(() {
      _isRenaming = false;
    });
    if (newName.isEmpty) return;

    final currentState = ref.read(sessionStateFamily(widget.sessionId));
    if (newName == (currentState.sessionName ?? widget.sessionId)) return;

    try {
      final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
      await notifier.rename(newName);
      ref.invalidate(sessionListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante la rinomina: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_scrollController.hasClients) return false;

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        // User intentionally scrolled upward towards older messages
        if (!_userScrolledUp) {
          setState(() => _userScrolledUp = true);
        }
      } else if (notification.direction == ScrollDirection.reverse) {
        // User scrolled downward towards bottom
        final dist = _scrollController.position.maxScrollExtent -
            _scrollController.offset;
        if (dist < 40 && _userScrolledUp) {
          setState(() => _userScrolledUp = false);
        }
      }
    } else if (notification is ScrollUpdateNotification) {
      final dist = _scrollController.position.maxScrollExtent -
          _scrollController.offset;
      if (notification.dragDetails != null ||
          (notification.scrollDelta != null &&
              notification.scrollDelta!.abs() > 0)) {
        if (dist > 60 && !_userScrolledUp) {
          setState(() => _userScrolledUp = true);
        } else if (dist < 30 && _userScrolledUp) {
          setState(() => _userScrolledUp = false);
        }
      }
    }
    return false;
  }

  void _followStream() {
    if (!_scrollController.hasClients || _userScrolledUp) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    final delta = maxScroll - current;
    if (delta <= 1.0) return;

    _scrollController.jumpTo(maxScroll);
  }

  void _scrollToBottomFull() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent >
          _scrollController.offset) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          if (_scrollController.position.maxScrollExtent >
              _scrollController.offset) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
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
    _renameController.dispose();
    _renameFocusNode.dispose();
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
        if (req['method'] == 'notify') {
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

  String _cleanStatusValue(String raw) {
    var s = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
    s = s.replaceAll(RegExp(r'\x1B\([B0-9]'), '');
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.trim();

    if (s.startsWith('[') && s.endsWith(']')) {
      final inner = s.substring(1, s.length - 1).trim();
      final parts = inner.split(RegExp(r'[,;\s]+'));
      if (parts.isNotEmpty && parts.every((p) => int.tryParse(p) != null)) {
        try {
          final bytes = parts.map((p) => int.parse(p)).toList();
          if (bytes.every((b) => b >= 32 && b <= 126)) {
            return String.fromCharCodes(bytes).toUpperCase();
          }
        } catch (_) {}
      }
    }

    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }

    return s.isEmpty ? '—' : s.toUpperCase();
  }

  Widget _metricChip(
    CrustTokens tokens,
    String label,
    String value, {
    IconData? leadingIcon,
    Color? iconColor,
    Color? valueColor,
    void Function(BuildContext)? onTap,
    IconData? trailingIcon,
  }) {
    return Builder(
      builder: (chipContext) {
        final chip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: 12,
                  color: iconColor ?? tokens.textMuted,
                ),
                const SizedBox(width: 4),
              ],
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label · ',
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    ),
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: valueColor ?? tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 3),
                Icon(trailingIcon, size: 11, color: tokens.textMuted),
              ],
            ],
          ),
        );

        if (onTap == null) return chip;

        return InkWell(
          onTap: () => onTap(chipContext),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: chip,
        );
      },
    );
  }

  Future<void> _showModelPicker(BuildContext chipContext) async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final models = await notifier.getAvailableModels();
    if (!mounted || !chipContext.mounted) return;
    final tokens = context.tokens;
    final current = ref.read(sessionStateFamily(widget.sessionId)).currentModel;

    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun modello alternativo disponibile.'),
        ),
      );
      return;
    }

    final renderBox = chipContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = renderBox?.size ?? Size.zero;

    final selected = await showMenu<Map<String, dynamic>>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + 280,
        offset.dy + size.height + 400,
      ),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      items: models.map((m) {
        final id = m['id']?.toString() ?? '';
        final name = m['name']?.toString() ?? id;
        final isCurrent = id == current || name == current;
        return PopupMenuItem<Map<String, dynamic>>(
          value: m,
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 15,
                color: isCurrent ? tokens.accent : tokens.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isCurrent ? tokens.accent : tokens.textPrimary,
                        fontSize: 12,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (m['provider'] != null)
                      Text(
                        m['provider'].toString(),
                        style: TextStyle(color: tokens.textMuted, fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (isCurrent)
                Icon(Icons.check, size: 14, color: tokens.accent),
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
    final levels = await notifier.getAvailableThinkingLevels();
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
    final size = renderBox?.size ?? Size.zero;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + 200,
        offset.dy + size.height + 250,
      ),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      items: effectiveLevels.map((lvl) {
        final isCurrent = lvl.toLowerCase() == (current ?? '').toLowerCase();
        return PopupMenuItem<String>(
          value: lvl,
          height: 34,
          child: Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 15,
                color: isCurrent ? tokens.thinking : tokens.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lvl.toUpperCase(),
                  style: TextStyle(
                    color: isCurrent ? tokens.thinking : tokens.textPrimary,
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (isCurrent)
                Icon(Icons.check, size: 14, color: tokens.thinking),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      await notifier.setThinkingLevel(selected);
    }
  }

  Future<void> _showContextDialog(
    BuildContext chipContext,
    Map? contextUsage,
    Map? stats,
    num? cost,
  ) async {
    final tokens = context.tokens;
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        bool compacting = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final currentSession = ref.watch(
              sessionStateFamily(widget.sessionId),
            );
            final currentStats = currentSession.sessionStats;
            final currentUsage =
                currentStats?['contextUsage'] as Map? ??
                currentSession.usage?['contextUsage'] as Map?;
            final pct = (currentUsage?['percent'] as num?)?.toDouble() ?? 0.0;
            final tokensUsed =
                currentUsage?['tokens'] ??
                currentSession.usage?['totalTokens'] ??
                '—';
            final maxWindow = currentUsage?['contextWindow'] ?? '—';
            final inTokens =
                currentSession.usage?['inputTokens'] ??
                currentStats?['inputTokens'] ??
                '—';
            final outTokens =
                currentSession.usage?['outputTokens'] ??
                currentStats?['outputTokens'] ??
                '—';
            final cacheTokens =
                currentSession.usage?['cacheReadTokens'] ??
                currentStats?['cacheReadTokens'] ??
                '—';

            return Dialog(
              backgroundColor: tokens.surfaceElevated,
              alignment: const Alignment(0.0, -0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                side: BorderSide(color: tokens.borderStrong),
              ),
              child: SizedBox(
                width: 330,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.pie_chart_outline,
                                size: 16,
                                color: tokens.syntaxFunction,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Contesto & Token',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: tokens.textMuted,
                            ),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Utilizzo:',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(1)}% (${_formatTokens(tokensUsed)} / ${_formatTokens(maxWindow)})',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        child: LinearProgressIndicator(
                          value: (pct / 100.0).clamp(0.0, 1.0),
                          backgroundColor: tokens.surface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct > 85
                                ? tokens.danger
                                : pct > 65
                                ? tokens.warning
                                : tokens.syntaxFunction,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Divider(color: tokens.border, height: 1),
                      const SizedBox(height: 8),
                      _tokenRow('Token Input', inTokens.toString(), tokens),
                      _tokenRow('Token Output', outTokens.toString(), tokens),
                      _tokenRow('Token Cache', cacheTokens.toString(), tokens),
                      _tokenRow(
                        'Costo Stimato',
                        cost == null ? '—' : '\$${cost.toStringAsFixed(4)}',
                        tokens,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.accentContrast,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                          ),
                        ),
                        icon: compacting
                            ? SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.accentContrast,
                                ),
                              )
                            : const Icon(Icons.compress, size: 15),
                        label: Text(
                          compacting ? 'Compattazione...' : 'Compatta Contesto',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: compacting || currentSession.readOnly
                            ? null
                            : () async {
                                setDialogState(() => compacting = true);
                                try {
                                  await notifier.compact();
                                  if (mounted && ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Compattazione completata!',
                                        ),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted && ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Errore compattazione: $e',
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  setDialogState(() => compacting = false);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tokenRow(String label, String value, CrustTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: tokens.textMuted, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: tokens.textPrimary,
              fontFamily: tokens.monoFontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

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

    // Auto check pending extension UI requests
    _checkPendingUiRequests(sessionState.pendingUiRequests);

    final hasActiveTools = sessionState.activeToolCalls.isNotEmpty;
    final liveThinking = sessionState.currentStreamingThinking;
    final liveText = sessionState.currentStreamingText;
    final showLiveStream =
        sessionState.isStreaming ||
        liveText.isNotEmpty ||
        liveThinking.isNotEmpty ||
        hasActiveTools;

    // Auto-scroll fluidly with stream if user is near bottom
    if (!_userScrolledUp && showLiveStream) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _followStream();
      });
    }

    final isCompact = MediaQuery.sizeOf(context).width < 600;

    // Windowing / Pagination for long transcripts (excluding internal/junk messages)
    final cleanEntries = sessionState.entries.where((e) => !e.isJunkOrInternal).toList();
    final totalEntries = cleanEntries.length;

    // Keep visible messages in view if new messages arrive during active session
    if (_lastTotalEntries > 0 && totalEntries > _lastTotalEntries) {
      final added = totalEntries - _lastTotalEntries;
      _visibleCount = _visibleCount + added;
    }
    _lastTotalEntries = totalEntries;

    // Transition live thinking expansion to newly committed entry if stream finished
    if (!sessionState.isStreaming &&
        _expandedThinkingBlocks.contains('live_${widget.sessionId}')) {
      final lastAssistant = cleanEntries.reversed
          .where((e) => e.role == 'assistant' && e.thinking != null && e.thinking!.isNotEmpty)
          .firstOrNull;
      if (lastAssistant != null) {
        _expandedThinkingBlocks.remove('live_${widget.sessionId}');
        _expandedThinkingBlocks.add(lastAssistant.id);
      }
    }

    final hiddenCount = (totalEntries - _visibleCount).clamp(0, totalEntries);
    final visibleEntries = cleanEntries.sublist(hiddenCount);
    final hasLoadBanner = hiddenCount > 0;

    // Initial scroll to bottom when opening session or receiving first entries
    if (!_initialScrollDone && sessionState.entries.isNotEmpty) {
      _initialScrollDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomFull();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBentoHeader(
          sessionState,
          tokens,
          isCompact,
          contextLabel,
          contextUsage,
          stats,
          cost,
          extensionStatuses,
        ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  child: ListView.builder(
                    key: const ValueKey('transcript-scroll'),
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      top: 10,
                      bottom: isCompact ? 16 : 28,
                    ),
                    itemCount:
                        (hasLoadBanner ? 1 : 0) +
                        visibleEntries.length +
                        (showLiveStream ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasLoadBanner && index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                side: BorderSide(color: tokens.border),
                                foregroundColor: tokens.textSecondary,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(tokens.radiusSm),
                                ),
                              ),
                              icon: const Icon(Icons.history, size: 14),
                              label: Text(
                                'Carica messaggi precedenti ($hiddenCount non mostrati)',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                final oldMax =
                                    _scrollController.position.maxScrollExtent;
                                final oldOffset = _scrollController.offset;
                                setState(() {
                                  _visibleCount =
                                      (_visibleCount + _pageSize).clamp(
                                    0,
                                    totalEntries,
                                  );
                                });
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!_scrollController.hasClients) return;
                                  final newMax =
                                      _scrollController.position.maxScrollExtent;
                                  final diff = newMax - oldMax;
                                  if (diff > 0) {
                                    _scrollController.jumpTo(oldOffset + diff);
                                  }
                                });
                              },
                            ),
                          ),
                        );
                      }

                      final entryIndex = index - (hasLoadBanner ? 1 : 0);
                      if (entryIndex < visibleEntries.length) {
                        final entry = visibleEntries[entryIndex];
                        return Padding(
                          key: ValueKey('entry_row_${entry.id}'),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 24,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: RepaintBoundary(
                                key: ValueKey(entry.id),
                                child: _buildEntryItem(entry, tokens),
                              ),
                            ),
                          ),
                        );
                      }

                      return Padding(
                        key: const ValueKey('entry_row_livestream'),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 12 : 24,
                        ),
                        child: Center(
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
                      );
                    },
                  ),
                ),
              ),

              // Floating Scroll-to-bottom Button
              if (_userScrolledUp)
                Positioned(
                  right: 24,
                  bottom: 24,
                  child: FloatingActionButton.small(
                    backgroundColor: tokens.surfaceElevated,
                    foregroundColor: tokens.accent,
                    onPressed: () {
                      setState(() => _userScrolledUp = false);
                      _scrollToBottom(animate: true);
                    },
                    child: const Icon(Icons.arrow_downward, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBentoHeader(
    SessionState sessionState,
    CrustTokens tokens,
    bool isCompact,
    String contextLabel,
    Map? contextUsage,
    Map? stats,
    num? cost,
    List<MapEntry<String, dynamic>> extensionStatuses,
  ) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        isCompact ? 10 : 16,
        isCompact ? 8 : 10,
        isCompact ? 10 : 16,
        2,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderStrong),
        boxShadow: [
          BoxShadow(
            color: tokens.displaySurface.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isRenaming)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Focus(
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent) {
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.escape) {
                                      _cancelRename();
                                      return KeyEventResult.handled;
                                    }
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.numpadEnter) {
                                      _submitRename();
                                      return KeyEventResult.handled;
                                    }
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextField(
                                  key: const ValueKey(
                                    'session-name-rename-field',
                                  ),
                                  controller: _renameController,
                                  focusNode: _renameFocusNode,
                                  autofocus: true,
                                  maxLines: 1,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitRename(),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontFamily: tokens.headingFontFamily,
                                    fontSize: isCompact ? 15 : 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                    filled: true,
                                    fillColor: tokens.surfaceElevated,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxKeyword,
                                        width: 1.2,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxKeyword,
                                        width: 1.2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxKeyword,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const ValueKey(
                                'session-name-rename-submit',
                              ),
                              icon: Icon(
                                Icons.check,
                                size: 16,
                                color: tokens.syntaxFunction,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              tooltip: 'Salva',
                              onPressed: _submitRename,
                            ),
                            IconButton(
                              key: const ValueKey(
                                'session-name-rename-cancel',
                              ),
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: tokens.textMuted,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              tooltip: 'Annulla',
                              onPressed: _cancelRename,
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        key: const ValueKey('session-name-title'),
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () => _startRenaming(
                          sessionState.sessionName ?? widget.sessionId,
                        ),
                        child: Tooltip(
                          message: 'Doppio clic per rinominare',
                          waitDuration: const Duration(milliseconds: 400),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    sessionState.sessionName ?? widget.sessionId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontFamily: tokens.headingFontFamily,
                                      fontSize: isCompact ? 16 : 19,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.edit_outlined,
                                  size: isCompact ? 13 : 15,
                                  color: tokens.textMuted.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 12,
                          color: tokens.syntaxFunction,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            sessionState.cwd.isNotEmpty
                                ? sessionState.cwd
                                : 'Nessuna cartella aperta',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AgentStatusBadge(
                status: sessionState.agentStatus,
                onDisplay: false,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _metricChip(
                  tokens,
                  'Modello',
                  sessionState.currentModel ?? '—',
                  leadingIcon: Icons.psychology_outlined,
                  iconColor: tokens.accent,
                  valueColor: tokens.accent,
                  trailingIcon: Icons.arrow_drop_down,
                  onTap: (ctx) => _showModelPicker(ctx),
                ),
                const SizedBox(width: 6),
                _metricChip(
                  tokens,
                  'Thinking',
                  sessionState.currentThinkingLevel ?? '—',
                  leadingIcon: Icons.bolt_outlined,
                  iconColor: tokens.thinking,
                  valueColor: tokens.thinking,
                  trailingIcon: Icons.arrow_drop_down,
                  onTap: (ctx) => _showThinkingPicker(ctx),
                ),
                const SizedBox(width: 6),
                _metricChip(
                  tokens,
                  'Contesto',
                  contextLabel,
                  leadingIcon: Icons.pie_chart_outline,
                  iconColor: tokens.syntaxFunction,
                  trailingIcon: Icons.info_outline,
                  onTap: (ctx) => _showContextDialog(
                    ctx,
                    contextUsage,
                    stats,
                    cost,
                  ),
                ),
                const SizedBox(width: 6),
                _metricChip(
                  tokens,
                  'Costo',
                  cost == null ? '—' : '\$${cost.toStringAsFixed(4)}',
                  leadingIcon: Icons.monetization_on_outlined,
                  iconColor: tokens.syntaxString,
                  valueColor: tokens.syntaxString,
                ),
                for (final status in extensionStatuses) ...[
                  const SizedBox(width: 6),
                  _metricChip(
                    tokens,
                    status.key,
                    _cleanStatusValue(status.value),
                    leadingIcon: Icons.extension_outlined,
                    iconColor: tokens.syntaxKeyword,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
              key: ValueKey('thinking_live_${widget.sessionId}'),
              thinkingText: liveThinking,
              isStreaming: sessionState.isStreaming,
              isExpanded: _expandedThinkingBlocks
                  .contains('live_${widget.sessionId}'),
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedThinkingBlocks
                        .add('live_${widget.sessionId}');
                  } else {
                    _expandedThinkingBlocks
                        .remove('live_${widget.sessionId}');
                  }
                });
              },
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
    if (entry.isJunkOrInternal) return const SizedBox.shrink();
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
            border: Border.all(color: tokens.accent.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: tokens.accent.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(
                        color: tokens.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
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
                            color: tokens.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _handleFork(entry.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_split,
                            size: 12,
                            color: tokens.syntaxKeyword,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Riparti da qui',
                            style: TextStyle(
                              color: tokens.syntaxKeyword,
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
              const SizedBox(height: 8),
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
            ThinkingBlock(
              key: ValueKey('thinking_${entry.id}'),
              thinkingText: entry.thinking!,
              isExpanded: _expandedThinkingBlocks.contains(entry.id),
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedThinkingBlocks.add(entry.id);
                  } else {
                    _expandedThinkingBlocks.remove(entry.id);
                  }
                });
              },
            ),

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
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.syntaxFunction.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(
                            color:
                                tokens.syntaxFunction.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: tokens.syntaxFunction,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Assistente',
                              style: TextStyle(
                                color: tokens.syntaxFunction,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
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
