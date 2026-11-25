import 'package:flutter/material.dart';

/// The regions of the app shell in keyboard order (plan task 6.2): Tab moves through
/// them in this order, top to bottom inside each one. F6 and Ctrl/Cmd+1…4 move between
/// the panes ([panes]).
enum FocusRegion {
  titleBar,
  sessions,
  repository,
  transcript,
  composer,
  companion;

  /// The panes F6 cycles through. The transcript and the composer are one chat pane,
  /// and the composer takes the focus when the chat pane is chosen.
  static const List<FocusRegion> panes = [titleBar, sessions, repository, composer, companion];

  /// The regions that make up a pane, in the order the pane should take focus.
  List<FocusRegion> get paneRegions => this == composer ? const [composer, transcript] : [this];

  /// Keyboard shortcut number (Ctrl/Cmd+1…4) for the four panes the user can jump to.
  static const Map<int, FocusRegion> numbered = {1: sessions, 2: repository, 3: composer, 4: companion};
}

/// Puts [child] in the traversal position of [region].
///
/// Tab order is the numeric order of the regions, so focus never jumps from the
/// composer to a row in another pane. Nodes inside a region keep their top-to-bottom
/// reading order, because the traversal sort is stable within equal orders.
class FocusRegionMarker extends StatelessWidget {
  const FocusRegionMarker({super.key, required this.region, required this.regionKey, required this.child});

  final FocusRegion region;

  /// Lets the shell find the focus nodes of this region. Attach each key once per build.
  final GlobalKey regionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      // The key lets tests tell which region holds the focus.
      key: ValueKey('focus-region-${region.name}'),
      order: NumericFocusOrder(region.index.toDouble()),
      child: KeyedSubtree(key: regionKey, child: child),
    );
  }
}

bool _contextWithin(BuildContext node, BuildContext region) {
  if (identical(node, region)) return true;
  var found = false;
  node.visitAncestorElements((ancestor) {
    if (identical(ancestor, region)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// True when [node] is inside the subtree of [regionKey].
bool focusIsWithin(GlobalKey regionKey, FocusNode? node) {
  final regionContext = regionKey.currentContext;
  final nodeContext = node?.context;
  if (regionContext == null || nodeContext == null) return false;
  return _contextWithin(nodeContext, regionContext);
}

/// Focus nodes that can take keyboard focus inside the subtree of [regionKey], in
/// reading order (top to bottom, then left to right).
List<FocusNode> focusableNodesIn(GlobalKey regionKey) {
  final regionContext = regionKey.currentContext;
  if (regionContext == null) return const <FocusNode>[];
  final nodes = FocusManager.instance.rootScope.traversalDescendants
      .where(
        (node) =>
            node.canRequestFocus &&
            !node.skipTraversal &&
            node.context != null &&
            _contextWithin(node.context!, regionContext),
      )
      .toList();
  nodes.sort((a, b) {
    final byTop = a.rect.top.compareTo(b.rect.top);
    return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
  });
  return nodes;
}
