import 'package:flutter/foundation.dart';

@immutable
class PiSubagentPackageInfo {
  final String id;
  final String? version;
  final bool installed;
  final String configFile;

  const PiSubagentPackageInfo({
    required this.id,
    this.version,
    this.installed = false,
    this.configFile = '',
  });

  factory PiSubagentPackageInfo.fromJson(Map<String, dynamic> json) {
    return PiSubagentPackageInfo(
      id: json['id']?.toString() ?? '',
      version: json['version']?.toString(),
      installed: json['installed'] == true,
      configFile: json['configFile']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (version != null) 'version': version,
        'installed': installed,
        'configFile': configFile,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiSubagentPackageInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version &&
          installed == other.installed &&
          configFile == other.configFile;

  @override
  int get hashCode => Object.hash(id, version, installed, configFile);
}

@immutable
class PiAgentModelInfo {
  final String? effective;
  final String origin;
  final bool? available;

  const PiAgentModelInfo({
    this.effective,
    this.origin = 'none',
    this.available,
  });

  factory PiAgentModelInfo.fromJson(Map<String, dynamic> json) {
    return PiAgentModelInfo(
      effective: json['effective']?.toString(),
      origin: json['origin']?.toString() ?? 'none',
      available: json['available'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'effective': effective,
        'origin': origin,
        'available': available,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiAgentModelInfo &&
          runtimeType == other.runtimeType &&
          effective == other.effective &&
          origin == other.origin &&
          available == other.available;

  @override
  int get hashCode => Object.hash(effective, origin, available);
}

@immutable
class PiAgentThinkingInfo {
  final String? effective;
  final String origin;

  const PiAgentThinkingInfo({
    this.effective,
    this.origin = 'none',
  });

  factory PiAgentThinkingInfo.fromJson(Map<String, dynamic> json) {
    return PiAgentThinkingInfo(
      effective: json['effective']?.toString(),
      origin: json['origin']?.toString() ?? 'none',
    );
  }

  Map<String, dynamic> toJson() => {
        'effective': effective,
        'origin': origin,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiAgentThinkingInfo &&
          runtimeType == other.runtimeType &&
          effective == other.effective &&
          origin == other.origin;

  @override
  int get hashCode => Object.hash(effective, origin);
}

@immutable
class PiAgentContextInfo {
  final bool supported;
  final int? limit;
  final List<int> options;
  final int? modelContextWindow;

  const PiAgentContextInfo({
    this.supported = false,
    this.limit,
    this.options = const [],
    this.modelContextWindow,
  });

  factory PiAgentContextInfo.fromJson(Map<String, dynamic> json) {
    return PiAgentContextInfo(
      supported: json['supported'] == true,
      limit: (json['limit'] as num?)?.toInt(),
      options: (json['options'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      modelContextWindow: (json['modelContextWindow'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'limit': limit,
        'options': options,
        'modelContextWindow': modelContextWindow,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiAgentContextInfo &&
          runtimeType == other.runtimeType &&
          supported == other.supported &&
          limit == other.limit &&
          listEquals(options, other.options) &&
          modelContextWindow == other.modelContextWindow;

  @override
  int get hashCode =>
      Object.hash(supported, limit, Object.hashAll(options), modelContextWindow);
}

@immutable
class PiAgentInfo {
  final String name;
  final List<String> aliases;
  final String? package;
  final String source;
  final String? description;
  final bool editable;
  final String? readOnlyReason;
  final PiAgentModelInfo model;
  final PiAgentThinkingInfo thinking;
  final PiAgentContextInfo context;

  const PiAgentInfo({
    required this.name,
    this.aliases = const [],
    this.package,
    this.source = 'builtin',
    this.description,
    this.editable = true,
    this.readOnlyReason,
    this.model = const PiAgentModelInfo(),
    this.thinking = const PiAgentThinkingInfo(),
    this.context = const PiAgentContextInfo(),
  });

  factory PiAgentInfo.fromJson(Map<String, dynamic> json) {
    final rawAliases = json['aliases'];
    final aliases = (rawAliases is List)
        ? rawAliases
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : const <String>[];

    return PiAgentInfo(
      name: json['name']?.toString() ?? '',
      aliases: aliases,
      package: json['package']?.toString(),
      source: json['source']?.toString() ?? 'builtin',
      description: json['description']?.toString(),
      editable: json['editable'] != false,
      readOnlyReason: json['readOnlyReason']?.toString(),
      model: json['model'] is Map
          ? PiAgentModelInfo.fromJson(
              Map<String, dynamic>.from(json['model'] as Map))
          : const PiAgentModelInfo(),
      thinking: json['thinking'] is Map
          ? PiAgentThinkingInfo.fromJson(
              Map<String, dynamic>.from(json['thinking'] as Map))
          : const PiAgentThinkingInfo(),
      context: json['context'] is Map
          ? PiAgentContextInfo.fromJson(
              Map<String, dynamic>.from(json['context'] as Map))
          : const PiAgentContextInfo(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (aliases.isNotEmpty) 'aliases': aliases,
        if (package != null) 'package': package,
        'source': source,
        if (description != null) 'description': description,
        'editable': editable,
        if (readOnlyReason != null) 'readOnlyReason': readOnlyReason,
        'model': model.toJson(),
        'thinking': thinking.toJson(),
        'context': context.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiAgentInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          listEquals(aliases, other.aliases) &&
          package == other.package &&
          source == other.source &&
          description == other.description &&
          editable == other.editable &&
          readOnlyReason == other.readOnlyReason &&
          model == other.model &&
          thinking == other.thinking &&
          context == other.context;

  @override
  int get hashCode => Object.hash(
        name,
        Object.hashAll(aliases),
        package,
        source,
        description,
        editable,
        readOnlyReason,
        model,
        thinking,
        context,
      );
}

@immutable
class PiSubagentDefaults {
  final String? package;
  final String? model;
  final String? thinking;
  final bool? modelAvailable;
  final String? fallbackAgent;

  const PiSubagentDefaults({
    this.package,
    this.model,
    this.thinking,
    this.modelAvailable,
    this.fallbackAgent,
  });

  factory PiSubagentDefaults.fromJson(Map<String, dynamic> json) {
    return PiSubagentDefaults(
      package: json['package']?.toString(),
      model: json['model']?.toString(),
      thinking: json['thinking']?.toString(),
      modelAvailable: json['modelAvailable'] as bool?,
      fallbackAgent: json['fallbackAgent']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'package': package,
        'model': model,
        'thinking': thinking,
        'modelAvailable': modelAvailable,
        'fallbackAgent': fallbackAgent,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiSubagentDefaults &&
          runtimeType == other.runtimeType &&
          package == other.package &&
          model == other.model &&
          thinking == other.thinking &&
          modelAvailable == other.modelAvailable &&
          fallbackAgent == other.fallbackAgent;

  @override
  int get hashCode =>
      Object.hash(package, model, thinking, modelAvailable, fallbackAgent);
}

@immutable
class PiSessionDefaults {
  final String? provider;
  final String? model;
  final String? thinking;
  final bool? modelAvailable;

  const PiSessionDefaults({
    this.provider,
    this.model,
    this.thinking,
    this.modelAvailable,
  });

  factory PiSessionDefaults.fromJson(Map<String, dynamic> json) {
    return PiSessionDefaults(
      provider: json['provider']?.toString(),
      model: json['model']?.toString(),
      thinking: json['thinking']?.toString(),
      modelAvailable: json['modelAvailable'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'thinking': thinking,
        'modelAvailable': modelAvailable,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiSessionDefaults &&
          runtimeType == other.runtimeType &&
          provider == other.provider &&
          model == other.model &&
          thinking == other.thinking &&
          modelAvailable == other.modelAvailable;

  @override
  int get hashCode => Object.hash(provider, model, thinking, modelAvailable);
}

@immutable
class PiAvailableModel {
  final String id;
  final String name;
  final int contextWindow;
  final bool reasoning;
  final List<int> tiers;

  const PiAvailableModel({
    required this.id,
    required this.name,
    this.contextWindow = 0,
    this.reasoning = false,
    this.tiers = const [],
  });

  factory PiAvailableModel.fromJson(Map<String, dynamic> json) {
    return PiAvailableModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['id']?.toString() ?? '',
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 0,
      reasoning: json['reasoning'] == true,
      tiers: (json['tiers'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'contextWindow': contextWindow,
        'reasoning': reasoning,
        'tiers': tiers,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiAvailableModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          contextWindow == other.contextWindow &&
          reasoning == other.reasoning &&
          listEquals(tiers, other.tiers);

  @override
  int get hashCode =>
      Object.hash(id, name, contextWindow, reasoning, Object.hashAll(tiers));
}

@immutable
class PiAgentsConfig {
  final List<PiSubagentPackageInfo> packages;
  final List<PiAgentInfo> agents;
  final PiSubagentDefaults subagentDefaults;
  final PiSessionDefaults sessionDefaults;
  final List<String> thinkingLevels;
  final List<PiAvailableModel> availableModels;
  final List<String> warnings;

  const PiAgentsConfig({
    this.packages = const [],
    this.agents = const [],
    this.subagentDefaults = const PiSubagentDefaults(),
    this.sessionDefaults = const PiSessionDefaults(),
    this.thinkingLevels = const [],
    this.availableModels = const [],
    this.warnings = const [],
  });

  factory PiAgentsConfig.fromJson(Map<String, dynamic> json) {
    final pkgs = (json['packages'] as List?)
            ?.whereType<Map>()
            .map((e) =>
                PiSubagentPackageInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [];

    final ags = (json['agents'] as List?)
            ?.whereType<Map>()
            .map((e) => PiAgentInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [];

    final subDef = json['subagentDefaults'] is Map
        ? PiSubagentDefaults.fromJson(
            Map<String, dynamic>.from(json['subagentDefaults'] as Map))
        : const PiSubagentDefaults();

    final sessDef = json['sessionDefaults'] is Map
        ? PiSessionDefaults.fromJson(
            Map<String, dynamic>.from(json['sessionDefaults'] as Map))
        : const PiSessionDefaults();

    final think = (json['thinkingLevels'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final models = (json['availableModels'] as List?)
            ?.whereType<Map>()
            .map((e) =>
                PiAvailableModel.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [];

    final warns = (json['warnings'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return PiAgentsConfig(
      packages: pkgs,
      agents: ags,
      subagentDefaults: subDef,
      sessionDefaults: sessDef,
      thinkingLevels: think,
      availableModels: models,
      warnings: warns,
    );
  }

  Map<String, dynamic> toJson() => {
        'packages': packages.map((e) => e.toJson()).toList(),
        'agents': agents.map((e) => e.toJson()).toList(),
        'subagentDefaults': subagentDefaults.toJson(),
        'sessionDefaults': sessionDefaults.toJson(),
        'thinkingLevels': thinkingLevels,
        'availableModels': availableModels.map((e) => e.toJson()).toList(),
        'warnings': warnings,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiAgentsConfig &&
          runtimeType == other.runtimeType &&
          listEquals(packages, other.packages) &&
          listEquals(agents, other.agents) &&
          subagentDefaults == other.subagentDefaults &&
          sessionDefaults == other.sessionDefaults &&
          listEquals(thinkingLevels, other.thinkingLevels) &&
          listEquals(availableModels, other.availableModels) &&
          listEquals(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(packages),
        Object.hashAll(agents),
        subagentDefaults,
        sessionDefaults,
        Object.hashAll(thinkingLevels),
        Object.hashAll(availableModels),
        Object.hashAll(warnings),
      );
}
