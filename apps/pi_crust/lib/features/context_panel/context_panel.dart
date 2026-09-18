import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';

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
        _thinkingLevels = levels.isNotEmpty ? levels : ['off', 'low', 'medium', 'high'];
        _isLoadingParams = false;
      });
    }
  }

  Future<void> _triggerCompaction() async {
    if (_isCompacting) return;
    setState(() {
      _isCompacting = true;
    });

    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final res = await notifier.compact();

    setState(() {
      _isCompacting = false;
    });

    if (mounted && res != null) {
      final tokensBefore = res['tokensBefore'] ?? '?';
      final tokensAfter = res['tokensAfter'] ?? '?';
      final cost = res['cost'] != null ? '\$${res['cost']}' : '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Compattazione completata'),
          content: Text(
            'Token prima: $tokensBefore\nToken dopo: $tokensAfter\n${cost.isNotEmpty ? "Costo: $cost" : ""}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);

    final currentModelName = sessionState.currentModel ?? (_models.isNotEmpty ? (_models.first['name'] ?? _models.first['id']) : 'Default');
    final currentThinking = sessionState.currentThinkingLevel ?? 'medium';

    // Calculate context usage
    final usage = sessionState.usage;
    final tokensMap = usage?['tokens'] as Map<String, dynamic>?;
    final totalTokens = (tokensMap?['total'] as num?)?.toInt() ?? 0;
    final contextUsage = usage?['contextUsage'] as Map<String, dynamic>?;
    final percent = (contextUsage?['percent'] as num?)?.toDouble();

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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.tune, size: 18, color: tokens.accent),
                const SizedBox(width: 8),
                Text(
                  'Parametri Sessione',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),

          Expanded(
            child: _isLoadingParams
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 1. Model Selector
                      Text(
                        'Modello LLM',
                        style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: tokens.background,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _models.any((m) => (m['name'] ?? m['id']) == currentModelName) ? currentModelName : null,
                      hint: Text(currentModelName, style: TextStyle(color: tokens.textPrimary, fontSize: 13)),
                      isExpanded: true,
                      dropdownColor: tokens.surfaceElevated,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                      items: _models.map((m) {
                        final name = (m['name'] ?? m['id']).toString();
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (selectedName) {
                        if (selectedName == null) return;
                        final found = _models.firstWhere(
                          (m) => (m['name'] ?? m['id']) == selectedName,
                          orElse: () => {},
                        );
                        if (found.isNotEmpty) {
                          sessionNotifier.setModel(found['provider'] ?? '', found['id'] ?? '');
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Thinking Level Selector
                Text(
                  'Livello di Thinking (Reasoning)',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: tokens.background,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _thinkingLevels.contains(currentThinking) ? currentThinking : null,
                      hint: Text(currentThinking, style: TextStyle(color: tokens.textPrimary, fontSize: 13)),
                      isExpanded: true,
                      dropdownColor: tokens.surfaceElevated,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                      items: _thinkingLevels.map((lvl) {
                        return DropdownMenuItem<String>(
                          value: lvl,
                          child: Text(lvl.toUpperCase(), style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          sessionNotifier.setThinkingLevel(val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Context Usage Bar
                Text(
                  'Uso della Context Window',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (percent == null && totalTokens == 0)
                  Text(
                    'In attesa di primo prompt...',
                    style: TextStyle(color: tokens.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                  )
                else ...[
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
                ],
                const SizedBox(height: 20),

                // 4. Compaction Action
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
