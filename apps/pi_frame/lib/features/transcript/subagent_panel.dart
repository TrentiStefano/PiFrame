import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_transcript.dart';
import 'subagents_provider.dart';
import 'workflows_provider.dart';

bool get _isTestBinding =>
    WidgetsBinding.instance.runtimeType.toString().contains('Test');

/// The Agents/Workflows column beside the chat card: a slim strip while
/// closed, the full [AgentActivityPanel] while open, nothing when the session
/// never delegated work.
class AgentActivitySidecar extends ConsumerStatefulWidget {
  final String sessionId;

  /// Called whenever the panel opens, so the shell can make room for it.
  final VoidCallback? onOpened;

  const AgentActivitySidecar({super.key, required this.sessionId, this.onOpened});

  @override
  ConsumerState<AgentActivitySidecar> createState() => _AgentActivitySidecarState();
}

class _AgentActivitySidecarState extends ConsumerState<AgentActivitySidecar> {
  @override
  void initState() {
    super.initState();
    final sessionId = widget.sessionId;
    // fireImmediately: a session entered with agents at work, or with the
    // panel left open, must open it and make room just like a fresh launch.
    ref.listenManual<bool>(backgroundAgentsRunningProvider(sessionId), (previous, next) {
      if (next && previous != true) {
        // Deferred: the change can surface while another widget is building.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(agentActivityPanelOpenProvider(sessionId).notifier).state = true;
        });
      }
    }, fireImmediately: true);
    ref.listenManual<bool>(agentActivityPanelOpenProvider(sessionId), (previous, next) {
      if (next && previous != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onOpened?.call();
        });
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final agents = ref.watch(subagentsFamily(sessionId));
    final workflows = ref.watch(workflowsFamily(sessionId));
    final open = ref.watch(agentActivityPanelOpenProvider(sessionId));
    final running = agents.where((a) => a.isRunning).length +
        workflows.where((w) => w.isRunning).length;

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
                          running > 0
                              ? strings.subagentsStripActive(running)
                              : strings.subagentsStripIdle,
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

/// This session's workflows and subagents as a live tree; a node expands to
/// the agent's task and output or the workflow's result.
class AgentActivityPanel extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;

  const AgentActivityPanel({super.key, required this.sessionId, this.onClose});

  @override
  ConsumerState<AgentActivityPanel> createState() => _AgentActivityPanelState();
}

class _AgentActivityPanelState extends ConsumerState<AgentActivityPanel> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final subagents = ref.watch(subagentsFamily(widget.sessionId));
    final workflows = ref.watch(workflowsFamily(widget.sessionId)).reversed.toList();
    final runningCount = subagents.where((s) => s.isRunning).length +
        workflows.where((w) => w.isRunning).length;
    // Unlinked children may belong to a listed agent; summing them could count a cost twice.
    final agents = subagents.where((s) => !s.isUnlinked).toList();
    final knownCost = agents.fold<double>(0, (total, s) => total + (s.cost ?? 0));
    final costLabel =
        '${agents.any((s) => s.cost == null) ? strings.subagentsPartialCostPrefix : ''}\$${knownCost.toStringAsFixed(4)}';

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
                strings.subagentsPanelTitle,
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
                  strings.subagentsRunningCount(runningCount),
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
                  tooltip: strings.subagentsCloseTooltip,
                  icon: Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: _AgentTree(
            sessionId: widget.sessionId,
            workflows: workflows,
            subagents: subagents,
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

const double _treeStep = 22;
const double _avatarSize = 22;
const double _rowTopPad = 5;
const double _nodeCenterY = _rowTopPad + _avatarSize / 2;

/// One row of the agent map: a node on the session tree.
class _TreeNode {
  final String id;
  final int depth;
  final bool isLast;
  final bool hasChildren;
  /// For each ancestor level, whether its trunk continues past this row.
  final List<bool> guides;
  final SubagentItem? agent;
  final WorkflowItem? run;
  final List<SubagentItem> runChildren;

  const _TreeNode({
    required this.id,
    required this.depth,
    required this.isLast,
    this.hasChildren = false,
    this.guides = const [],
    this.agent,
    this.run,
    this.runChildren = const [],
  });

  bool get isRunning => agent?.isRunning ?? run?.isRunning ?? false;
}

String _elapsed(int? from, int? to) {
  if (from == null) return '';
  final seconds = ((to ?? DateTime.now().millisecondsSinceEpoch) - from) ~/ 1000;
  if (seconds < 0) return '';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

(String, Color) _statusStyle(FrameTokens tokens, AppStrings strings, String status) => switch (status) {
      'running' || 'steering' => (strings.subagentStatusInProgress, tokens.agentWorking),
      'error' => (strings.subagentStatusError, tokens.agentError),
      'stopped' => (strings.subagentStatusStopped, tokens.textMuted),
      _ => (strings.subagentStatusCompleted, tokens.success),
    };

Color _typeColor(FrameTokens tokens, String? type) {
  final palette = [
    tokens.syntaxFunction,
    tokens.syntaxString,
    tokens.syntaxType,
    tokens.syntaxNumber,
    tokens.syntaxVariable,
    tokens.info,
  ];
  final key = (type ?? '').toLowerCase();
  return palette[key.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff) % palette.length];
}

IconData _typeIcon(String? type) {
  final key = (type ?? '').toLowerCase();
  if (key.contains('explore') || key.contains('locator') || key.contains('scout')) return Icons.travel_explore;
  if (key.contains('review') || key.contains('verif') || key.contains('audit')) return Icons.fact_check_outlined;
  if (key.contains('plan') || key.contains('architect')) return Icons.architecture;
  if (key.contains('research') || key.contains('web')) return Icons.public;
  if (key.contains('analy')) return Icons.insights_outlined;
  if (key.contains('worker') || key.contains('builder')) return Icons.construction_outlined;
  return Icons.smart_toy_outlined;
}

IconData _toolIcon(String tool) {
  final key = tool.toLowerCase();
  if (key.contains('shell') || key == 'bash' || key.contains('terminal')) return Icons.terminal;
  if (key.contains('read')) return Icons.description_outlined;
  if (key.contains('edit') || key.contains('write')) return Icons.edit_outlined;
  if (key.contains('grep') || key.contains('find') || key.contains('ls') || key.contains('search')) {
    return Icons.search;
  }
  if (key.contains('web') || key.contains('fetch')) return Icons.public;
  if (key.contains('agent')) return Icons.hub_outlined;
  return Icons.bolt_outlined;
}

/// Agents and workflow runs of a session drawn as a tree hanging from the
/// session, with live activity on each running branch.
class _AgentTree extends ConsumerStatefulWidget {
  final String sessionId;
  final List<WorkflowItem> workflows;
  final List<SubagentItem> subagents;

  const _AgentTree({required this.sessionId, required this.workflows, required this.subagents});

  @override
  ConsumerState<_AgentTree> createState() => _AgentTreeState();
}

class _AgentTreeState extends ConsumerState<_AgentTree> with SingleTickerProviderStateMixin {
  final Set<String> _expandedIds = <String>{};
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() {
        if (!_expandedIds.remove(id)) _expandedIds.add(id);
      });

  List<_TreeNode> _nodes() {
    final linked = widget.subagents.where((s) => !s.isUnlinked).toList().reversed.toList();
    final split = workflowChildren(widget.workflows, widget.subagents.where((s) => s.isUnlinked).toList());
    final top = <({WorkflowItem? run, SubagentItem? agent})>[
      for (final run in widget.workflows) (run: run, agent: null),
      for (final agent in linked) (run: null, agent: agent),
      for (final agent in split['']!.reversed) (run: null, agent: agent),
    ];
    final nodes = <_TreeNode>[];
    for (var i = 0; i < top.length; i++) {
      final item = top[i];
      final isLast = i == top.length - 1;
      final children = item.run == null ? const <SubagentItem>[] : split[item.run!.id]!;
      nodes.add(_TreeNode(
        id: item.run?.id ?? item.agent!.id,
        depth: 1,
        isLast: isLast,
        hasChildren: children.isNotEmpty,
        agent: item.agent,
        run: item.run,
        runChildren: children,
      ));
      for (var j = 0; j < children.length; j++) {
        nodes.add(_TreeNode(
          id: children[j].id,
          depth: 2,
          isLast: j == children.length - 1,
          guides: [!isLast],
          agent: children[j],
        ));
      }
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _nodes();
    final anyRunning = nodes.any((n) => n.isRunning);
    if (anyRunning && !_isTestBinding) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
    final strings = ref.watch(appStringsProvider);
    final notifier = ref.read(subagentsFamily(widget.sessionId).notifier);
    final agentNodes = nodes.where((n) => n.agent != null);
    final working = agentNodes.where((n) => n.isRunning).length;
    final runCount = widget.workflows.length;
    final summary = [
      if (runCount > 0) '$runCount workflow',
      strings.subagentsCount(agentNodes.length),
      working > 0 ? strings.subagentsWorking(working) : strings.subagentsAllIdle,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      children: [
        _TreeRow(
          key: const ValueKey('agent-tree-root'),
          depth: 0,
          isLast: true,
          hasChildren: nodes.isNotEmpty,
          running: anyRunning,
          color: context.tokens.accent,
          pulse: _pulse,
          avatar: _NodeAvatar(
            icon: Icons.forum_outlined,
            color: context.tokens.accent,
            running: false,
            pulse: _pulse,
          ),
          title: strings.subagentMainSession,
          subtitle: Text(
            summary,
            style: TextStyle(color: context.tokens.textMuted, fontSize: 10.5),
          ),
        ),
        for (final node in nodes)
          _Entrance(
            key: ValueKey(node.run != null ? 'workflow-entry-${node.id}' : 'subagent-entry-${node.id}'),
            child: node.run != null
                ? _workflowRow(node, strings)
                : _agentRow(node, notifier, strings),
          ),
      ],
    );
  }

  Widget _workflowRow(_TreeNode node, AppStrings strings) {
    final tokens = context.tokens;
    final run = node.run!;
    final done = node.runChildren.where((c) => !c.isRunning).length;
    final working = node.runChildren.where((c) => c.isRunning).length;
    final (statusLabel, statusColor) = _statusStyle(tokens, strings, run.status);
    final counts = node.runChildren.isEmpty
        ? (run.summary.isNotEmpty ? run.summary : (run.isRunning ? strings.workflowStarting : ''))
        : strings.subagentsFinishedWorking(done, node.runChildren.length, working);
    final expanded = _expandedIds.contains(run.id);
    return _TreeRow(
      key: ValueKey('workflow-card-${run.id}'),
      depth: node.depth,
      isLast: node.isLast,
      guides: node.guides,
      hasChildren: node.hasChildren,
      running: run.isRunning,
      color: tokens.syntaxKeyword,
      pulse: _pulse,
      onTap: () => _toggle(run.id),
      avatar: _NodeAvatar(
        icon: Icons.account_tree_outlined,
        color: tokens.syntaxKeyword,
        running: run.isRunning,
        pulse: _pulse,
        status: run.status,
      ),
      title: run.name,
      badge: 'WORKFLOW',
      trailing: _StatusChip(
        label: statusLabel,
        color: statusColor,
        detail: _elapsed(run.timestamp, run.endedAt),
        expanded: expanded,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (counts.isNotEmpty)
            Text(
              counts,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            ),
          if (node.runChildren.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ProgressSegments(children: node.runChildren),
          ],
          if (run.phases.isNotEmpty) ...[
            const SizedBox(height: 4),
            _PhaseTrack(phases: run.phases, settled: !run.isRunning),
          ],
        ],
      ),
      details: expanded ? _WorkflowDetails(run: run, hasChildren: node.runChildren.isNotEmpty, strings: strings) : null,
    );
  }

  Widget _agentRow(_TreeNode node, SubagentsNotifier notifier, AppStrings strings) {
    final tokens = context.tokens;
    final agent = node.agent!;
    final (statusLabel, statusColor) = _statusStyle(tokens, strings, agent.status);
    final color = _typeColor(tokens, agent.agentType ?? agent.name);
    final expanded = _expandedIds.contains(agent.id);
    // Workflow children have no name of their own; their task line says what they do.
    final title = agent.isUnlinked ? (agent.prompt ?? agent.name) : agent.name;
    final type = agent.agentType ?? (agent.isUnlinked ? agent.name.split('#').first : null);
    final meta = [
      if (type != null && type.isNotEmpty) type,
      // Unknown stays unknown: never shown as a zero cost.
      agent.model ?? strings.transcriptNotAvailable,
      agent.cost == null ? strings.transcriptNotAvailable : '\$${agent.cost!.toStringAsFixed(4)}',
    ].join(' · ');
    return _TreeRow(
      key: ValueKey(agent.isUnlinked ? 'unlinked-session-${agent.id}' : 'subagent-card-${agent.id}'),
      depth: node.depth,
      isLast: node.isLast,
      guides: node.guides,
      running: agent.isRunning,
      color: color,
      pulse: _pulse,
      onTap: () => _toggle(agent.id),
      avatar: _NodeAvatar(
        icon: _typeIcon(type ?? agent.name),
        color: color,
        running: agent.isRunning,
        pulse: _pulse,
        status: agent.status,
      ),
      title: title,
      titleMaxLines: agent.isUnlinked ? 2 : 1,
      struck: agent.isCompleted && !agent.isUnlinked,
      trailing: _StatusChip(
        label: statusLabel,
        color: statusColor,
        detail: _elapsed(agent.startedAt, agent.isRunning ? null : agent.updatedAt),
        expanded: expanded,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textMuted, fontSize: 10.5, fontFamily: tokens.monoFontFamily),
            ),
          if (agent.activity != null && agent.activity!.isNotEmpty) ...[
            const SizedBox(height: 3),
            _ActivityLine(text: agent.activity!, running: agent.isRunning, color: color),
          ],
        ],
      ),
      details: expanded
          ? _AgentDetails(
              agent: agent,
              strings: strings,
              onSteer: (msg) => notifier.steerSubagent(agent.id, msg),
              onStop: () => notifier.stopSubagent(agent.id),
              onToggleSteeringBox: () => notifier.toggleSteering(agent.id),
            )
          : null,
    );
  }
}

/// A tree row: guide lines and elbow in the gutter, avatar, then content.
class _TreeRow extends StatelessWidget {
  final int depth;
  final bool isLast;
  final bool hasChildren;
  final List<bool> guides;
  final bool running;
  final Color color;
  final Animation<double> pulse;
  final Widget avatar;
  final String title;
  final int titleMaxLines;
  /// Settled agents read as done, like a ticked-off task.
  final bool struck;
  final String? badge;
  final Widget? trailing;
  final Widget? subtitle;
  final Widget? details;
  final VoidCallback? onTap;

  const _TreeRow({
    super.key,
    required this.depth,
    required this.isLast,
    this.hasChildren = false,
    this.guides = const [],
    required this.running,
    required this.color,
    required this.pulse,
    required this.avatar,
    required this.title,
    this.titleMaxLines = 1,
    this.struck = false,
    this.badge,
    this.trailing,
    this.subtitle,
    this.details,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final indent = depth * _treeStep;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (badge != null) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 1, right: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: color,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: struck ? tokens.textMuted : tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            height: 1.25,
                            decoration: struck ? TextDecoration.lineThrough : null,
                            decorationColor: tokens.textMuted,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[const SizedBox(width: 6), trailing!],
                    ],
                  ),
                  if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
                ],
              ),
            ),
          ],
        ),
        if (details != null)
          Padding(
            padding: const EdgeInsets.only(left: _avatarSize + 8, top: 6),
            child: details!,
          ),
      ],
    );
    return CustomPaint(
      painter: _TreeLinePainter(
        depth: depth,
        isLast: isLast,
        hasChildren: hasChildren,
        guides: guides,
        running: running,
        line: tokens.borderStrong,
        color: color,
        pulse: pulse,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, _rowTopPad, 4, 7),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeLinePainter extends CustomPainter {
  final int depth;
  final bool isLast;
  final bool hasChildren;
  final List<bool> guides;
  final bool running;
  final Color line;
  final Color color;
  final Animation<double> pulse;

  _TreeLinePainter({
    required this.depth,
    required this.isLast,
    required this.hasChildren,
    required this.guides,
    required this.running,
    required this.line,
    required this.color,
    required this.pulse,
  }) : super(repaint: running ? pulse : null);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < guides.length; i++) {
      if (!guides[i]) continue;
      final x = i * _treeStep + _avatarSize / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), stroke);
    }
    if (hasChildren) {
      final x = depth * _treeStep + _avatarSize / 2;
      canvas.drawLine(Offset(x, _nodeCenterY + _avatarSize / 2), Offset(x, size.height), stroke);
    }
    if (depth == 0) return;
    final x = (depth - 1) * _treeStep + _avatarSize / 2;
    final end = depth * _treeStep;
    const radius = 6.0;
    final elbow = Path()
      ..moveTo(x, 0)
      ..lineTo(x, _nodeCenterY - radius)
      ..quadraticBezierTo(x, _nodeCenterY, x + radius, _nodeCenterY)
      ..lineTo(end, _nodeCenterY);
    canvas.drawPath(elbow, stroke);
    if (!isLast) canvas.drawLine(Offset(x, _nodeCenterY - radius), Offset(x, size.height), stroke);
    if (!running) return;
    canvas.drawPath(
      elbow,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );
    // A spark travels down the branch while the agent works.
    final metric = elbow.computeMetrics().first;
    final at = metric.getTangentForOffset(metric.length * pulse.value)?.position;
    if (at == null) return;
    canvas.drawCircle(at, 4, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(at, 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TreeLinePainter old) =>
      old.depth != depth ||
      old.isLast != isLast ||
      old.hasChildren != hasChildren ||
      old.running != running ||
      old.line != line ||
      old.color != color ||
      old.guides.length != guides.length ||
      !Iterable.generate(guides.length).every((i) => old.guides[i] == guides[i]);
}

/// Round agent badge; a running agent gets an orbiting arc.
class _NodeAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool running;
  final Animation<double> pulse;
  final String? status;

  const _NodeAvatar({
    required this.icon,
    required this.color,
    required this.running,
    required this.pulse,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (badgeIcon, badgeColor) = switch (status) {
      'error' => (Icons.priority_high, tokens.agentError),
      'stopped' => (Icons.stop, tokens.textMuted),
      'completed' || 'steered' => (Icons.check, tokens.success),
      _ => (null, null),
    };
    return SizedBox(
      width: _avatarSize,
      height: _avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.alphaBlend(color.withValues(alpha: running ? 0.22 : 0.12), tokens.surface),
                border: Border.all(color: color.withValues(alpha: running ? 0.9 : 0.45), width: 1.2),
              ),
              child: Icon(icon, size: 12, color: running ? color : color.withValues(alpha: 0.8)),
            ),
          ),
          if (running)
            Positioned(
              left: -3,
              top: -3,
              right: -3,
              bottom: -3,
              child: CustomPaint(painter: _OrbitPainter(color: color, pulse: pulse)),
            ),
          if (badgeIcon != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.surface, width: 1.5),
                ),
                child: Icon(badgeIcon, size: 7, color: tokens.surface),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Color color;
  final Animation<double> pulse;
  _OrbitPainter({required this.color, required this.pulse}) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(0.8),
      pulse.value * 2 * 3.14159265,
      1.9,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.color != color;
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final String detail;
  final bool expanded;
  const _StatusChip({required this.label, required this.color, required this.detail, required this.expanded});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
            if (detail.isNotEmpty)
              Text(
                detail,
                style: TextStyle(color: tokens.textMuted, fontSize: 9.5, fontFamily: tokens.monoFontFamily),
              ),
          ],
        ),
        Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 15, color: tokens.textMuted),
      ],
    );
  }
}

/// "tool: argument" while the agent works; its last answer line once done.
class _ActivityLine extends StatelessWidget {
  final String text;
  final bool running;
  final Color color;
  const _ActivityLine({required this.text, required this.running, required this.color});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tool = running ? RegExp(r'^([\w.\-]+):\s+(.*)$').firstMatch(text) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: running ? color.withValues(alpha: 0.08) : tokens.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border(left: BorderSide(color: running ? color : tokens.border, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              tool != null ? _toolIcon(tool.group(1)!) : (running ? Icons.chat_bubble_outline : Icons.notes),
              size: 11,
              color: running ? color : tokens.textMuted,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (tool != null)
                  TextSpan(
                    text: '${tool.group(1)} ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                TextSpan(text: tool?.group(2) ?? text),
              ]),
              maxLines: running ? 2 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: running ? tokens.textPrimary : tokens.textSecondary,
                fontSize: 10.5,
                height: 1.3,
                fontFamily: tool != null ? tokens.monoFontFamily : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One segment per workflow agent: filled when done, pulsing while it works.
class _ProgressSegments extends StatelessWidget {
  final List<SubagentItem> children;
  const _ProgressSegments({required this.children});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: 4,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: switch (children[i].status) {
                    'running' || 'steering' => tokens.agentWorking.withValues(alpha: 0.55),
                    'error' => tokens.agentError,
                    'stopped' => tokens.textMuted.withValues(alpha: 0.5),
                    _ => tokens.success,
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The workflow's declared phases as a connected track.
class _PhaseTrack extends StatelessWidget {
  final List<String> phases;
  final bool settled;
  const _PhaseTrack({required this.phases, required this.settled});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      runSpacing: 3,
      children: [
        for (var i = 0; i < phases.length; i++) ...[
          if (i > 0) Container(width: 8, height: 1, color: tokens.borderStrong),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: settled ? tokens.success.withValues(alpha: 0.6) : tokens.border),
              color: tokens.surfaceElevated,
            ),
            child: Text(
              phases[i],
              style: TextStyle(color: tokens.textSecondary, fontSize: 9.5),
            ),
          ),
        ],
      ],
    );
  }
}

/// Description, final result and, without child sessions, the journal of a
/// workflow run.
class _WorkflowDetails extends StatefulWidget {
  final WorkflowItem run;
  final bool hasChildren;
  final AppStrings? strings;
  const _WorkflowDetails({required this.run, required this.hasChildren, this.strings});

  @override
  State<_WorkflowDetails> createState() => _WorkflowDetailsState();
}

class _WorkflowDetailsState extends State<_WorkflowDetails> {
  List<_JournalEntry> _journal = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _readJournal();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _WorkflowDetails oldWidget) {
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
    if (widget.run.isRunning && !widget.hasChildren && !kIsWeb && !_isTestBinding) {
      _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _readJournal());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _readJournal() {
    final path = widget.run.journalPath;
    // The journal lives on the host disk; the browser build only sees the final notification.
    if (kIsWeb || path == null || widget.hasChildren) return;
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
    final strings = widget.strings ?? safeTranscriptStrings(context);
    final run = widget.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (run.description != null && run.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(run.description!, style: TextStyle(color: tokens.textSecondary, fontSize: 11.5)),
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
                  color: entry.ok ? tokens.success : tokens.danger,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    strings.workflowJournalAgent(
                      entry.index,
                      entry.text.isEmpty ? '' : entry.text.trim().split('\n').first,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        if (run.result.isNotEmpty)
          _OutputBox(text: run.result)
        else if (_journal.isEmpty && !widget.hasChildren)
          Text(
            run.isRunning ? strings.workflowWaitingFirstAgent : strings.workflowNoResultsRecorded,
            style: TextStyle(color: tokens.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
          ),
      ],
    );
  }
}

class _OutputBox extends StatelessWidget {
  final String text;
  const _OutputBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Long transcripts only matter at their end; keep layout cheap.
    final shown = text.length > 6000 ? '…${text.substring(text.length - 6000)}' : text;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          shown,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 11,
            fontFamily: tokens.monoFontFamily,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Task, output and controls of one agent in the tree.
class _AgentDetails extends StatefulWidget {
  final SubagentItem agent;
  final ValueChanged<String> onSteer;
  final VoidCallback onStop;
  final VoidCallback onToggleSteeringBox;
  final AppStrings? strings;

  const _AgentDetails({
    required this.agent,
    required this.onSteer,
    required this.onStop,
    required this.onToggleSteeringBox,
    this.strings,
  });

  @override
  State<_AgentDetails> createState() => _AgentDetailsState();
}

class _AgentDetailsState extends State<_AgentDetails> {
  final TextEditingController _steer = TextEditingController();

  @override
  void dispose() {
    _steer.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _steer.text.trim();
    if (text.isEmpty) return;
    widget.onSteer(text);
    _steer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = widget.strings ?? safeTranscriptStrings(context);
    final agent = widget.agent;
    final task = agent.isUnlinked ? null : (agent.description ?? agent.prompt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task != null && task.isNotEmpty && task != agent.name)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(task, style: TextStyle(color: tokens.textSecondary, fontSize: 11, height: 1.35)),
          ),
        // Child sessions run in a worker the daemon cannot steer.
        if (!agent.isUnlinked)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                TextButton.icon(
                  key: ValueKey('subagent-steer-btn-${agent.id}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: agent.isRunning ? widget.onToggleSteeringBox : null,
                  icon: Icon(Icons.alt_route, size: 13, color: tokens.syntaxFunction),
                  label: Text(
                    agent.isSteeringOpen ? strings.subagentSteerClose : strings.subagentSteer,
                    style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('subagent-stop-btn-${agent.id}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: agent.isRunning ? widget.onStop : null,
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    size: 13,
                    color: agent.isRunning ? tokens.danger : tokens.textMuted.withValues(alpha: 0.4),
                  ),
                  label: Text(
                    agent.isRunning ? strings.subagentStop : strings.subagentFinished,
                    style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (agent.isSteeringOpen && agent.isRunning)
          Padding(
            key: ValueKey('subagent-steer-box-${agent.id}'),
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('subagent-steer-input-${agent.id}'),
                    controller: _steer,
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                    style: TextStyle(color: tokens.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: strings.subagentSteerInputHint,
                      hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: tokens.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('subagent-steer-send-${agent.id}'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.send, size: 16, color: tokens.syntaxFunction),
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        if (agent.output.isNotEmpty)
          _OutputBox(text: agent.output)
        else
          Text(
            agent.isRunning ? strings.subagentWorkingOutput : strings.subagentNoOutputRecorded,
            style: TextStyle(color: tokens.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
          ),
      ],
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
  final AppStrings? strings;

  const SubagentExpandableCard({
    super.key,
    required this.subagent,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onSteer,
    required this.onStop,
    required this.onToggleSteeringBox,
    this.strings,
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
    final strings = widget.strings ?? safeTranscriptStrings(context);
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
                                sub.model != null && sub.model!.isNotEmpty
                                    ? sub.model!
                                    : strings.transcriptNotAvailable,
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
                              sub.cost == null
                                  ? strings.transcriptNotAvailable
                                  : '\$${sub.cost!.toStringAsFixed(4)}',
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
                          sub.isSteeringOpen
                              ? strings.subagentSteerClose
                              : strings.subagentSteer,
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
                          sub.isRunning
                              ? strings.subagentStop
                              : strings.subagentFinished,
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
                                strings.subagentManualSteeringTitle,
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
                                    hintText: strings.subagentManualSteeringHint,
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
                                label: Text(strings.subagentSendButton,
                                    style: const TextStyle(fontSize: 11)),
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
                                        ? strings.subagentWaitingWithTask(sub.description!)
                                        : strings.subagentWaitingOutput)
                                    : (sub.description != null && sub.description!.isNotEmpty
                                        ? strings.subagentCompletedWithTask(sub.description!)
                                        : strings.subagentNoOutputForThis),
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
    final strings = widget.strings ?? safeTranscriptStrings(context);

    switch (status) {
      case 'running':
        color = tokens.syntaxKeyword;
        icon = Icons.refresh;
        label = strings.subagentStatusInProgress;
        break;
      case 'steering':
      case 'steered':
        color = tokens.syntaxFunction;
        icon = Icons.alt_route;
        label = strings.subagentStatusSteered;
        break;
      case 'stopped':
        color = tokens.textMuted;
        icon = Icons.stop_circle_outlined;
        label = strings.subagentStatusStopped;
        break;
      case 'error':
        color = tokens.danger;
        icon = Icons.error_outline;
        label = strings.subagentStatusError;
        break;
      case 'completed':
      default:
        color = tokens.syntaxFunction;
        icon = Icons.check_circle_outline;
        label = strings.subagentStatusCompleted;
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
