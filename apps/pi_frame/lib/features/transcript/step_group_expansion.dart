import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable state holding user overrides for group expansion and child step expansions.
@immutable
class StepGroupExpansionState {
  /// Map of turnId -> userOverride (true = explicitly expanded, false = explicitly collapsed).
  final Map<String, bool> groupOverrides;

  /// Set of child step IDs (e.g. tool steps, thinking steps) that are individually expanded.
  final Set<String> expandedStepIds;

  /// Turn IDs whose expanded step list is shown at full height instead of the
  /// compact, height-limited scrollable list. Cleared whenever the group
  /// collapses, so re-expanding starts compact again.
  final Set<String> fullyExpandedGroups;

  const StepGroupExpansionState({
    this.groupOverrides = const {},
    this.expandedStepIds = const {},
    this.fullyExpandedGroups = const {},
  });

  /// Whether the expanded step list of [turnId] is shown at full height.
  bool isGroupFullyExpanded(String turnId) =>
      fullyExpandedGroups.contains(turnId);

  /// Evaluates whether a group is expanded:
  /// User manual override takes precedence; otherwise expanded while running or if autoCollapse is false.
  bool isGroupExpanded({
    required String turnId,
    required bool isRunning,
    required bool autoCollapse,
  }) {
    final userOverride = groupOverrides[turnId];
    return userOverride ?? (isRunning || !autoCollapse);
  }

  /// Whether a specific child step (tool details / thinking block) is expanded.
  bool isStepExpanded(String stepId) {
    return expandedStepIds.contains(stepId);
  }

  StepGroupExpansionState copyWith({
    Map<String, bool>? groupOverrides,
    Set<String>? expandedStepIds,
    Set<String>? fullyExpandedGroups,
  }) {
    return StepGroupExpansionState(
      groupOverrides: groupOverrides ?? this.groupOverrides,
      expandedStepIds: expandedStepIds ?? this.expandedStepIds,
      fullyExpandedGroups: fullyExpandedGroups ?? this.fullyExpandedGroups,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepGroupExpansionState &&
          runtimeType == other.runtimeType &&
          mapEquals(groupOverrides, other.groupOverrides) &&
          setEquals(expandedStepIds, other.expandedStepIds) &&
          setEquals(fullyExpandedGroups, other.fullyExpandedGroups);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(groupOverrides.entries),
        Object.hashAll(expandedStepIds),
        Object.hashAll(fullyExpandedGroups),
      );

  @override
  String toString() =>
      'StepGroupExpansionState(overrides: ${groupOverrides.length}, expandedSteps: ${expandedStepIds.length})';
}

/// Riverpod notifier managing expansion state for a specific session.
/// Survives UI rebuilds, streaming updates, and list virtualization.
class StepGroupExpansionNotifier
    extends StateNotifier<StepGroupExpansionState> {
  static const int maxGroupOverrides = 500;
  static const int maxExpandedSteps = 1000;

  /// Optional identifier of currently active/running turn so LRU eviction never drops it.
  String? activeTurnId;

  StepGroupExpansionNotifier({this.activeTurnId})
      : super(const StepGroupExpansionState());

  /// Sets or clears the active/running turn ID.
  void setActiveTurnId(String? turnId) {
    activeTurnId = turnId;
  }

  void _evictOldestGroupOverride(
    Map<String, bool> map, {
    String? protectedKey,
  }) {
    final candidate = map.keys.firstWhere(
      (key) => key != protectedKey && key != activeTurnId,
      orElse: () => map.keys.first,
    );
    map.remove(candidate);
  }

  /// Evaluates effective group expansion state.
  bool isGroupExpanded({
    required String turnId,
    required bool isRunning,
    required bool autoCollapse,
  }) {
    return state.isGroupExpanded(
      turnId: turnId,
      isRunning: isRunning,
      autoCollapse: autoCollapse,
    );
  }

  /// Toggles group expansion by setting user override to opposite of [currentEffective].
  /// True LRU: removes [turnId] before re-inserting so it moves to most-recent position.
  /// Eviction protects [runningTurnId] or [activeTurnId] from being dropped.
  void toggleGroup(
    String turnId,
    bool currentEffective, {
    String? runningTurnId,
  }) {
    if (runningTurnId != null) activeTurnId = runningTurnId;
    final nextOverrides = Map<String, bool>.from(state.groupOverrides);
    nextOverrides.remove(turnId);
    if (nextOverrides.length >= maxGroupOverrides) {
      _evictOldestGroupOverride(
        nextOverrides,
        protectedKey: runningTurnId ?? activeTurnId,
      );
    }
    nextOverrides[turnId] = !currentEffective;
    state = state.copyWith(
      groupOverrides: nextOverrides,
      // Collapsing resets the full-height list; the next expand is compact.
      fullyExpandedGroups: currentEffective
          ? (Set<String>.from(state.fullyExpandedGroups)..remove(turnId))
          : null,
    );
  }

  /// Shows the expanded step list of [turnId] at full height ([fully] true)
  /// or as the compact scrollable list ([fully] false).
  void setGroupFullyExpanded(String turnId, bool fully) {
    if (state.isGroupFullyExpanded(turnId) == fully) return;
    final next = Set<String>.from(state.fullyExpandedGroups);
    if (fully) {
      if (next.length >= maxGroupOverrides) next.remove(next.first);
      next.add(turnId);
    } else {
      next.remove(turnId);
    }
    state = state.copyWith(fullyExpandedGroups: next);
  }

  /// Sets an explicit user override for a group (or removes override if null).
  /// True LRU: removes [turnId] before re-inserting so it moves to most-recent position.
  /// Eviction protects [runningTurnId] or [activeTurnId] from being dropped.
  void setGroupOverride(
    String turnId,
    bool? override, {
    String? runningTurnId,
  }) {
    if (runningTurnId != null) activeTurnId = runningTurnId;
    final nextOverrides = Map<String, bool>.from(state.groupOverrides);
    if (override != true &&
        state.fullyExpandedGroups.contains(turnId)) {
      state = state.copyWith(
        fullyExpandedGroups: Set<String>.from(state.fullyExpandedGroups)
          ..remove(turnId),
      );
    }
    if (override == null) {
      nextOverrides.remove(turnId);
    } else {
      nextOverrides.remove(turnId);
      if (nextOverrides.length >= maxGroupOverrides) {
        _evictOldestGroupOverride(
          nextOverrides,
          protectedKey: runningTurnId ?? activeTurnId,
        );
      }
      nextOverrides[turnId] = override;
    }
    state = state.copyWith(groupOverrides: nextOverrides);
  }

  /// Whether a specific step card is expanded.
  bool isStepExpanded(String stepId) {
    return state.isStepExpanded(stepId);
  }

  /// Toggles expansion for an individual step item (e.g. tool execution details).
  /// True LRU: removes [stepId] before re-inserting so it moves to most-recent position.
  void toggleStep(String stepId) {
    final nextExpanded = Set<String>.from(state.expandedStepIds);
    if (nextExpanded.contains(stepId)) {
      nextExpanded.remove(stepId);
    } else {
      nextExpanded.remove(stepId);
      if (nextExpanded.length >= maxExpandedSteps) {
        final oldest = nextExpanded.first;
        nextExpanded.remove(oldest);
      }
      nextExpanded.add(stepId);
    }
    state = state.copyWith(expandedStepIds: nextExpanded);
  }

  /// Explicitly sets expansion for an individual step item.
  /// True LRU: removes [stepId] before re-inserting so it moves to most-recent position.
  void setStepExpanded(String stepId, bool expanded) {
    final nextExpanded = Set<String>.from(state.expandedStepIds);
    if (expanded) {
      nextExpanded.remove(stepId);
      if (nextExpanded.length >= maxExpandedSteps) {
        final oldest = nextExpanded.first;
        nextExpanded.remove(oldest);
      }
      nextExpanded.add(stepId);
    } else {
      nextExpanded.remove(stepId);
    }
    state = state.copyWith(expandedStepIds: nextExpanded);
  }

  /// Clears override for a turn, returning it to default auto-collapse behavior.
  void resetTurn(String turnId) {
    if (state.groupOverrides.containsKey(turnId) ||
        state.fullyExpandedGroups.contains(turnId)) {
      final nextOverrides = Map<String, bool>.from(state.groupOverrides)
        ..remove(turnId);
      state = state.copyWith(
        groupOverrides: nextOverrides,
        fullyExpandedGroups: Set<String>.from(state.fullyExpandedGroups)
          ..remove(turnId),
      );
    }
  }

  /// Clears all expansion state.
  void clear() {
    state = const StepGroupExpansionState();
  }
}

/// Riverpod family provider keyed by `sessionId`.
final stepGroupExpansionProvider = StateNotifierProvider.family<
    StepGroupExpansionNotifier, StepGroupExpansionState, String>(
  (ref, sessionId) {
    final notifier = StepGroupExpansionNotifier();
    ref.onDispose(() {
      notifier.clear();
    });
    return notifier;
  },
);

/// Alias matching family convention in PiFrame codebase.
final stepGroupExpansionFamily = stepGroupExpansionProvider;
