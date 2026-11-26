import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expansion state of the Agents tab tree for one session: whether the Completed subagents group is open,
/// and which subagents or workflows the user expanded. Held in memory only, so a restart starts collapsed.
@immutable
class SubagentTreeExpansionState {
  /// Ids of every entry in the tree when the user last opened the group; null while the group is closed.
  /// The group stays open only while every entry shown now was among them, so new work closes it.
  final Set<String>? completedSeenIds;
  final Set<String> expandedIds;

  const SubagentTreeExpansionState({this.completedSeenIds, this.expandedIds = const {}});

  /// Whether the group is open for a tree showing [currentIds].
  bool completedOpenFor(Set<String> currentIds) {
    final seen = completedSeenIds;
    return seen != null && currentIds.every(seen.contains);
  }

  SubagentTreeExpansionState copyWith({ValueGetter<Set<String>?>? completedSeenIds, Set<String>? expandedIds}) =>
      SubagentTreeExpansionState(
        completedSeenIds: completedSeenIds == null ? this.completedSeenIds : completedSeenIds(),
        expandedIds: expandedIds ?? this.expandedIds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubagentTreeExpansionState &&
          setEquals(completedSeenIds, other.completedSeenIds) &&
          setEquals(expandedIds, other.expandedIds);

  @override
  int get hashCode => Object.hash(
    completedSeenIds == null ? null : Object.hashAllUnordered(completedSeenIds!),
    Object.hashAllUnordered(expandedIds),
  );
}

/// Riverpod notifier for the Agents tab expansion state of one session.
class SubagentTreeExpansionNotifier extends StateNotifier<SubagentTreeExpansionState> {
  SubagentTreeExpansionNotifier() : super(const SubagentTreeExpansionState());

  /// Opens the group for a tree showing [currentIds], or closes it when it is open for that tree.
  void toggleCompleted(Set<String> currentIds) {
    state = state.copyWith(
      completedSeenIds: () => state.completedOpenFor(currentIds) ? null : Set<String>.of(currentIds),
    );
  }

  void toggleEntry(String id) {
    final next = Set<String>.of(state.expandedIds);
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(expandedIds: next);
  }
}

/// Riverpod family provider keyed by `sessionId`, like [stepGroupExpansionProvider].
final subagentTreeExpansionProvider =
    StateNotifierProvider.family<SubagentTreeExpansionNotifier, SubagentTreeExpansionState, String>(
      (ref, sessionId) => SubagentTreeExpansionNotifier(),
    );
