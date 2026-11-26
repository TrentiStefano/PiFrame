import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expansion state of the Agents tab tree for one session: whether the Completed row is open,
/// and which subagents or workflows the user expanded. Held in memory only, so a restart starts collapsed.
@immutable
class SubagentTreeExpansionState {
  final bool completedOpen;
  final Set<String> expandedIds;

  const SubagentTreeExpansionState({this.completedOpen = false, this.expandedIds = const {}});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubagentTreeExpansionState &&
          completedOpen == other.completedOpen &&
          setEquals(expandedIds, other.expandedIds);

  @override
  int get hashCode => Object.hash(completedOpen, Object.hashAll(expandedIds));
}

/// Riverpod notifier for the Agents tab expansion state of one session.
class SubagentTreeExpansionNotifier extends StateNotifier<SubagentTreeExpansionState> {
  SubagentTreeExpansionNotifier() : super(const SubagentTreeExpansionState());

  void toggleCompleted() =>
      state = SubagentTreeExpansionState(completedOpen: !state.completedOpen, expandedIds: state.expandedIds);

  void toggleEntry(String id) {
    final next = Set<String>.from(state.expandedIds);
    if (!next.remove(id)) next.add(id);
    state = SubagentTreeExpansionState(completedOpen: state.completedOpen, expandedIds: next);
  }
}

/// Riverpod family provider keyed by `sessionId`, like [stepGroupExpansionProvider].
final subagentTreeExpansionProvider =
    StateNotifierProvider.family<SubagentTreeExpansionNotifier, SubagentTreeExpansionState, String>(
      (ref, sessionId) => SubagentTreeExpansionNotifier(),
    );
