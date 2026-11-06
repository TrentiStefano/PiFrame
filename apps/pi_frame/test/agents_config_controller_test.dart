import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/agents/agents_config_controller.dart';
import 'package:pi_frame/data/agents/agents_config_model.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';

class _FakeAgentsClient extends PcpClient {
  _FakeAgentsClient({
    this.initialConfig,
    this.updateError,
    this.getError,
  }) : super(port: 1, token: 'test');

  PiAgentsConfig? initialConfig;
  PcpException? updateError;
  PcpException? getError;

  List<Map>? lastChangesReceived;

  @override
  Future<PiAgentsConfig> getAgentsConfig({String? cwd}) async {
    if (getError != null) throw getError!;
    return initialConfig ?? const PiAgentsConfig();
  }

  @override
  Future<PiAgentsConfig> updateAgentsConfig(List<Map> changes) async {
    lastChangesReceived = changes;
    if (updateError != null) throw updateError!;
    return initialConfig ?? const PiAgentsConfig();
  }
}

PiAgentsConfig _createSampleConfig() {
  return PiAgentsConfig.fromJson({
    'packages': [
      {
        'id': 'pi-subagents',
        'version': '0.9.5',
        'installed': true,
        'configFile': '/path/settings.json',
      }
    ],
    'agents': [
      {
        'name': 'worker',
        'package': 'pi-subagents',
        'source': 'builtin',
        'description': 'Worker agent',
        'editable': true,
        'model': {
          'effective': 'anthropic/claude-3-5-sonnet',
          'origin': 'override',
          'available': true,
        },
        'thinking': {
          'effective': 'high',
          'origin': 'override',
        },
        'context': {
          'supported': true,
          'limit': 272000,
          'options': [272000, 1048576],
          'modelContextWindow': 1048576,
        },
      },
      {
        'name': 'oracle',
        'package': 'pi-subagents',
        'source': 'builtin',
        'description': 'Oracle agent',
        'editable': false,
        'readOnlyReason': 'external CLI runner',
        'model': {
          'effective': 'openai/gpt-4o',
          'origin': 'default',
          'available': true,
        },
        'thinking': {
          'effective': 'off',
          'origin': 'default',
        },
        'context': {
          'supported': false,
          'limit': null,
          'options': [],
          'modelContextWindow': null,
        },
      },
    ],
    'subagentDefaults': {
      'package': 'pi-subagents',
      'model': 'openai/gpt-4o',
      'thinking': 'medium',
      'modelAvailable': true,
      'fallbackAgent': null,
    },
    'sessionDefaults': {
      'provider': 'anthropic',
      'model': 'anthropic/claude-3-5-sonnet',
      'thinking': 'high',
      'modelAvailable': true,
    },
    'thinkingLevels': ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'],
    'availableModels': [
      {
        'id': 'anthropic/claude-3-5-sonnet',
        'name': 'Claude 3.5 Sonnet',
        'contextWindow': 1048576,
        'reasoning': true,
        'tiers': [272000, 1048576],
      },
      {
        'id': 'openai/gpt-4o',
        'name': 'GPT-4o',
        'contextWindow': 128000,
        'reasoning': false,
        'tiers': [],
      },
    ],
    'warnings': [],
  });
}

void main() {
  group('AgentsConfigController', () {
    test('load loads config from client and updates state', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);

      await controller.load();
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.config, isNotNull);
      expect(controller.state.config!.agents.length, 2);
      expect(controller.state.config!.agents.first.name, 'worker');
      expect(controller.state.isDirty, isFalse);
    });

    test('load handles REMOTE_FORBIDDEN error correctly', () async {
      final fake = _FakeAgentsClient(
        getError: PcpException('Forbidden', code: 'REMOTE_FORBIDDEN'),
      );
      final controller = AgentsConfigController(fake);

      await controller.load();
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isReadOnlyRemote, isTrue);
    });

    test('pending edits toggle dirty state and discardEdits restores clean state', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      expect(controller.state.isDirty, isFalse);

      // Edit session default model
      controller.editSessionDefaultModel('openai/gpt-4o');
      expect(controller.state.isDirty, isTrue);
      expect(controller.state.hasSessionDefaultModelEdit, isTrue);
      expect(controller.state.sessionDefaultModel, 'openai/gpt-4o');

      // Discard edits
      controller.discardEdits();
      expect(controller.state.isDirty, isFalse);
      expect(controller.state.hasSessionDefaultModelEdit, isFalse);

      // Edit agent model
      controller.editAgentModel('worker', 'openai/gpt-4o');
      expect(controller.state.isDirty, isTrue);
      expect(controller.state.agentEdits['worker']?.hasModelEdit, isTrue);
      expect(controller.state.agentEdits['worker']?.model, 'openai/gpt-4o');

      // Reset agent model (null sends null)
      controller.resetAgentModel('worker');
      expect(controller.state.isDirty, isTrue);
      expect(controller.state.agentEdits['worker']?.hasModelEdit, isTrue);
      expect(controller.state.agentEdits['worker']?.model, isNull);

      controller.discardEdits();
      expect(controller.state.isDirty, isFalse);
    });

    test('save sends ONLY changed fields', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      // Only change worker's thinking
      controller.editAgentThinking('worker', 'minimal');
      expect(controller.state.isDirty, isTrue);

      final ok = await controller.save();
      expect(ok, isTrue);
      expect(fake.lastChangesReceived, isNotNull);
      expect(fake.lastChangesReceived!.length, 1);

      final change = fake.lastChangesReceived!.first;
      expect(change['kind'], 'agent');
      expect(change['name'], 'worker');
      expect(change['thinking'], 'minimal');
      expect(change.containsKey('model'), isFalse);
      expect(change.containsKey('contextLimit'), isFalse);
    });

    test('save sends correct null for reset on agent field', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      // Reset worker model and context limit
      controller.resetAgentModel('worker');
      controller.resetAgentContextLimit('worker');

      final ok = await controller.save();
      expect(ok, isTrue);
      expect(fake.lastChangesReceived, isNotNull);
      expect(fake.lastChangesReceived!.length, 1);

      final change = fake.lastChangesReceived!.first;
      expect(change['kind'], 'agent');
      expect(change['name'], 'worker');
      expect(change['model'], isNull);
      expect(change['contextLimit'], isNull);
      expect(change.containsKey('thinking'), isFalse);
    });

    test('session default save sends sessionDefaults change', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      controller.editSessionDefaultModel('openai/gpt-4o');
      controller.editSessionDefaultThinking('low');

      final ok = await controller.save();
      expect(ok, isTrue);
      expect(fake.lastChangesReceived, isNotNull);
      expect(fake.lastChangesReceived!.length, 1);

      final change = fake.lastChangesReceived!.first;
      expect(change['kind'], 'sessionDefaults');
      expect(change['model'], 'openai/gpt-4o');
      expect(change['thinking'], 'low');
    });

    test('subagent default save sends subagentDefaults change', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      controller.editSubagentDefaultModel('anthropic/claude-3-5-sonnet');
      controller.resetSubagentDefaultThinking();

      final ok = await controller.save();
      expect(ok, isTrue);
      expect(fake.lastChangesReceived, isNotNull);
      expect(fake.lastChangesReceived!.length, 1);

      final change = fake.lastChangesReceived!.first;
      expect(change['kind'], 'subagentDefaults');
      expect(change['model'], 'anthropic/claude-3-5-sonnet');
      expect(change['thinking'], isNull);
    });

    test('validation error mapping maps errors per field', () async {
      final fake = _FakeAgentsClient(
        initialConfig: _createSampleConfig(),
        updateError: PcpException(
          'Agent settings validation failed',
          code: 'AGENTS_VALIDATION_FAILED',
          details: [
            {
              'field': 'model',
              'message': 'model not available with current credentials',
            },
            {
              'field': 'thinking',
              'message': 'Thinking level must be "off" for models without reasoning support',
            },
            {
              'field': 'contextLimit',
              'message': 'Context limit requires a model with pricing tiers',
            },
          ],
        ),
      );

      final controller = AgentsConfigController(fake);
      await controller.load();

      controller.editAgentModel('worker', 'unsupported/model');
      final ok = await controller.save();

      expect(ok, isFalse);
      expect(controller.state.validationErrors.length, 3);
      expect(
        controller.state.getValidationError('model'),
        'model not available with current credentials',
      );
      expect(
        controller.state.getValidationError('thinking'),
        'Thinking level must be "off" for models without reasoning support',
      );
      expect(
        controller.state.getValidationError('contextLimit'),
        'Context limit requires a model with pricing tiers',
      );
    });

    test('save returns false when not dirty', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      final ok = await controller.save();
      expect(ok, isFalse);
      expect(fake.lastChangesReceived, isNull);
    });

    test('revert-to-original -> not dirty & no change', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      // Session defaults: edit then revert
      controller.editSessionDefaultThinking('minimal');
      expect(controller.state.isDirty, isTrue);
      controller.editSessionDefaultThinking('high'); // baseline is 'high'
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);

      // Session defaults: setting same value as baseline is not dirty
      controller.editSessionDefaultModel('anthropic/claude-3-5-sonnet');
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);

      // Agent edit then revert to original
      controller.editAgentThinking('worker', 'minimal');
      expect(controller.state.isDirty, isTrue);
      controller.editAgentThinking('worker', 'high'); // baseline is 'high'
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);

      controller.editAgentContextLimit('worker', 1048576);
      expect(controller.state.isDirty, isTrue);
      controller.editAgentContextLimit('worker', 272000); // baseline is 272000
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);

      // Reset on a field that has no override (origin != 'override') is a no-op
      // Oracle has origin: 'default' for model, thinking, and limit is null
      controller.resetAgentModel('oracle');
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);

      controller.resetAgentThinking('oracle');
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);

      controller.resetAgentContextLimit('oracle');
      expect(controller.state.isDirty, isFalse);
      expect(controller.buildChanges(), isEmpty);
    });

    test('non-reasoning model -> thinking "off" (dirty only if differs from baseline)', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      // Session default: claude-3-5-sonnet (reasoning) -> gpt-4o (non-reasoning)
      // Baseline thinking was 'high' -> thinking becomes 'off' (dirty)
      controller.editSessionDefaultModel('openai/gpt-4o');
      expect(controller.state.hasSessionDefaultThinkingEdit, isTrue);
      expect(controller.state.sessionDefaultThinking, 'off');

      // Revert model -> auto-set thinking cleared, not dirty
      controller.editSessionDefaultModel('anthropic/claude-3-5-sonnet');
      expect(controller.state.hasSessionDefaultThinkingEdit, isFalse);
      expect(controller.state.isDirty, isFalse);

      // Subagent default: gpt-4o was baseline model, thinking was 'medium'
      // If we change subagent model to gpt-4o (which is same as baseline model),
      // model is clean, but let's test agent 'worker'
      // Worker baseline thinking is 'high'. Switch model to non-reasoning gpt-4o:
      controller.editAgentModel('worker', 'openai/gpt-4o');
      expect(controller.state.agentEdits['worker']?.hasThinkingEdit, isTrue);
      expect(controller.state.agentEdits['worker']?.thinking, 'off');

      // Revert worker model to baseline reasoning model -> auto-set thinking cleared and clean edit removed
      controller.editAgentModel('worker', 'anthropic/claude-3-5-sonnet');
      expect(controller.state.agentEdits['worker'], isNull);
      expect(controller.state.isDirty, isFalse);
    });

    test('agent model change resets context & sends contextLimit null when needed', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      // Worker agent originally has context.limit = 272000.
      // Changing worker model to openai/gpt-4o (no tiers):
      // Must send contextLimit: null (removal) so daemon config stays consistent!
      controller.editAgentModel('worker', 'openai/gpt-4o');
      expect(controller.state.agentEdits['worker']?.hasContextLimitEdit, isTrue);
      expect(controller.state.agentEdits['worker']?.contextLimit, isNull);

      final changes = controller.buildChanges();
      final workerChange = changes.firstWhere((c) => c['name'] == 'worker');
      expect(workerChange['model'], 'openai/gpt-4o');
      expect(workerChange['thinking'], 'off');
      expect(workerChange['contextLimit'], isNull);

      // Oracle agent had no stored limit (context.limit == null).
      // Changing oracle model to a model with tiers does NOT send contextLimit null
      controller.editAgentModel('oracle', 'anthropic/claude-3-5-sonnet');
      expect(controller.state.agentEdits['oracle']?.hasContextLimitEdit, isFalse);
    });

    test('save is blocked while loading', () async {
      final fake = _FakeAgentsClient(initialConfig: _createSampleConfig());
      final controller = AgentsConfigController(fake);
      await controller.load();

      controller.editSessionDefaultModel('openai/gpt-4o');
      expect(controller.state.isDirty, isTrue);

      // Set isLoading to true
      controller.state = controller.state.copyWith(isLoading: true);

      final ok = await controller.save();
      expect(ok, isFalse);
      expect(fake.lastChangesReceived, isNull);
    });
  });
}
