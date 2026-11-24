import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_empty_state.dart';
import '../../ui/frame_icon_action.dart';

/// The branch tree of one session, shown with [show] as a [FrameDialog]. The
/// dialog is titled with the session's title; its id is a copyable detail row.
class SessionTreeDialog extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionTreeDialog({super.key, required this.sessionId});

  /// Opens the tree of [sessionId]. The title comes from the session's current
  /// display name, read from the enclosing [ProviderScope].
  static Future<void> show(BuildContext context, {required String sessionId}) {
    final container = ProviderScope.containerOf(context, listen: false);
    final title = container.read(sessionDisplayNameProvider(sessionId));
    final strings = container.read(appStringsProvider);
    return showFrameDialog<void>(
      context: context,
      dialog: FrameDialog<void>(
        title: title,
        body: SessionTreeDialog(sessionId: sessionId),
        actions: [FrameDialogAction<void>(label: strings.close, role: FrameDialogActionRole.cancel)],
      ),
    );
  }

  @override
  ConsumerState<SessionTreeDialog> createState() => _SessionTreeDialogState();
}

/// Minimum body height, so the empty, loading and error states do not collapse.
const double _minBodyHeight = 240;

/// Tallest the node list gets before it scrolls.
const double _maxListHeight = 360;

class _SessionTreeDialogState extends ConsumerState<SessionTreeDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _treeData;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTree());
  }

  Future<void> _loadTree() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = ref.read(pcpClientProvider);
    if (client == null) {
      final strings = ref.read(appStringsProvider);
      setState(() {
        _loading = false;
        _error = strings.composerDaemonNotConnected;
      });
      return;
    }

    try {
      final res = await client.getSessionTree(widget.sessionId);
      if (!mounted) return;
      final data = res['data'] as Map<String, dynamic>? ?? res;
      setState(() {
        _loading = false;
        _treeData = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minBodyHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row of the body: the session id (copyable) and refresh.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.sessionTreeIdLabel, style: text.caption.copyWith(color: tokens.textMuted)),
                    SelectableText(
                      widget.sessionId,
                      key: const ValueKey('session-tree-id'),
                      maxLines: 1,
                      style: text.mono.copyWith(color: tokens.textPrimary),
                    ),
                  ],
                ),
              ),
              FrameIconAction(
                key: const ValueKey('session-tree-copy-id'),
                icon: Icons.copy_outlined,
                tooltip: strings.sessionTreeCopyIdTooltip,
                onPressed: () => Clipboard.setData(ClipboardData(text: widget.sessionId)),
              ),
              FrameIconAction(
                key: const ValueKey('session-tree-refresh'),
                icon: Icons.refresh_outlined,
                tooltip: strings.sessionTreeReload,
                onPressed: _loading ? null : _loadTree,
              ),
            ],
          ),
          const SizedBox(height: FrameSpace.x4),
          _buildBody(tokens, text, strings),
        ],
      ),
    );
  }

  Widget _buildBody(FrameTokens tokens, FrameText text, AppStrings strings) {
    if (_loading) {
      return SizedBox(
        height: _minBodyHeight,
        child: Center(
          child: FrameActivityIndicator(size: FrameSize.iconLg, strokeWidth: 2, color: tokens.accent),
        ),
      );
    }

    if (_error != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minBodyHeight),
        child: FrameEmptyState(
          keyPrefix: 'session-tree-error',
          icon: Icons.error_outlined,
          title: strings.sessionTreeLoadFailed,
          message: strings.sessionTreeError(_error!),
          actionLabel: strings.sessionTreeEmptyAction,
          onAction: _loadTree,
        ),
      );
    }

    final parentOf = <String, String?>{};
    final entries = _treeData?['entries'] as List<dynamic>? ?? const [];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString();
      if (id != null) parentOf[id] = entry['parentId']?.toString();
    }
    final nodes = (_treeData?['tree'] as List<dynamic>? ?? _treeData?['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((node) => Map<String, dynamic>.from(node))
        .toList();
    final rows = flattenSessionTree(nodes, parentOf);

    if (rows.isEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minBodyHeight),
        child: FrameEmptyState(
          keyPrefix: 'session-tree-empty',
          icon: Icons.device_hub_outlined,
          title: strings.sessionTreeNoBranches,
          message: strings.sessionTreeAllMessagesMainBranch,
          actionLabel: strings.sessionTreeEmptyAction,
          onAction: _loadTree,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxListHeight),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: rows.length,
        itemBuilder: (context, index) =>
            _TreeNodeTile(row: rows[index], tokens: tokens, text: text, activeBadge: strings.sessionTreeActiveBadge),
      ),
    );
  }
}

/// One node of the tree, in display order, with what it needs to draw its
/// connector lines.
class SessionTreeRow {
  final Map<String, dynamic> node;
  final int depth;

  /// For each column left of this node's own elbow: whether a line runs down
  /// through it, because that ancestor has later siblings.
  final List<bool> guides;

  /// Whether this node is the last of its siblings (its elbow stops halfway).
  final bool isLast;

  const SessionTreeRow({required this.node, required this.depth, required this.guides, required this.isLast});
}

/// Flattens the tree depth-first. A node's parent comes from `parentId` on the
/// node, else from [parentOf] (the entries of the session), else the node is a
/// root. Cycles are cut so a bad payload cannot loop forever.
List<SessionTreeRow> flattenSessionTree(List<Map<String, dynamic>> nodes, Map<String, String?> parentOf) {
  final ids = {for (final node in nodes) node['id']?.toString() ?? ''};
  final children = <String, List<Map<String, dynamic>>>{};
  final roots = <Map<String, dynamic>>[];
  for (final node in nodes) {
    final id = node['id']?.toString() ?? '';
    final parent = (node['parentId'] ?? node['parent'])?.toString() ?? parentOf[id];
    if (parent == null || parent.isEmpty || !ids.contains(parent)) {
      roots.add(node);
    } else {
      children.putIfAbsent(parent, () => []).add(node);
    }
  }

  final rows = <SessionTreeRow>[];
  final seen = <String>{};
  void visit(Map<String, dynamic> node, int depth, List<bool> guides, bool isLast) {
    final id = node['id']?.toString() ?? '';
    if (!seen.add(id)) return;
    rows.add(SessionTreeRow(node: node, depth: depth, guides: guides, isLast: isLast));
    final kids = children[id] ?? const <Map<String, dynamic>>[];
    // Roots draw no connector; their children draw theirs in column 0.
    final childGuides = depth == 0 ? <bool>[] : [...guides, !isLast];
    for (var i = 0; i < kids.length; i++) {
      visit(kids[i], depth + 1, childGuides, i == kids.length - 1);
    }
  }

  for (var i = 0; i < roots.length; i++) {
    visit(roots[i], 0, const [], i == roots.length - 1);
  }
  return rows;
}

class _TreeNodeTile extends StatelessWidget {
  final SessionTreeRow row;
  final FrameTokens tokens;
  final FrameText text;
  final String activeBadge;

  const _TreeNodeTile({required this.row, required this.tokens, required this.text, required this.activeBadge});

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final role = node['role']?.toString() ?? 'entry';
    final summary = node['summary']?.toString() ?? node['text']?.toString() ?? node['id']?.toString() ?? '';
    final isLeaf = node['isLeaf'] == true;
    final isActive = node['isActive'] == true;

    final card = Container(
      margin: const EdgeInsets.only(bottom: FrameSpace.x2),
      padding: const EdgeInsets.all(FrameSpace.x3),
      decoration: BoxDecoration(
        color: isActive ? tokens.surfaceElevated : tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: isActive ? tokens.accent : tokens.border),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.radio_button_checked_outlined : (isLeaf ? Icons.nature_outlined : Icons.commit_outlined),
            color: isActive ? tokens.accent : tokens.textMuted,
            size: FrameSize.icon,
          ),
          const SizedBox(width: FrameSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      role.toUpperCase(),
                      style: text.caption.copyWith(color: tokens.textSecondary, fontWeight: FontWeight.bold),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: FrameSpace.x1),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x1),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          activeBadge,
                          style: text.caption.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: FrameSpace.x1),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.body.copyWith(color: tokens.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (row.depth == 0) return card;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: row.depth * FrameSpace.x4,
            child: CustomPaint(
              painter: _TreeConnectorPainter(
                depth: row.depth,
                guides: row.guides,
                isLast: row.isLast,
                color: tokens.borderStrong,
              ),
            ),
          ),
          Expanded(child: card),
        ],
      ),
    );
  }
}

/// Draws the connector lines of one tree row: a vertical guide for each
/// ancestor that has later siblings, and an elbow into this node.
class _TreeConnectorPainter extends CustomPainter {
  final int depth;
  final List<bool> guides;
  final bool isLast;
  final Color color;

  const _TreeConnectorPainter({required this.depth, required this.guides, required this.isLast, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const unit = FrameSpace.x4;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // The card sits above its bottom margin; the elbow meets the card's middle.
    final centreY = (size.height - FrameSpace.x2) / 2;

    for (var column = 0; column < guides.length; column++) {
      if (!guides[column]) continue;
      final x = column * unit + unit / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final x = (depth - 1) * unit + unit / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, isLast ? centreY : size.height), paint);
    canvas.drawLine(Offset(x, centreY), Offset(depth * unit, centreY), paint);
  }

  @override
  bool shouldRepaint(covariant _TreeConnectorPainter old) =>
      old.depth != depth || old.isLast != isLast || old.color != color || !listEquals(old.guides, guides);
}
