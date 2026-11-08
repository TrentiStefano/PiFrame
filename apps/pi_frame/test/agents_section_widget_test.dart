import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/agents/agents_config_controller.dart';
import 'package:pi_frame/data/agents/agents_config_model.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/features/settings/agents_section.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _MockAgentsClient extends PcpClient {
  _MockAgentsClient({required this.config}) : super(port: 1, token: 'test');

  PiAgentsConfig config;
  List<Map>? lastUpdateChanges;

  @override
  Future<PiAgentsConfig> getAgentsConfig({String? cwd}) async {
    return config;
  }

  @override
  Future<PiAgentsConfig> updateAgentsConfig(List<Map> changes) async {
    lastUpdateChanges = changes;
    return config;
  }
}

void main() {
  Widget buildTestApp({
    required PcpClient client,
    AppLanguage language = AppLanguage.it,
  }) {
    return ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        pcpClientProvider.overrideWithValue(client),
        appStringsProvider.overrideWithValue(AppStrings(language)),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [FrameTokens.dark],
        ),
        home: const Scaffold(
          body: AgentsSection(),
        ),
      ),
    );
  }

  testWidgets(
      'renders real agents from fake result without hardcoded agent list',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeNames = ['custom-agent-alpha', 'custom-agent-beta', 'custom-agent-gamma'];
    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          version: '1.2.3',
          installed: true,
          configFile: '/config.json',
        ),
      ],
      agents: fakeNames.map((name) {
        return PiAgentInfo(
          name: name,
          package: 'pi-subagents',
          source: 'user',
          description: 'Description for $name',
          editable: true,
          model: const PiAgentModelInfo(
            effective: 'anthropic/claude-3-5-sonnet',
            origin: 'default',
            available: true,
          ),
          thinking: const PiAgentThinkingInfo(
            effective: 'medium',
            origin: 'default',
          ),
          context: const PiAgentContextInfo(
            supported: false,
          ),
        );
      }).toList(),
      availableModels: [
        const PiAvailableModel(
          id: 'anthropic/claude-3-5-sonnet',
          name: 'Claude 3.5 Sonnet',
          contextWindow: 200000,
          reasoning: true,
        ),
      ],
      thinkingLevels: ['off', 'low', 'medium', 'high'],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    // Verify each exact name from fake appears in the UI
    for (final name in fakeNames) {
      expect(find.text(name), findsOneWidget);
      expect(find.text('Description for $name'), findsOneWidget);
    }
  });

  testWidgets('displays unavailable model warning when model.available == false',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      agents: [
        const PiAgentInfo(
          name: 'restricted-agent',
          editable: true,
          model: PiAgentModelInfo(
            effective: 'uncredentialed/super-llm',
            origin: 'override',
            available: false,
          ),
        ),
      ],
      availableModels: [
        const PiAvailableModel(
          id: 'available/model',
          name: 'Available Model',
          contextWindow: 128000,
        ),
      ],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client, language: AppLanguage.en));
    await tester.pumpAndSettle();

    expect(find.text('restricted-agent'), findsOneWidget);
    expect(find.text('Not available with current credentials'), findsWidgets);
  });

  testWidgets(
      'context dropdown is shown only when supported, otherwise shows n/d with tooltip',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      agents: [
        const PiAgentInfo(
          name: 'context-tier-agent',
          editable: true,
          context: PiAgentContextInfo(
            supported: true,
            limit: 272000,
            options: [272000, 1048576],
            modelContextWindow: 1048576,
          ),
        ),
        const PiAgentInfo(
          name: 'single-tier-agent',
          editable: true,
          context: PiAgentContextInfo(
            supported: false,
          ),
        ),
      ],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client, language: AppLanguage.en));
    await tester.pumpAndSettle();

    expect(find.text('context-tier-agent'), findsOneWidget);
    expect(find.text('272k'), findsOneWidget);

    expect(find.text('single-tier-agent'), findsOneWidget);
    expect(find.text('N/A'), findsOneWidget);
    expect(
      find.byTooltip('Model has a single context tier'),
      findsOneWidget,
    );
  });

  testWidgets('read-only row is disabled and displays readOnlyReason tooltip',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      agents: [
        const PiAgentInfo(
          name: 'locked-agent',
          editable: false,
          readOnlyReason: 'external CLI runner',
          model: PiAgentModelInfo(
            effective: 'some/model',
            origin: 'frontmatter',
            available: true,
          ),
        ),
      ],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('locked-agent'), findsOneWidget);
    expect(find.byTooltip('external CLI runner'), findsWidgets);
  });

  testWidgets('session default save sends sessionDefaults change',
      (tester) async {
    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      sessionDefaults: const PiSessionDefaults(
        model: 'model-a',
        thinking: 'off',
      ),
      availableModels: [
        const PiAvailableModel(
          id: 'model-a',
          name: 'Model A',
          contextWindow: 100000,
          reasoning: true,
        ),
        const PiAvailableModel(
          id: 'model-b',
          name: 'Model B',
          contextWindow: 100000,
          reasoning: true,
        ),
      ],
      thinkingLevels: ['off', 'low', 'medium', 'high'],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    // Verify Save button is initially disabled
    final saveButtonFinder = find.widgetWithText(FilledButton, 'Salva modifiche');
    expect(tester.widget<FilledButton>(saveButtonFinder).enabled, isFalse);

    // Open session model dropdown and select Model B
    await tester.tap(find.text('Model A').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Model B').last);
    await tester.pumpAndSettle();

    // Save button should now be enabled
    expect(tester.widget<FilledButton>(saveButtonFinder).enabled, isTrue);

    // Tap Save button
    await tester.tap(saveButtonFinder);
    await tester.pumpAndSettle();

    // Verify client received sessionDefaults change
    expect(client.lastUpdateChanges, isNotNull);
    expect(client.lastUpdateChanges!.length, 1);
    expect(client.lastUpdateChanges!.first['kind'], 'sessionDefaults');
    expect(client.lastUpdateChanges!.first['model'], 'model-b');
  });

  testWidgets('shows empty state when no package is installed',
      (tester) async {
    final config = const PiAgentsConfig(
      packages: [],
      agents: [],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    expect(
      find.text('Nessun pacchetto di sottoagenti installato'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Installa un pacchetto di sottoagenti come pi-subagents'),
      findsOneWidget,
    );
  });

  testWidgets('context dropdown follows selected model tiers',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      agents: [
        const PiAgentInfo(
          name: 'worker',
          editable: true,
          model: PiAgentModelInfo(
            effective: 'model-a',
            origin: 'override',
            available: true,
          ),
          context: PiAgentContextInfo(
            supported: true,
            limit: 20000,
            options: [20000, 100000],
            modelContextWindow: 100000,
          ),
        ),
      ],
      availableModels: [
        const PiAvailableModel(
          id: 'model-a',
          name: 'Model A',
          contextWindow: 100000,
          reasoning: true,
          tiers: [20000, 100000],
        ),
        const PiAvailableModel(
          id: 'model-b',
          name: 'Model B',
          contextWindow: 50000,
          reasoning: false,
          tiers: [],
        ),
      ],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client, language: AppLanguage.en));
    await tester.pumpAndSettle();

    // Model A has tiers -> context tier 20k is shown
    expect(find.text('20k'), findsOneWidget);

    // Switch model to Model B (no tiers)
    await tester.tap(find.text('Model A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model B').last);
    await tester.pumpAndSettle();

    // Now context dropdown is replaced by N/A with single tier tooltip
    expect(find.text('N/A'), findsOneWidget);
    expect(find.byTooltip('Model has a single context tier'), findsOneWidget);
  });

  testWidgets('narrow layout at 480px width renders without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      agents: [
        const PiAgentInfo(
          name: 'worker',
          aliases: ['advisor', 'helper'],
          editable: true,
          model: PiAgentModelInfo(
            effective: 'model-a',
            origin: 'override',
            available: true,
          ),
          thinking: PiAgentThinkingInfo(
            effective: 'high',
            origin: 'override',
          ),
          context: PiAgentContextInfo(
            supported: true,
            limit: 20000,
            options: [20000, 100000],
            modelContextWindow: 100000,
          ),
        ),
      ],
      availableModels: [
        const PiAvailableModel(
          id: 'model-a',
          name: 'Model A',
          contextWindow: 100000,
          reasoning: true,
          tiers: [20000, 100000],
        ),
      ],
      thinkingLevels: ['off', 'low', 'medium', 'high'],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('worker'), findsOneWidget);
    expect(find.text('aliases: advisor, helper'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aliases parsed and shown in agent row', (tester) async {
    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      agents: [
        const PiAgentInfo(
          name: 'advisor-agent',
          aliases: ['advisor'],
          editable: true,
        ),
        const PiAgentInfo(
          name: 'multi-alias-agent',
          aliases: ['alpha', 'beta'],
          editable: true,
        ),
      ],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('alias: advisor'), findsOneWidget);
    expect(find.text('aliases: alpha, beta'), findsOneWidget);
  });

  testWidgets('save button is disabled while loading', (tester) async {
    final config = PiAgentsConfig(
      packages: [
        const PiSubagentPackageInfo(
          id: 'pi-subagents',
          installed: true,
        ),
      ],
      sessionDefaults: const PiSessionDefaults(
        model: 'model-a',
      ),
      availableModels: [
        const PiAvailableModel(
          id: 'model-a',
          name: 'Model A',
          contextWindow: 100000,
          reasoning: true,
        ),
        const PiAvailableModel(
          id: 'model-b',
          name: 'Model B',
          contextWindow: 100000,
          reasoning: true,
        ),
      ],
    );

    final client = _MockAgentsClient(config: config);
    await tester.pumpWidget(buildTestApp(client: client));
    await tester.pumpAndSettle();

    // Edit to make dirty
    await tester.tap(find.text('Model A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model B').last);
    await tester.pumpAndSettle();

    final saveButtonFinder = find.widgetWithText(FilledButton, 'Salva modifiche');
    expect(tester.widget<FilledButton>(saveButtonFinder).enabled, isTrue);

    // Set isLoading to true on controller
    final element = tester.element(find.byType(AgentsSection));
    final container = ProviderScope.containerOf(element);
    container.read(agentsConfigControllerProvider.notifier).state =
        container.read(agentsConfigControllerProvider).copyWith(isLoading: true);
    await tester.pump();

    // Now save button is disabled
    expect(tester.widget<FilledButton>(saveButtonFinder).enabled, isFalse);
  });
}
