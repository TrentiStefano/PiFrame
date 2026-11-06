import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'subagents_provider.dart';
import 'workflows_provider.dart';

bool get _isTestBinding =>
    WidgetsBinding.instance.runtimeType.toString().contains('Test');

/// The Agents/Workflows column beside the chat card: a slim strip while
/// closed, the full [AgentActivityPanel] while open, nothing when the session
/// never delegated work.
class AgentActivitySidecar extends ConsumerWidget {
  final String sessionId;

  /// Called whenever the panel opens, so the shell can make room for it.
  final VoidCallback? onOpened;

  const AgentActivitySidecar({super.key, required this.sessionId, this.onOpened});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final agents = ref.watch(subagentsFamily(sessionId));
    final workflows = ref.watch(workflowsFamily(sessionId));
    final open = ref.watch(agentActivityPanelOpenProvider(sessionId));
    final running = agents.where((a) => a.isRunning).length +
        workflows.where((w) => w.isRunning).length;

    ref.listen<bool>(backgroundAgentsRunningProvider(sessionId), (previous, next) {
      if (next && previous == false) {
        // Deferred: the change can surface while another widget is building.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(agentActivityPanelOpenProvider(sessionId).notifier).state = true;
        });
      }
    });
    ref.listen<bool>(agentActivityPanelOpenProvider(sessionId), (previous, next) {
      if (next && previous != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onOpened?.call());
      }
    });

    final hasItems = agents.isNotEmpty || workflows.isNotEmpty;
    final Widget child;
    if (!hasItems) {
      child = const SizedBox(key: ValueKey('agent-activity-none'), height: 0);
    } else if (open) {
      child = Padding(
        key: const ValueKey('agent-activity-open'),
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 360,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: AgentActivityPanel(
            sessionId: sessionId,
            onClose: () =>
                ref.read(agentActivityPanelOpenProvider(sessionId).notifier).state = false,
          ),
        ),
      );
    } else {
      child = Padding(
        key: const ValueKey('agent-activity-strip'),
        padding: const EdgeInsets.all(3),
        child: Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('agent-activity-open-btn'),
            onTap: () =>
                ref.read(agentActivityPanelOpenProvider(sessionId).notifier).state = true,
            child: SizedBox(
              width: 34,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_left, size: 18, color: tokens.accent),
                  const SizedBox(height: 6),
                  Icon(Icons.hub_outlined, size: 15, color: tokens.syntaxFunction),
                  const SizedBox(height: 6),
                  _StatusDot(running: running > 0),
                  const SizedBox(height: 12),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Center(
                        child: Text(
                          running > 0 ? 'AGENTI · $running ATTIVI' : 'AGENTI',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
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

    // AnimatedSize clips while it resizes, so the panel never lays out squeezed.
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

/// Compact list of this session's workflows and subagents; a row expands to
/// the agent's output or the workflow's progress.
class AgentActivityPanel extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;

  const AgentActivityPanel({super.key, required this.sessionId, this.onClose});

  @override
  ConsumerState<AgentActivityPanel> createState() => _AgentActivityPanelState();
}

class _AgentActivityPanelState extends ConsumerState<AgentActivityPanel> {
  final Set<String> _expandedIds = <String>{};

  void _toggle(String id) => setState(() {
        if (!_expandedIds.remove(id)) _expandedIds.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final subagents = ref.watch(subagentsFamily(widget.sessionId));
    final workflows = ref.watch(workflowsFamily(widget.sessionId)).reversed.toList();
    final agents = subagents.where((s) => !s.isUnlinked).toList();
    final children = subagents.where((s) => s.isUnlinked).toList();
    final runningCount = subagents.where((s) => s.isRunning).length +
        workflows.where((w) => w.isRunning).length;
    final knownCost = agents.fold<double>(0, (total, s) => total + (s.cost ?? 0));
    final costLabel =
        '${agents.any((s) => s.cost == null) ? 'Parziale ' : ''}\$${knownCost.toStringAsFixed(4)}';
    final notifier = ref.read(subagentsFamily(widget.sessionId).notifier);

    Widget section(String label, IconData icon) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Row(
            children: [
              Icon(icon, size: 12, color: tokens.textMuted),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );

    return Column(
      key: const ValueKey('agent-activity-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.hub_outlined, size: 15, color: tokens.syntaxFunction),
              const SizedBox(width: 8),
              Text(
                'Agenti',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: tokens.headingFontFamily,
                ),
              ),
              if (agents.any((s) => (s.cost ?? 0) > 0)) ...[
                const SizedBox(width: 8),
                Text(
                  costLabel,
                  style: TextStyle(
                    color: tokens.syntaxString,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ],
              if (runningCount > 0) ...[
                const SizedBox(width: 8),
                _StatusDot(running: true),
                const SizedBox(width: 4),
                Text(
                  '$runningCount in esecuzione',
                  style: TextStyle(color: tokens.syntaxKeyword, fontSize: 10.5),
                ),
              ],
              const Spacer(),
              if (widget.onClose != null)
                IconButton(
                  key: const ValueKey('agent-activity-close-btn'),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Chiudi pannello agenti',
                  icon: Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              if (workflows.isNotEmpty) ...[
                section('Workflow (${workflows.length})', Icons.account_tree_outlined),
                for (final run in workflows)
                  _Entrance(
                    key: ValueKey('workflow-entry-${run.id}'),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _WorkflowCard(
                        key: ValueKey('workflow-card-${run.id}'),
                        run: run,
                        isExpanded: _expandedIds.contains(run.id),
                        onToggleExpand: () => _toggle(run.id),
                      ),
                    ),
                  ),
              ],
              if (agents.isNotEmpty) ...[
                section('Subagenti (${agents.length})', Icons.smart_toy_outlined),
                for (final subagent in agents)
                  _Entrance(
                    key: ValueKey('subagent-entry-${subagent.id}'),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: SubagentExpandableCard(
                          key: ValueKey('subagent-card-${subagent.id}'),
                          subagent: subagent,
                          isExpanded: _expandedIds.contains(subagent.id),
                          onToggleExpand: () => _toggle(subagent.id),
                          onSteer: (msg) => notifier.steerSubagent(subagent.id, msg),
                          onStop: () => notifier.stopSubagent(subagent.id),
                          onToggleSteeringBox: () => notifier.toggleSteering(subagent.id),
                        ),
                      ),
                    ),
                  ),
              ],
              if (children.isNotEmpty) ...[
                section('Sessioni figlie (${children.length})', Icons.account_tree_outlined),
                for (final child in children)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Row(
                      children: [
                        _StatusDot(running: child.isRunning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Sessione figlia non attribuita: ${child.name} · ${child.model ?? 'N/D'} · '
                            '${child.cost == null ? 'N/D' : '\$${child.cost!.toStringAsFixed(4)}'}',
                            key: ValueKey('unlinked-session-${child.id}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: tokens.textMuted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fades and slides a row in the first time it appears.
class _Entrance extends StatelessWidget {
  final Widget child;
  const _Entrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(12 * (1 - t), 0), child: child),
      ),
      child: child,
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool running;
  const _StatusDot({required this.running});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (!running) {
      return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: tokens.textMuted.withValues(alpha: 0.5), shape: BoxShape.circle),
      );
    }
    return SizedBox(
      width: 9,
      height: 9,
      child: CircularProgressIndicator(
        strokeWidth: 1.6,
        // A spinning indicator never settles; keep widget tests deterministic.
        value: _isTestBinding ? 0.75 : null,
        valueColor: AlwaysStoppedAnimation(tokens.syntaxKeyword),
      ),
    );
  }
}

/// One settled agent call from a workflow's journal.
typedef _JournalEntry = ({int index, bool ok, String text});

class _WorkflowCard extends StatefulWidget {
  final WorkflowItem run;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _WorkflowCard({
    super.key,
    required this.run,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  State<_WorkflowCard> createState() => _WorkflowCardState();
}

class _WorkflowCardState extends State<_WorkflowCard> {
  List<_JournalEntry> _journal = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _readJournal();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _WorkflowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.status != widget.run.status) _readJournal();
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    if (widget.run.isRunning && !kIsWeb && !_isTestBinding) {
      _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _readJournal());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _readJournal() {
    final path = widget.run.journalPath;
    // The journal lives on the host disk; the browser build only sees the final notification.
    if (kIsWeb || path == null) return;
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final entries = <_JournalEntry>[];
      for (final line in file.readAsLinesSync()) {
        try {
          final raw = jsonDecode(line) as Map<String, dynamic>;
          entries.add((
            index: (raw['index'] as num?)?.toInt() ?? entries.length,
            ok: raw['ok'] == true,
            text: raw['text']?.toString() ?? '',
          ));
        } catch (_) {
          // The run may be mid-append; the next read picks the line up.
        }
      }
      if (mounted && entries.length != _journal.length) setState(() => _journal = entries);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final run = widget.run;
    final ok = _journal.where((e) => e.ok).length;
    final failed = _journal.length - ok;
    final progress = _journal.isEmpty
        ? (run.summary.isNotEmpty ? run.summary : (run.isRunning ? 'In avvio…' : ''))
        : '$ok agenti completati${failed > 0 ? ' · $failed falliti' : ''}';
    final (statusLabel, statusColor) = switch (run.status) {
      'running' => ('In corso', tokens.syntaxKeyword),
      'error' => ('Errore', tokens.danger),
      'stopped' => ('Fermato', tokens.textMuted),
      _ => ('Completato', tokens.syntaxFunction),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: run.isRunning ? tokens.syntaxKeyword.withValues(alpha: 0.5) : tokens.border,
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: widget.onToggleExpand,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    _StatusDot(running: run.isRunning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            run.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          if (progress.isNotEmpty)
                            Text(
                              progress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: tokens.textMuted, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      widget.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isExpanded) ...[
              Container(height: 1, color: tokens.border),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (run.description != null && run.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          run.description!,
                          style: TextStyle(color: tokens.textSecondary, fontSize: 11.5),
                        ),
                      ),
                    if (run.phases.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final phase in run.phases)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceElevated,
                                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                                  border: Border.all(color: tokens.border),
                                ),
                                child: Text(
                                  phase,
                                  style: TextStyle(color: tokens.textSecondary, fontSize: 10.5),
                                ),
                              ),
                          ],
                        ),
                      ),
                    for (final entry in _journal)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              entry.ok ? Icons.check_circle_outline : Icons.error_outline,
                              size: 12,
                              color: entry.ok ? tokens.syntaxFunction : tokens.danger,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Agente #${entry.index + 1}${entry.text.isEmpty ? '' : ': ${entry.text.trim().split('\n').first}'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (run.result.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tokens.background,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            run.result,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 11,
                              fontFamily: tokens.monoFontFamily,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    else if (_journal.isEmpty)
                      Text(
                        run.isRunning ? 'In attesa del primo agente completato…' : 'Nessun risultato registrato.',
                        style: TextStyle(color: tokens.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    if (run.scriptPath != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SelectableText(
                          run.scriptPath!,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SubagentExpandableCard extends StatefulWidget {
  final SubagentItem subagent;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onSteer;
  final VoidCallback onStop;
  final VoidCallback onToggleSteeringBox;

  const SubagentExpandableCard({
    super.key,
    required this.subagent,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onSteer,
    required this.onStop,
    required this.onToggleSteeringBox,
  });

  @override
  State<SubagentExpandableCard> createState() => _SubagentExpandableCardState();
}

class _SubagentExpandableCardState extends State<SubagentExpandableCard> {
  final TextEditingController _steerController = TextEditingController();
  final ScrollController _outputScrollController = ScrollController();

  @override
  void dispose() {
    _steerController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  void _submitSteer() {
    final text = _steerController.text.trim();
    if (text.isEmpty) return;
    widget.onSteer(text);
    _steerController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sub = widget.subagent;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: sub.isRunning
              ? tokens.syntaxKeyword.withValues(alpha: 0.5)
              : tokens.border,
          width: sub.isRunning ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Card Title Bar / Window Header
          InkWell(
            onTap: widget.onToggleExpand,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  _buildStatusIndicator(tokens, sub.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sub.isCompleted ? tokens.textMuted : tokens.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            decoration: sub.isCompleted ? TextDecoration.lineThrough : null,
                            decorationColor: tokens.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Always display the model used for each subagent
                            Flexible(
                              child: Text(
                                sub.model != null && sub.model!.isNotEmpty ? sub.model! : 'N/D',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 10,
                                  fontFamily: tokens.monoFontFamily,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sub.cost == null ? 'N/D' : '\$${sub.cost!.toStringAsFixed(4)}',
                              style: TextStyle(
                                color: tokens.syntaxString,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                          ],
                        ),
                        if (sub.description != null &&
                            sub.description!.isNotEmpty &&
                            sub.description != sub.name)
                          Text(
                            sub.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: tokens.textMuted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    widget.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Card Expanded Body
          if (widget.isExpanded) ...[
            Container(
              height: 1,
              color: tokens.border,
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        key: ValueKey('subagent-steer-btn-${sub.id}'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: Icon(
                          sub.isSteeringOpen ? Icons.close : Icons.navigation_outlined,
                          size: 14,
                          color: sub.isSteeringOpen ? tokens.textMuted : tokens.syntaxFunction,
                        ),
                        label: Text(
                          sub.isSteeringOpen ? 'Chiudi guida' : 'Guida',
                          style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                        ),
                        onPressed: widget.onToggleSteeringBox,
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        key: ValueKey('subagent-stop-btn-${sub.id}'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: Icon(
                          Icons.stop_circle_outlined,
                          size: 15,
                          color: sub.isRunning ? tokens.danger : tokens.textMuted.withValues(alpha: 0.4),
                        ),
                        label: Text(
                          sub.isRunning ? 'Interrompi' : 'Terminato',
                          style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                        ),
                        onPressed: sub.isRunning ? widget.onStop : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Steering Input Box (when active)
                  if (sub.isSteeringOpen) ...[
                    Container(
                      key: ValueKey('subagent-steer-box-${sub.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.syntaxFunction,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.navigation_outlined,
                                size: 13,
                                color: tokens.syntaxFunction,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Guida manuale subagente',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: ValueKey('subagent-steer-input-${sub.id}'),
                                  controller: _steerController,
                                  autofocus: true,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Invia istruzioni per guidare il subagente...',
                                    hintStyle: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 11.5,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    filled: true,
                                    fillColor: tokens.background,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(tokens.radiusSm),
                                      borderSide:
                                          BorderSide(color: tokens.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(tokens.radiusSm),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxFunction,
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _submitSteer(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.icon(
                                key: ValueKey('subagent-steer-send-${sub.id}'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: tokens.syntaxFunction,
                                  foregroundColor: tokens.surface,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.send, size: 12),
                                label: const Text('Invia',
                                    style: TextStyle(fontSize: 11)),
                                onPressed: _submitSteer,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Output Terminal/Console Display
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: sub.output.isNotEmpty
                        ? Scrollbar(
                            controller: _outputScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _outputScrollController,
                              child: SelectableText(
                                sub.output,
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 11,
                                  fontFamily: tokens.monoFontFamily,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Text(
                                sub.isRunning
                                    ? (sub.description != null && sub.description!.isNotEmpty
                                        ? 'Attività: ${sub.description}\n\nIn attesa di output dal subagente...'
                                        : 'In attesa di output dal subagente...')
                                    : (sub.description != null && sub.description!.isNotEmpty
                                        ? 'Attività: ${sub.description}\n\nCompletato.'
                                        : 'Nessun output registrato per questo subagente.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(FrameTokens tokens, String status) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'running':
        color = tokens.syntaxKeyword;
        icon = Icons.refresh;
        label = 'In corso';
        break;
      case 'steering':
      case 'steered':
        color = tokens.syntaxFunction;
        icon = Icons.alt_route;
        label = 'Guidato';
        break;
      case 'stopped':
        color = tokens.textMuted;
        icon = Icons.stop_circle_outlined;
        label = 'Fermato';
        break;
      case 'error':
        color = tokens.danger;
        icon = Icons.error_outline;
        label = 'Errore';
        break;
      case 'completed':
      default:
        color = tokens.syntaxFunction;
        icon = Icons.check_circle_outline;
        label = 'Completato';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
