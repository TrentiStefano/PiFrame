import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daemon/daemon_providers.dart';
import '../daemon/pcp_client.dart';
import 'agents_config_model.dart';

@immutable
class AgentPendingEdit {
  final bool hasModelEdit;
  final String? model;
  final bool hasThinkingEdit;
  final String? thinking;
  final bool isThinkingAutoSet;
  final bool hasContextLimitEdit;
  final int? contextLimit;

  const AgentPendingEdit({
    this.hasModelEdit = false,
    this.model,
    this.hasThinkingEdit = false,
    this.thinking,
    this.isThinkingAutoSet = false,
    this.hasContextLimitEdit = false,
    this.contextLimit,
  });

  bool get isDirty => hasModelEdit || hasThinkingEdit || hasContextLimitEdit;

  AgentPendingEdit copyWith({
    bool? hasModelEdit,
    String? model,
    bool clearModel = false,
    bool? hasThinkingEdit,
    String? thinking,
    bool clearThinking = false,
    bool? isThinkingAutoSet,
    bool? hasContextLimitEdit,
    int? contextLimit,
    bool clearContextLimit = false,
  }) {
    return AgentPendingEdit(
      hasModelEdit: hasModelEdit ?? this.hasModelEdit,
      model: clearModel ? null : (model ?? this.model),
      hasThinkingEdit: hasThinkingEdit ?? this.hasThinkingEdit,
      thinking: clearThinking ? null : (thinking ?? this.thinking),
      isThinkingAutoSet: isThinkingAutoSet ?? this.isThinkingAutoSet,
      hasContextLimitEdit: hasContextLimitEdit ?? this.hasContextLimitEdit,
      contextLimit:
          clearContextLimit ? null : (contextLimit ?? this.contextLimit),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPendingEdit &&
          runtimeType == other.runtimeType &&
          hasModelEdit == other.hasModelEdit &&
          model == other.model &&
          hasThinkingEdit == other.hasThinkingEdit &&
          thinking == other.thinking &&
          isThinkingAutoSet == other.isThinkingAutoSet &&
          hasContextLimitEdit == other.hasContextLimitEdit &&
          contextLimit == other.contextLimit;

  @override
  int get hashCode => Object.hash(
        hasModelEdit,
        model,
        hasThinkingEdit,
        thinking,
        isThinkingAutoSet,
        hasContextLimitEdit,
        contextLimit,
      );
}

@immutable
class AgentsConfigState {
  final PiAgentsConfig? config;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool isReadOnlyRemote;
  final Map<String, String> validationErrors;

  // Session defaults edits
  final bool hasSessionDefaultModelEdit;
  final String? sessionDefaultModel;
  final bool hasSessionDefaultThinkingEdit;
  final String? sessionDefaultThinking;
  final bool isSessionDefaultThinkingAutoSet;

  // Subagent defaults edits
  final bool hasSubagentDefaultModelEdit;
  final String? subagentDefaultModel;
  final bool hasSubagentDefaultThinkingEdit;
  final String? subagentDefaultThinking;
  final bool isSubagentDefaultThinkingAutoSet;
  final bool hasSubagentDefaultFallbackAgentEdit;
  final String? subagentDefaultFallbackAgent;

  // Per agent edits: agentName -> AgentPendingEdit
  final Map<String, AgentPendingEdit> agentEdits;

  const AgentsConfigState({
    this.config,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.isReadOnlyRemote = false,
    this.validationErrors = const {},
    this.hasSessionDefaultModelEdit = false,
    this.sessionDefaultModel,
    this.hasSessionDefaultThinkingEdit = false,
    this.sessionDefaultThinking,
    this.isSessionDefaultThinkingAutoSet = false,
    this.hasSubagentDefaultModelEdit = false,
    this.subagentDefaultModel,
    this.hasSubagentDefaultThinkingEdit = false,
    this.subagentDefaultThinking,
    this.isSubagentDefaultThinkingAutoSet = false,
    this.hasSubagentDefaultFallbackAgentEdit = false,
    this.subagentDefaultFallbackAgent,
    this.agentEdits = const {},
  });

  bool get isDirty =>
      hasSessionDefaultModelEdit ||
      hasSessionDefaultThinkingEdit ||
      hasSubagentDefaultModelEdit ||
      hasSubagentDefaultThinkingEdit ||
      hasSubagentDefaultFallbackAgentEdit ||
      agentEdits.values.any((e) => e.isDirty);

  AgentsConfigState copyWith({
    PiAgentsConfig? config,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isReadOnlyRemote,
    Map<String, String>? validationErrors,
    bool? hasSessionDefaultModelEdit,
    String? sessionDefaultModel,
    bool clearSessionDefaultModel = false,
    bool? hasSessionDefaultThinkingEdit,
    String? sessionDefaultThinking,
    bool clearSessionDefaultThinking = false,
    bool? isSessionDefaultThinkingAutoSet,
    bool? hasSubagentDefaultModelEdit,
    String? subagentDefaultModel,
    bool clearSubagentDefaultModel = false,
    bool? hasSubagentDefaultThinkingEdit,
    String? subagentDefaultThinking,
    bool clearSubagentDefaultThinking = false,
    bool? isSubagentDefaultThinkingAutoSet,
    bool? hasSubagentDefaultFallbackAgentEdit,
    String? subagentDefaultFallbackAgent,
    bool clearSubagentDefaultFallbackAgent = false,
    Map<String, AgentPendingEdit>? agentEdits,
  }) {
    return AgentsConfigState(
      config: config ?? this.config,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isReadOnlyRemote: isReadOnlyRemote ?? this.isReadOnlyRemote,
      validationErrors: validationErrors ?? this.validationErrors,
      hasSessionDefaultModelEdit:
          hasSessionDefaultModelEdit ?? this.hasSessionDefaultModelEdit,
      sessionDefaultModel: clearSessionDefaultModel
          ? null
          : (sessionDefaultModel ?? this.sessionDefaultModel),
      hasSessionDefaultThinkingEdit:
          hasSessionDefaultThinkingEdit ?? this.hasSessionDefaultThinkingEdit,
      sessionDefaultThinking: clearSessionDefaultThinking
          ? null
          : (sessionDefaultThinking ?? this.sessionDefaultThinking),
      isSessionDefaultThinkingAutoSet: isSessionDefaultThinkingAutoSet ??
          this.isSessionDefaultThinkingAutoSet,
      hasSubagentDefaultModelEdit:
          hasSubagentDefaultModelEdit ?? this.hasSubagentDefaultModelEdit,
      subagentDefaultModel: clearSubagentDefaultModel
          ? null
          : (subagentDefaultModel ?? this.subagentDefaultModel),
      hasSubagentDefaultThinkingEdit:
          hasSubagentDefaultThinkingEdit ?? this.hasSubagentDefaultThinkingEdit,
      subagentDefaultThinking: clearSubagentDefaultThinking
          ? null
          : (subagentDefaultThinking ?? this.subagentDefaultThinking),
      isSubagentDefaultThinkingAutoSet: isSubagentDefaultThinkingAutoSet ??
          this.isSubagentDefaultThinkingAutoSet,
      hasSubagentDefaultFallbackAgentEdit:
          hasSubagentDefaultFallbackAgentEdit ??
              this.hasSubagentDefaultFallbackAgentEdit,
      subagentDefaultFallbackAgent: clearSubagentDefaultFallbackAgent
          ? null
          : (subagentDefaultFallbackAgent ??
              this.subagentDefaultFallbackAgent),
      agentEdits: agentEdits ?? this.agentEdits,
    );
  }

  String? getEffectiveSessionDefaultModel() {
    if (hasSessionDefaultModelEdit) return sessionDefaultModel;
    return config?.sessionDefaults.model;
  }

  String? getEffectiveSessionDefaultThinking() {
    if (hasSessionDefaultThinkingEdit) return sessionDefaultThinking;
    return config?.sessionDefaults.thinking;
  }

  String? getEffectiveSubagentDefaultModel() {
    if (hasSubagentDefaultModelEdit) return subagentDefaultModel;
    return config?.subagentDefaults.model;
  }

  String? getEffectiveSubagentDefaultThinking() {
    if (hasSubagentDefaultThinkingEdit) return subagentDefaultThinking;
    return config?.subagentDefaults.thinking;
  }

  String? getEffectiveSubagentDefaultFallbackAgent() {
    if (hasSubagentDefaultFallbackAgentEdit) return subagentDefaultFallbackAgent;
    return config?.subagentDefaults.fallbackAgent;
  }

  String? getEffectiveAgentModel(PiAgentInfo agent) {
    final edit = agentEdits[agent.name];
    if (edit?.hasModelEdit == true) return edit!.model;
    return agent.model.effective;
  }

  String getEffectiveAgentModelOrigin(PiAgentInfo agent) {
    final edit = agentEdits[agent.name];
    if (edit?.hasModelEdit == true) {
      return edit!.model == null ? 'default' : 'override';
    }
    return agent.model.origin;
  }

  String? getEffectiveAgentThinking(PiAgentInfo agent) {
    final edit = agentEdits[agent.name];
    if (edit?.hasThinkingEdit == true) return edit!.thinking;
    return agent.thinking.effective;
  }

  String getEffectiveAgentThinkingOrigin(PiAgentInfo agent) {
    final edit = agentEdits[agent.name];
    if (edit?.hasThinkingEdit == true) {
      return edit!.thinking == null ? 'default' : 'override';
    }
    return agent.thinking.origin;
  }

  int? getEffectiveAgentContextLimit(PiAgentInfo agent) {
    final edit = agentEdits[agent.name];
    if (edit?.hasContextLimitEdit == true) return edit!.contextLimit;
    return agent.context.limit;
  }

  String? getValidationError(String field, {String? agentName}) {
    if (agentName != null) {
      final compoundKey = '$agentName.$field';
      if (validationErrors.containsKey(compoundKey)) {
        return validationErrors[compoundKey];
      }
    }
    return validationErrors[field];
  }
}

class AgentsConfigController extends StateNotifier<AgentsConfigState> {
  final PcpClient? _client;

  AgentsConfigController(this._client) : super(const AgentsConfigState()) {
    if (_client != null) {
      load();
    }
  }

  Future<void> load({String? cwd}) async {
    if (_client == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Daemon not connected',
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      validationErrors: const {},
    );

    try {
      final config = await _client.getAgentsConfig(cwd: cwd);
      state = AgentsConfigState(
        config: config,
        isLoading: false,
        isReadOnlyRemote: false,
      );
    } on PcpException catch (e) {
      if (e.code == 'REMOTE_FORBIDDEN') {
        state = state.copyWith(
          isLoading: false,
          isReadOnlyRemote: true,
          errorMessage: e.message.isNotEmpty
              ? e.message
              : 'Remote access is read-only. pi.agents commands are local-only.',
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: e.message.isNotEmpty ? e.message : e.code,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> reload({String? cwd}) => load(cwd: cwd);

  void discardEdits() {
    state = state.copyWith(
      hasSessionDefaultModelEdit: false,
      clearSessionDefaultModel: true,
      hasSessionDefaultThinkingEdit: false,
      clearSessionDefaultThinking: true,
      isSessionDefaultThinkingAutoSet: false,
      hasSubagentDefaultModelEdit: false,
      clearSubagentDefaultModel: true,
      hasSubagentDefaultThinkingEdit: false,
      clearSubagentDefaultThinking: true,
      isSubagentDefaultThinkingAutoSet: false,
      hasSubagentDefaultFallbackAgentEdit: false,
      clearSubagentDefaultFallbackAgent: true,
      agentEdits: const {},
      validationErrors: const {},
      clearErrorMessage: true,
    );
  }

  PiAgentInfo? _findAgent(String name) {
    return state.config?.agents.cast<PiAgentInfo?>().firstWhere(
          (a) => a?.name == name,
          orElse: () => null,
        );
  }

  // Session Defaults Edits
  void editSessionDefaultModel(String? model) {
    final baselineModel = state.config?.sessionDefaults.model;
    final isModelEqualBaseline = model == baselineModel;

    final selectedModel = state.config?.availableModels
        .cast<PiAvailableModel?>()
        .firstWhere((m) => m?.id == model, orElse: () => null);

    bool nextHasThinkingEdit = state.hasSessionDefaultThinkingEdit;
    String? nextThinking = state.sessionDefaultThinking;
    bool nextIsThinkingAutoSet = state.isSessionDefaultThinkingAutoSet;

    if (selectedModel != null && !selectedModel.reasoning) {
      final baselineThinking = state.config?.sessionDefaults.thinking;
      final isThinkingDirty = baselineThinking != 'off';
      nextHasThinkingEdit = isThinkingDirty;
      nextThinking = isThinkingDirty ? 'off' : null;
      nextIsThinkingAutoSet = true;
    } else if (state.isSessionDefaultThinkingAutoSet) {
      nextHasThinkingEdit = false;
      nextThinking = null;
      nextIsThinkingAutoSet = false;
    }

    state = state.copyWith(
      hasSessionDefaultModelEdit: !isModelEqualBaseline,
      sessionDefaultModel: isModelEqualBaseline ? null : model,
      clearSessionDefaultModel: isModelEqualBaseline,
      hasSessionDefaultThinkingEdit: nextHasThinkingEdit,
      sessionDefaultThinking: nextThinking,
      clearSessionDefaultThinking: !nextHasThinkingEdit,
      isSessionDefaultThinkingAutoSet: nextIsThinkingAutoSet,
    );
  }

  void resetSessionDefaultModel() {
    final baselineModel = state.config?.sessionDefaults.model;
    if (baselineModel == null) {
      state = state.copyWith(
        hasSessionDefaultModelEdit: false,
        clearSessionDefaultModel: true,
        hasSessionDefaultThinkingEdit: state.isSessionDefaultThinkingAutoSet
            ? false
            : state.hasSessionDefaultThinkingEdit,
        clearSessionDefaultThinking: state.isSessionDefaultThinkingAutoSet,
        isSessionDefaultThinkingAutoSet: false,
      );
    } else {
      state = state.copyWith(
        hasSessionDefaultModelEdit: true,
        clearSessionDefaultModel: true,
        hasSessionDefaultThinkingEdit: state.isSessionDefaultThinkingAutoSet
            ? false
            : state.hasSessionDefaultThinkingEdit,
        clearSessionDefaultThinking: state.isSessionDefaultThinkingAutoSet,
        isSessionDefaultThinkingAutoSet: false,
      );
    }
  }

  void editSessionDefaultThinking(String? thinking) {
    final baselineThinking = state.config?.sessionDefaults.thinking;
    final isEqualBaseline = thinking == baselineThinking;
    state = state.copyWith(
      hasSessionDefaultThinkingEdit: !isEqualBaseline,
      sessionDefaultThinking: isEqualBaseline ? null : thinking,
      clearSessionDefaultThinking: isEqualBaseline,
      isSessionDefaultThinkingAutoSet: false,
    );
  }

  void resetSessionDefaultThinking() {
    final baselineThinking = state.config?.sessionDefaults.thinking;
    if (baselineThinking == null) {
      state = state.copyWith(
        hasSessionDefaultThinkingEdit: false,
        clearSessionDefaultThinking: true,
        isSessionDefaultThinkingAutoSet: false,
      );
    } else {
      state = state.copyWith(
        hasSessionDefaultThinkingEdit: true,
        clearSessionDefaultThinking: true,
        isSessionDefaultThinkingAutoSet: false,
      );
    }
  }

  // Subagent Defaults Edits
  void editSubagentDefaultModel(String? model) {
    final baselineModel = state.config?.subagentDefaults.model;
    final isModelEqualBaseline = model == baselineModel;

    final selectedModel = state.config?.availableModels
        .cast<PiAvailableModel?>()
        .firstWhere((m) => m?.id == model, orElse: () => null);

    bool nextHasThinkingEdit = state.hasSubagentDefaultThinkingEdit;
    String? nextThinking = state.subagentDefaultThinking;
    bool nextIsThinkingAutoSet = state.isSubagentDefaultThinkingAutoSet;

    if (selectedModel != null && !selectedModel.reasoning) {
      final baselineThinking = state.config?.subagentDefaults.thinking;
      final isThinkingDirty = baselineThinking != 'off';
      nextHasThinkingEdit = isThinkingDirty;
      nextThinking = isThinkingDirty ? 'off' : null;
      nextIsThinkingAutoSet = true;
    } else if (state.isSubagentDefaultThinkingAutoSet) {
      nextHasThinkingEdit = false;
      nextThinking = null;
      nextIsThinkingAutoSet = false;
    }

    state = state.copyWith(
      hasSubagentDefaultModelEdit: !isModelEqualBaseline,
      subagentDefaultModel: isModelEqualBaseline ? null : model,
      clearSubagentDefaultModel: isModelEqualBaseline,
      hasSubagentDefaultThinkingEdit: nextHasThinkingEdit,
      subagentDefaultThinking: nextThinking,
      clearSubagentDefaultThinking: !nextHasThinkingEdit,
      isSubagentDefaultThinkingAutoSet: nextIsThinkingAutoSet,
    );
  }

  void resetSubagentDefaultModel() {
    final baselineModel = state.config?.subagentDefaults.model;
    if (baselineModel == null) {
      state = state.copyWith(
        hasSubagentDefaultModelEdit: false,
        clearSubagentDefaultModel: true,
        hasSubagentDefaultThinkingEdit: state.isSubagentDefaultThinkingAutoSet
            ? false
            : state.hasSubagentDefaultThinkingEdit,
        clearSubagentDefaultThinking: state.isSubagentDefaultThinkingAutoSet,
        isSubagentDefaultThinkingAutoSet: false,
      );
    } else {
      state = state.copyWith(
        hasSubagentDefaultModelEdit: true,
        clearSubagentDefaultModel: true,
        hasSubagentDefaultThinkingEdit: state.isSubagentDefaultThinkingAutoSet
            ? false
            : state.hasSubagentDefaultThinkingEdit,
        clearSubagentDefaultThinking: state.isSubagentDefaultThinkingAutoSet,
        isSubagentDefaultThinkingAutoSet: false,
      );
    }
  }

  void editSubagentDefaultThinking(String? thinking) {
    final baselineThinking = state.config?.subagentDefaults.thinking;
    final isEqualBaseline = thinking == baselineThinking;
    state = state.copyWith(
      hasSubagentDefaultThinkingEdit: !isEqualBaseline,
      subagentDefaultThinking: isEqualBaseline ? null : thinking,
      clearSubagentDefaultThinking: isEqualBaseline,
      isSubagentDefaultThinkingAutoSet: false,
    );
  }

  void resetSubagentDefaultThinking() {
    final baselineThinking = state.config?.subagentDefaults.thinking;
    if (baselineThinking == null) {
      state = state.copyWith(
        hasSubagentDefaultThinkingEdit: false,
        clearSubagentDefaultThinking: true,
        isSubagentDefaultThinkingAutoSet: false,
      );
    } else {
      state = state.copyWith(
        hasSubagentDefaultThinkingEdit: true,
        clearSubagentDefaultThinking: true,
        isSubagentDefaultThinkingAutoSet: false,
      );
    }
  }

  void editSubagentDefaultFallbackAgent(String? fallbackAgent) {
    final baselineFallback = state.config?.subagentDefaults.fallbackAgent;
    final isEqualBaseline = fallbackAgent == baselineFallback;
    state = state.copyWith(
      hasSubagentDefaultFallbackAgentEdit: !isEqualBaseline,
      subagentDefaultFallbackAgent: isEqualBaseline ? null : fallbackAgent,
      clearSubagentDefaultFallbackAgent: isEqualBaseline,
    );
  }

  void resetSubagentDefaultFallbackAgent() {
    final baselineFallback = state.config?.subagentDefaults.fallbackAgent;
    if (baselineFallback == null) {
      state = state.copyWith(
        hasSubagentDefaultFallbackAgentEdit: false,
        clearSubagentDefaultFallbackAgent: true,
      );
    } else {
      state = state.copyWith(
        hasSubagentDefaultFallbackAgentEdit: true,
        clearSubagentDefaultFallbackAgent: true,
      );
    }
  }

  // Agent Edits
  void editAgentModel(String name, String? model) {
    final agent = _findAgent(name);
    final current = state.agentEdits[name] ?? const AgentPendingEdit();

    final baselineModel = agent?.model.effective;
    final isModelEqualBaseline = model == baselineModel;

    final selectedModel = state.config?.availableModels
        .cast<PiAvailableModel?>()
        .firstWhere((m) => m?.id == model, orElse: () => null);

    // Requirement 2: thinking
    bool nextHasThinkingEdit = current.hasThinkingEdit;
    String? nextThinking = current.thinking;
    bool nextIsThinkingAutoSet = current.isThinkingAutoSet;

    if (selectedModel != null && !selectedModel.reasoning) {
      final baselineThinking = agent?.thinking.effective;
      final isThinkingDirty = baselineThinking != 'off';
      nextHasThinkingEdit = isThinkingDirty;
      nextThinking = isThinkingDirty ? 'off' : null;
      nextIsThinkingAutoSet = true;
    } else if (current.isThinkingAutoSet) {
      nextHasThinkingEdit = false;
      nextThinking = null;
      nextIsThinkingAutoSet = false;
    }

    // Requirement 3: contextLimit
    // When an agent model changes: clear pending contextLimit;
    // if the agent had a stored limit and new model has no tiers, send contextLimit: null (removal) as part of the change
    bool nextHasContextLimitEdit = false;
    int? nextContextLimit;

    if (!isModelEqualBaseline) {
      final hasTiers = selectedModel != null && selectedModel.tiers.isNotEmpty;
      if (agent?.context.limit != null && !hasTiers) {
        nextHasContextLimitEdit = true;
        nextContextLimit = null;
      }
    }

    final updated = current.copyWith(
      hasModelEdit: !isModelEqualBaseline,
      model: isModelEqualBaseline ? null : model,
      clearModel: isModelEqualBaseline,
      hasThinkingEdit: nextHasThinkingEdit,
      thinking: nextThinking,
      clearThinking: !nextHasThinkingEdit,
      isThinkingAutoSet: nextIsThinkingAutoSet,
      hasContextLimitEdit: nextHasContextLimitEdit,
      contextLimit: nextContextLimit,
      clearContextLimit: !nextHasContextLimitEdit,
    );

    final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
    if (!updated.isDirty) {
      nextEdits.remove(name);
    } else {
      nextEdits[name] = updated;
    }
    state = state.copyWith(agentEdits: nextEdits);
  }

  void resetAgentModel(String name) {
    final agent = _findAgent(name);
    final current = state.agentEdits[name] ?? const AgentPendingEdit();

    if (agent == null || agent.model.origin != 'override') {
      // No override! Reset is a no-op / clears pending model edit
      final updated = current.copyWith(
        hasModelEdit: false,
        clearModel: true,
        hasThinkingEdit:
            current.isThinkingAutoSet ? false : current.hasThinkingEdit,
        clearThinking: current.isThinkingAutoSet,
        isThinkingAutoSet: false,
        hasContextLimitEdit: false,
        clearContextLimit: true,
      );
      final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
      if (!updated.isDirty) {
        nextEdits.remove(name);
      } else {
        nextEdits[name] = updated;
      }
      state = state.copyWith(agentEdits: nextEdits);
      return;
    }

    // Has override: reset sends model: null
    final updated = current.copyWith(
      hasModelEdit: true,
      clearModel: true,
      hasThinkingEdit:
          current.isThinkingAutoSet ? false : current.hasThinkingEdit,
      clearThinking: current.isThinkingAutoSet,
      isThinkingAutoSet: false,
      hasContextLimitEdit: false,
      clearContextLimit: true,
    );
    final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
    nextEdits[name] = updated;
    state = state.copyWith(agentEdits: nextEdits);
  }

  void editAgentThinking(String name, String? thinking) {
    final agent = _findAgent(name);
    final current = state.agentEdits[name] ?? const AgentPendingEdit();

    final baselineThinking = agent?.thinking.effective;
    final isEqualBaseline = thinking == baselineThinking;

    final updated = current.copyWith(
      hasThinkingEdit: !isEqualBaseline,
      thinking: isEqualBaseline ? null : thinking,
      clearThinking: isEqualBaseline,
      isThinkingAutoSet: false,
    );

    final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
    if (!updated.isDirty) {
      nextEdits.remove(name);
    } else {
      nextEdits[name] = updated;
    }
    state = state.copyWith(agentEdits: nextEdits);
  }

  void resetAgentThinking(String name) {
    final agent = _findAgent(name);
    final current = state.agentEdits[name] ?? const AgentPendingEdit();

    if (agent == null || agent.thinking.origin != 'override') {
      // No override! Reset is a no-op / clears pending thinking edit
      final updated = current.copyWith(
        hasThinkingEdit: false,
        clearThinking: true,
        isThinkingAutoSet: false,
      );
      final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
      if (!updated.isDirty) {
        nextEdits.remove(name);
      } else {
        nextEdits[name] = updated;
      }
      state = state.copyWith(agentEdits: nextEdits);
      return;
    }

    // Has override: reset sends thinking: null
    final updated = current.copyWith(
      hasThinkingEdit: true,
      clearThinking: true,
      isThinkingAutoSet: false,
    );
    final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
    nextEdits[name] = updated;
    state = state.copyWith(agentEdits: nextEdits);
  }

  void editAgentContextLimit(String name, int? contextLimit) {
    final agent = _findAgent(name);
    final current = state.agentEdits[name] ?? const AgentPendingEdit();

    final baselineLimit = agent?.context.limit;
    final isEqualBaseline = contextLimit == baselineLimit;

    final updated = current.copyWith(
      hasContextLimitEdit: !isEqualBaseline,
      contextLimit: isEqualBaseline ? null : contextLimit,
      clearContextLimit: isEqualBaseline,
    );

    final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
    if (!updated.isDirty) {
      nextEdits.remove(name);
    } else {
      nextEdits[name] = updated;
    }
    state = state.copyWith(agentEdits: nextEdits);
  }

  void resetAgentContextLimit(String name) {
    final agent = _findAgent(name);
    final current = state.agentEdits[name] ?? const AgentPendingEdit();

    if (agent == null || agent.context.limit == null) {
      // No stored limit! Reset is a no-op / clears pending edit
      final updated = current.copyWith(
        hasContextLimitEdit: false,
        clearContextLimit: true,
      );
      final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
      if (!updated.isDirty) {
        nextEdits.remove(name);
      } else {
        nextEdits[name] = updated;
      }
      state = state.copyWith(agentEdits: nextEdits);
      return;
    }

    // Had stored limit: reset sends contextLimit: null
    final updated = current.copyWith(
      hasContextLimitEdit: true,
      clearContextLimit: true,
    );
    final nextEdits = Map<String, AgentPendingEdit>.from(state.agentEdits);
    nextEdits[name] = updated;
    state = state.copyWith(agentEdits: nextEdits);
  }

  List<Map<String, dynamic>> buildChanges() {
    final changes = <Map<String, dynamic>>[];

    // Session Defaults
    if (state.hasSessionDefaultModelEdit ||
        state.hasSessionDefaultThinkingEdit) {
      final change = <String, dynamic>{'kind': 'sessionDefaults'};
      if (state.hasSessionDefaultModelEdit) {
        change['model'] = state.sessionDefaultModel;
      }
      if (state.hasSessionDefaultThinkingEdit) {
        change['thinking'] = state.sessionDefaultThinking;
      }
      changes.add(change);
    }

    // Subagent Defaults
    if (state.hasSubagentDefaultModelEdit ||
        state.hasSubagentDefaultThinkingEdit ||
        state.hasSubagentDefaultFallbackAgentEdit) {
      final change = <String, dynamic>{'kind': 'subagentDefaults'};
      if (state.hasSubagentDefaultModelEdit) {
        change['model'] = state.subagentDefaultModel;
      }
      if (state.hasSubagentDefaultThinkingEdit) {
        change['thinking'] = state.subagentDefaultThinking;
      }
      if (state.hasSubagentDefaultFallbackAgentEdit) {
        change['fallbackAgent'] = state.subagentDefaultFallbackAgent;
      }
      changes.add(change);
    }

    // Agent Edits
    for (final entry in state.agentEdits.entries) {
      final name = entry.key;
      final edit = entry.value;
      if (!edit.isDirty) continue;

      final change = <String, dynamic>{
        'kind': 'agent',
        'name': name,
      };
      if (edit.hasModelEdit) {
        change['model'] = edit.model;
      }
      if (edit.hasThinkingEdit) {
        change['thinking'] = edit.thinking;
      }
      if (edit.hasContextLimitEdit) {
        change['contextLimit'] = edit.contextLimit;
      }
      changes.add(change);
    }

    return changes;
  }

  Future<bool> save() async {
    if (!state.isDirty || state.isSaving || state.isLoading || _client == null) {
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearErrorMessage: true,
      validationErrors: const {},
    );

    final changes = buildChanges();

    try {
      final freshConfig = await _client.updateAgentsConfig(changes);
      state = AgentsConfigState(
        config: freshConfig,
        isLoading: false,
        isSaving: false,
        isReadOnlyRemote: false,
      );
      return true;
    } on PcpException catch (e) {
      if (e.code == 'REMOTE_FORBIDDEN') {
        state = state.copyWith(
          isSaving: false,
          isReadOnlyRemote: true,
          errorMessage: e.message.isNotEmpty
              ? e.message
              : 'Remote access is read-only. pi.agents update is local-only.',
        );
      } else if (e.code == 'AGENTS_VALIDATION_FAILED') {
        final errorMap = <String, String>{};
        for (final err in e.validationErrors) {
          final field = err['field']?.toString() ?? '';
          final message = err['message']?.toString() ?? 'Validation failed';
          if (field.isNotEmpty) {
            errorMap[field] = message;
          }
        }
        state = state.copyWith(
          isSaving: false,
          validationErrors: errorMap,
          errorMessage: e.message.isNotEmpty ? e.message : 'Validation failed',
        );
      } else {
        state = state.copyWith(
          isSaving: false,
          errorMessage: e.message.isNotEmpty ? e.message : e.code,
        );
      }
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
}

final agentsConfigControllerProvider =
    StateNotifierProvider<AgentsConfigController, AgentsConfigState>((ref) {
  final client = ref.watch(pcpClientProvider);
  return AgentsConfigController(client);
});
