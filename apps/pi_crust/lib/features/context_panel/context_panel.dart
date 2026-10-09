import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../session_tree/session_tree_dialog.dart';
import '../workspace/repository_workspace.dart';

class ContextPanel extends ConsumerStatefulWidget {
  final String sessionId;

  const ContextPanel({super.key, required this.sessionId});

  @override
  ConsumerState<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends ConsumerState<ContextPanel> {
  List<Map<String, dynamic>> _models = [];
  List<String> _thinkingLevels = [];
  bool _isLoadingParams = true;
  bool _isCompacting = false;

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  Future<void> _loadParams() async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final models = await notifier.getAvailableModels();
    final levels = await notifier.getAvailableThinkingLevels();

    if (mounted) {
      setState(() {
        _models = models;
        _thinkingLevels = levels.isNotEmpty
            ? levels
            : ['off', 'low', 'medium', 'high'];
        _isLoadingParams = false;
      });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
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

  Future<void> _triggerCompaction() async {
    if (_isCompacting) return;
    setState(() => _isCompacting = true);

    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    Map<String, dynamic>? res;
    try {
      final result = await notifier.compact();
      res = result?['data'] as Map<String, dynamic>?;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compattazione non riuscita: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompacting = false);
    }

    if (mounted && res != null) {
      final tokensBefore = res['tokensBefore'] ?? '?';
      final tokensAfter =
          res['estimatedTokensAfter'] ?? res['tokensAfter'] ?? '?';
      final usage = res['usage'] as Map?;
      final cost = usage?['cost'] is Map ? '\$${usage!['cost']['total']}' : '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.tokens.surface,
          title: Text(
            'Compattazione completata',
            style: TextStyle(color: context.tokens.textPrimary),
          ),
          content: Text(
            'Token prima: $tokensBefore\nToken dopo: $tokensAfter\n${cost.isNotEmpty ? "Costo: $cost" : ""}',
            style: TextStyle(color: context.tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: context.tokens.textPrimary),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cloneSession() async {
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
      final result = await client.cloneSession(widget.sessionId);
      if (!mounted) return;
      final data = result['data'] as Map<String, dynamic>;
      if (!await switchSessionSafely(context, ref, data['sessionId'] as String))
        return;
      ref.invalidate(sessionListProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicazione non riuscita: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );

    final currentModelName =
        sessionState.currentModel ??
        (_models.isNotEmpty
            ? (_models.first['name'] ?? _models.first['id'])
            : 'Default');
    final currentThinking = sessionState.currentThinkingLevel ?? 'medium';

    final usage = sessionState.usage;
    final tokensMap = usage?['tokens'] as Map<String, dynamic>?;
    final totalTokens = (tokensMap?['total'] as num?)?.toInt() ?? 0;
    final contextUsage = usage?['contextUsage'] as Map<String, dynamic>?;
    final percent = (contextUsage?['percent'] as num?)?.toDouble();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: tokens.chassis,
        border: Border(left: BorderSide(color: tokens.borderStrong, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: tokens.displaySurface,
              border: Border(bottom: BorderSide(color: tokens.borderStrong)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sessione',
                    style: TextStyle(
                      color: tokens.displayText,
                      fontSize: 24,
                      height: 1,
                      fontFamily: tokens.headingFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Session settings; repository and Git status live in Git Changes.
                // 1. Modello Attivo
                Text(
                  'Modello LLM',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _isLoadingParams
                    ? SizedBox(
                        height: 36,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        ),
                      )
                    : _models.isEmpty
                    ? Text(
                        sessionState.currentModel == null
                            ? 'Nessun modello abilitato in Pi.'
                            : '${sessionState.currentModel}\nElenco modelli non disponibile.',
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border, width: 1),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMd,
                            ),
                            dropdownColor: tokens.surfaceElevated,
                            value:
                                _models.any(
                                  (m) =>
                                      m['name'] == currentModelName ||
                                      m['id'] == currentModelName,
                                )
                                ? currentModelName
                                : (_models.isNotEmpty
                                      ? (_models.first['name'] ??
                                            _models.first['id'])
                                      : null),
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 13,
                              fontFamily: tokens.uiFontFamily,
                            ),
                            items: _models.map((m) {
                              final name =
                                  m['name'] as String? ?? m['id'] as String;
                              return DropdownMenuItem<String>(
                                value: name,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: sessionState.readOnly
                                ? null
                                : (newModel) {
                                    if (newModel != null) {
                                      final modelObj = _models.firstWhere(
                                        (m) =>
                                            (m['name'] ?? m['id'])
                                                ?.toString() ==
                                            newModel,
                                        orElse: () => {
                                          'provider': '',
                                          'id': newModel,
                                        },
                                      );
                                      final provider =
                                          modelObj['provider']?.toString() ??
                                          '';
                                      final modelId =
                                          modelObj['id']?.toString() ??
                                          newModel;
                                      _runAction(
                                        () => sessionNotifier.setModel(
                                          provider,
                                          modelId,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ),
                const SizedBox(height: 16),

                // 3. Livello Reasoning / Thinking
                Text(
                  'Livello Thinking',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border, width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      dropdownColor: tokens.surfaceElevated,
                      value: _thinkingLevels.contains(currentThinking)
                          ? currentThinking
                          : (_thinkingLevels.isNotEmpty
                                ? _thinkingLevels.first
                                : 'off'),
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 13,
                        fontFamily: tokens.uiFontFamily,
                      ),
                      items: _thinkingLevels.map((lvl) {
                        return DropdownMenuItem<String>(
                          value: lvl,
                          child: Text(lvl.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: sessionState.readOnly
                          ? null
                          : (newLevel) {
                              if (newLevel != null) {
                                _runAction(
                                  () => sessionNotifier.setThinkingLevel(
                                    newLevel,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Finestra di Contesto
                Text(
                  'Utilizzo Contesto',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (percent != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: LinearProgressIndicator(
                      value: (percent / 100.0).clamp(0.0, 1.0),
                      backgroundColor: tokens.background,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent > 80
                            ? tokens.danger
                            : (percent > 60 ? tokens.warning : tokens.success),
                      ),
                      minHeight: 8,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      usage == null
                          ? 'Dati non disponibili'
                          : '$totalTokens token',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    if (percent != null)
                      Text(
                        '${percent.toStringAsFixed(1)} %',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // 5. Actions (Compaction, Duplicate Branch)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.surfaceElevated,
                    foregroundColor: tokens.textPrimary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  icon: _isCompacting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        )
                      : Icon(Icons.compress, size: 16, color: tokens.accent),
                  label: Text(
                    _isCompacting ? 'Compattazione...' : 'Compatta contesto',
                  ),
                  onPressed: _isCompacting || sessionState.readOnly
                      ? null
                      : _triggerCompaction,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  icon: Icon(
                    Icons.content_copy,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                  label: const Text('Duplica Ramo (Clone)'),
                  onPressed: _cloneSession,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  icon: Icon(
                    Icons.account_tree_outlined,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                  label: const Text('Albero dei Rami (Tree)'),
                  onPressed: () => SessionTreeDialog.show(
                    context,
                    sessionId: widget.sessionId,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
