import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../ui/code/diff_block.dart';
import '../session_tree/session_tree_dialog.dart';

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
  Map<String, dynamic>? _gitStatus;
  bool _isLoadingGit = false;

  @override
  void initState() {
    super.initState();
    _loadParams();
    _loadGitStatus();
  }

  Future<void> _loadParams() async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final models = await notifier.getAvailableModels();
    final levels = await notifier.getAvailableThinkingLevels();

    if (mounted) {
      setState(() {
        _models = models;
        _thinkingLevels = levels.isNotEmpty ? levels : ['off', 'low', 'medium', 'high'];
        _isLoadingParams = false;
      });
    }
  }

  Future<void> _loadGitStatus() async {
    setState(() => _isLoadingGit = true);
    final client = ref.read(pcpClientProvider);
    if (client != null) {
      try {
        final res = await client.refreshWorkspace(widget.sessionId);
        if (mounted) {
          setState(() {
            _gitStatus = res;
            _isLoadingGit = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingGit = false);
      }
    } else {
      if (mounted) setState(() => _isLoadingGit = false);
    }
  }

  Future<void> _showFileDiff(String filePath) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    try {
      final res = await client.getWorkspaceDiff(widget.sessionId, filePath: filePath);
      final diffText = res['diff']?.toString() ?? 'Nessuna differenza trovata.';

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: context.tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.tokens.radiusMd),
              side: BorderSide(color: context.tokens.border, width: 1),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Diff: $filePath',
                        style: TextStyle(
                          color: context.tokens.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: context.tokens.monoFontFamily,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: context.tokens.textSecondary,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DiffBlock(
                        diffText: diffText,
                        filename: filePath,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _triggerCompaction() async {
    if (_isCompacting) return;
    setState(() => _isCompacting = true);

    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final res = await notifier.compact();

    setState(() => _isCompacting = false);

    if (mounted && res != null) {
      final tokensBefore = res['tokensBefore'] ?? '?';
      final tokensAfter = res['tokensAfter'] ?? '?';
      final cost = res['cost'] != null ? '\$${res['cost']}' : '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.tokens.surface,
          title: Text('Compattazione completata',
              style: TextStyle(color: context.tokens.textPrimary)),
          content: Text(
            'Token prima: $tokensBefore\nToken dopo: $tokensAfter\n${cost.isNotEmpty ? "Costo: $cost" : ""}',
            style: TextStyle(color: context.tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: TextStyle(color: context.tokens.accent)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cloneSession() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    await client.cloneSession(widget.sessionId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ramo duplicato con successo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);

    final currentModelName = sessionState.currentModel ??
        (_models.isNotEmpty ? (_models.first['name'] ?? _models.first['id']) : 'Default');
    final currentThinking = sessionState.currentThinkingLevel ?? 'medium';

    final usage = sessionState.usage;
    final tokensMap = usage?['tokens'] as Map<String, dynamic>?;
    final totalTokens = (tokensMap?['total'] as num?)?.toInt() ?? 0;
    final contextUsage = usage?['contextUsage'] as Map<String, dynamic>?;
    final percent = (contextUsage?['percent'] as num?)?.toDouble();

    final isGitRepo = _gitStatus?['isRepository'] == true;
    final branch = _gitStatus?['branch']?.toString() ?? 'main';
    final additions = _gitStatus?['totalAdditions'] as int? ?? 0;
    final deletions = _gitStatus?['totalDeletions'] as int? ?? 0;
    final changedFiles = (_gitStatus?['files'] as List<dynamic>?) ?? const [];

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Contesto & Git',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    size: 16,
                    color: _isLoadingGit ? tokens.accent : tokens.textSecondary,
                  ),
                  onPressed: _isLoadingGit ? null : _loadGitStatus,
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Git Repository Card
                if (isGitRepo) ...[
                  Row(
                    children: [
                      Icon(Icons.fork_right_outlined, size: 16, color: tokens.accent),
                      const SizedBox(width: 6),
                      Text(
                        branch,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (additions > 0)
                        Text(
                          '+$additions',
                          style: TextStyle(
                            color: tokens.diffAddedFg,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (additions > 0 && deletions > 0) const SizedBox(width: 4),
                      if (deletions > 0)
                        Text(
                          '-$deletions',
                          style: TextStyle(
                            color: tokens.diffRemovedFg,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Changed Files
                  Text(
                    'File Modificati (${changedFiles.length})',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (changedFiles.isEmpty)
                    Text(
                      'Nessun file modificato (clean)',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11.5),
                    )
                  else
                    ...changedFiles.map((f) {
                      final filePath = f['path']?.toString() ?? '';
                      final status = f['status']?.toString() ?? 'modified';
                      Color badgeColor = tokens.warning;
                      String badgeText = 'M';
                      if (status == 'added') {
                        badgeColor = tokens.diffAddedFg;
                        badgeText = 'A';
                      } else if (status == 'deleted') {
                        badgeColor = tokens.diffRemovedFg;
                        badgeText = 'D';
                      } else if (status == 'untracked') {
                        badgeColor = tokens.info;
                        badgeText = '?';
                      }

                      return InkWell(
                        onTap: () => _showFileDiff(filePath),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 10,
                                    fontFamily: tokens.monoFontFamily,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  filePath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 20),
                  Divider(color: tokens.border, height: 1),
                  const SizedBox(height: 16),
                ],

                // 2. Modello Attivo
                Text(
                  'Modello LLM',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                _isLoadingParams
                    ? SizedBox(height: 36, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent)))
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
                            dropdownColor: tokens.surfaceElevated,
                            value: _models.any((m) => m['name'] == currentModelName || m['id'] == currentModelName)
                                ? currentModelName
                                : (_models.isNotEmpty ? (_models.first['name'] ?? _models.first['id']) : null),
                            style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                            items: _models.map((m) {
                              final name = m['name'] as String? ?? m['id'] as String;
                              return DropdownMenuItem<String>(
                                value: name,
                                child: Text(name, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (newModel) {
                              if (newModel != null) {
                                final modelObj = _models.firstWhere(
                                  (m) => (m['name'] ?? m['id'])?.toString() == newModel,
                                  orElse: () => {'provider': '', 'id': newModel},
                                );
                                final provider = modelObj['provider']?.toString() ?? '';
                                final modelId = modelObj['id']?.toString() ?? newModel;
                                sessionNotifier.setModel(provider, modelId);
                              }
                            },
                          ),
                        ),
                      ),
                const SizedBox(height: 16),

                // 3. Livello Reasoning / Thinking
                Text(
                  'Livello Thinking',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
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
                      dropdownColor: tokens.surfaceElevated,
                      value: _thinkingLevels.contains(currentThinking)
                          ? currentThinking
                          : (_thinkingLevels.isNotEmpty ? _thinkingLevels.first : 'off'),
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                      items: _thinkingLevels.map((lvl) {
                        return DropdownMenuItem<String>(
                          value: lvl,
                          child: Text(lvl.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (newLevel) {
                        if (newLevel != null) {
                          sessionNotifier.setThinkingLevel(newLevel);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Finestra di Contesto
                Text(
                  'Utilizzo Contesto',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent != null ? (percent / 100.0).clamp(0.0, 1.0) : 0.05,
                    backgroundColor: tokens.background,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      (percent ?? 0) > 80 ? tokens.danger : ((percent ?? 0) > 60 ? tokens.warning : tokens.success),
                    ),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$totalTokens token',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    if (percent != null)
                      Text(
                        '${percent.toStringAsFixed(1)} %',
                        style: TextStyle(color: tokens.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
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
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm)),
                  ),
                  icon: _isCompacting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
                        )
                      : Icon(Icons.compress, size: 16, color: tokens.accent),
                  label: Text(_isCompacting ? 'Compattazione...' : 'Compatta contesto'),
                  onPressed: _isCompacting ? null : _triggerCompaction,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm)),
                  ),
                  icon: Icon(Icons.content_copy, size: 15, color: tokens.textSecondary),
                  label: const Text('Duplica Ramo (Clone)'),
                  onPressed: _cloneSession,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm)),
                  ),
                  icon: Icon(Icons.account_tree_outlined, size: 15, color: tokens.textSecondary),
                  label: const Text('Albero dei Rami (Tree)'),
                  onPressed: () => SessionTreeDialog.show(context, sessionId: widget.sessionId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
