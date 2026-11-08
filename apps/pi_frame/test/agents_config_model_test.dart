import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/agents/agents_config_model.dart';
import 'package:pi_frame/features/settings/agents_section.dart';

void main() {
  group('PiAgentsConfig and models parsing', () {
    test('PiSubagentPackageInfo parses JSON correctly', () {
      final json = {
        'id': 'pi-subagents',
        'version': '0.9.5',
        'installed': true,
        'configFile': '/home/user/.pi/agent/settings.json',
      };
      final pkg = PiSubagentPackageInfo.fromJson(json);
      expect(pkg.id, 'pi-subagents');
      expect(pkg.version, '0.9.5');
      expect(pkg.installed, isTrue);
      expect(pkg.configFile, '/home/user/.pi/agent/settings.json');
      expect(pkg.toJson(), json);
    });

    test('PiSubagentPackageInfo handles missing or null fields tolerantly', () {
      final pkg = PiSubagentPackageInfo.fromJson({});
      expect(pkg.id, '');
      expect(pkg.version, isNull);
      expect(pkg.installed, isFalse);
      expect(pkg.configFile, '');
    });

    test('PiAgentModelInfo parses JSON correctly and tolerates nulls', () {
      final info = PiAgentModelInfo.fromJson({
        'effective': 'anthropic/claude-3-5-sonnet',
        'origin': 'override',
        'available': true,
      });
      expect(info.effective, 'anthropic/claude-3-5-sonnet');
      expect(info.origin, 'override');
      expect(info.available, isTrue);

      final empty = PiAgentModelInfo.fromJson({});
      expect(empty.effective, isNull);
      expect(empty.origin, 'none');
      expect(empty.available, isNull);
    });

    test('PiAgentThinkingInfo parses JSON correctly', () {
      final info = PiAgentThinkingInfo.fromJson({
        'effective': 'medium',
        'origin': 'frontmatter',
      });
      expect(info.effective, 'medium');
      expect(info.origin, 'frontmatter');

      final empty = PiAgentThinkingInfo.fromJson({});
      expect(empty.effective, isNull);
      expect(empty.origin, 'none');
    });

    test('PiAgentContextInfo parses JSON correctly', () {
      final info = PiAgentContextInfo.fromJson({
        'supported': true,
        'limit': 272000,
        'options': [272000, 1048576],
        'modelContextWindow': 1048576,
      });
      expect(info.supported, isTrue);
      expect(info.limit, 272000);
      expect(info.options, [272000, 1048576]);
      expect(info.modelContextWindow, 1048576);

      final empty = PiAgentContextInfo.fromJson({});
      expect(info.toJson()['supported'], isTrue);
      expect(empty.supported, isFalse);
      expect(empty.limit, isNull);
      expect(empty.options, isEmpty);
      expect(empty.modelContextWindow, isNull);
    });

    test('PiAgentInfo parses JSON completely and tolerantly', () {
      final json = {
        'name': 'worker',
        'package': 'pi-subagents',
        'source': 'builtin',
        'description': 'Executes implementation tasks',
        'editable': true,
        'readOnlyReason': null,
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
          'options': [272000, 1000000],
          'modelContextWindow': 1000000,
        },
      };

      final agent = PiAgentInfo.fromJson(json);
      expect(agent.name, 'worker');
      expect(agent.package, 'pi-subagents');
      expect(agent.source, 'builtin');
      expect(agent.description, 'Executes implementation tasks');
      expect(agent.editable, isTrue);
      expect(agent.readOnlyReason, isNull);
      expect(agent.model.effective, 'anthropic/claude-3-5-sonnet');
      expect(agent.model.origin, 'override');
      expect(agent.model.available, isTrue);
      expect(agent.thinking.effective, 'high');
      expect(agent.context.supported, isTrue);
      expect(agent.context.limit, 272000);

      // Tolerant fallback
      final empty = PiAgentInfo.fromJson({'name': 'minimal'});
      expect(empty.name, 'minimal');
      expect(empty.editable, isTrue);
      expect(empty.model.origin, 'none');
      expect(empty.thinking.origin, 'none');
      expect(empty.context.supported, isFalse);
    });

    test('PiSubagentDefaults parses JSON correctly', () {
      final defaults = PiSubagentDefaults.fromJson({
        'package': 'pi-subagents',
        'model': 'openai/gpt-4o',
        'thinking': 'medium',
        'modelAvailable': true,
        'fallbackAgent': null,
      });
      expect(defaults.package, 'pi-subagents');
      expect(defaults.model, 'openai/gpt-4o');
      expect(defaults.thinking, 'medium');
      expect(defaults.modelAvailable, isTrue);
      expect(defaults.fallbackAgent, isNull);

      final empty = PiSubagentDefaults.fromJson({});
      expect(empty.package, isNull);
      expect(empty.model, isNull);
    });

    test('PiSessionDefaults parses JSON correctly', () {
      final sess = PiSessionDefaults.fromJson({
        'provider': 'anthropic',
        'model': 'anthropic/claude-3-5-sonnet',
        'thinking': 'high',
        'modelAvailable': true,
      });
      expect(sess.provider, 'anthropic');
      expect(sess.model, 'anthropic/claude-3-5-sonnet');
      expect(sess.thinking, 'high');
      expect(sess.modelAvailable, isTrue);

      final empty = PiSessionDefaults.fromJson({});
      expect(empty.provider, isNull);
      expect(empty.model, isNull);
    });

    test('PiAvailableModel parses JSON correctly', () {
      final model = PiAvailableModel.fromJson({
        'id': 'anthropic/claude-3-5-sonnet',
        'name': 'Claude 3.5 Sonnet',
        'contextWindow': 1048576,
        'reasoning': true,
        'tiers': [272000, 500000, 1048576],
      });
      expect(model.id, 'anthropic/claude-3-5-sonnet');
      expect(model.name, 'Claude 3.5 Sonnet');
      expect(model.contextWindow, 1048576);
      expect(model.reasoning, isTrue);
      expect(model.tiers, [272000, 500000, 1048576]);
    });

    test('PiAgentsConfig parses full JSON payload tolerantly', () {
      final json = {
        'packages': [
          {
            'id': 'pi-subagents',
            'version': '0.9.5',
            'installed': true,
            'configFile': '/config',
          }
        ],
        'agents': [
          {
            'name': 'reviewer',
            'source': 'builtin',
            'editable': true,
            'model': {
              'effective': 'test/model',
              'origin': 'default',
              'available': true,
            },
            'thinking': {'effective': 'off', 'origin': 'default'},
            'context': {'supported': false, 'options': []},
          }
        ],
        'subagentDefaults': {
          'package': 'pi-subagents',
          'model': 'test/model',
          'thinking': 'off',
          'modelAvailable': true,
        },
        'sessionDefaults': {
          'provider': 'test',
          'model': 'test/model',
          'thinking': 'off',
          'modelAvailable': true,
        },
        'thinkingLevels': ['off', 'low', 'medium', 'high'],
        'availableModels': [
          {
            'id': 'test/model',
            'name': 'Test Model',
            'contextWindow': 200000,
            'reasoning': false,
            'tiers': [],
          }
        ],
        'warnings': ['Warning 1'],
      };

      final config = PiAgentsConfig.fromJson(json);
      expect(config.packages.length, 1);
      expect(config.packages.first.id, 'pi-subagents');
      expect(config.agents.length, 1);
      expect(config.agents.first.name, 'reviewer');
      expect(config.subagentDefaults.model, 'test/model');
      expect(config.sessionDefaults.model, 'test/model');
      expect(config.thinkingLevels, ['off', 'low', 'medium', 'high']);
      expect(config.availableModels.first.id, 'test/model');
      expect(config.warnings, ['Warning 1']);

      // Empty json returns valid empty config
      final empty = PiAgentsConfig.fromJson({});
      expect(empty.packages, isEmpty);
      expect(empty.agents, isEmpty);
      expect(empty.thinkingLevels, isEmpty);
      expect(empty.availableModels, isEmpty);
      expect(empty.warnings, isEmpty);
    });

    test('formatContextTier formats tiers and full window cleanly', () {
      expect(formatContextTier(272000, 1048576), '272k');
      expect(formatContextTier(1048576, 1048576), '1.05M (full)');
      expect(formatContextTier(2000000, 2000000), '2M (full)');
      expect(formatContextTier(500000, 1000000), '500k');
      expect(formatContextTier(1000000, 1000000), '1M (full)');
    });

    test('PiAgentInfo parses aliases tolerantly and serializes correctly', () {
      final withAliases = PiAgentInfo.fromJson({
        'name': 'advisor',
        'aliases': ['consultant', 'guide'],
      });
      expect(withAliases.aliases, ['consultant', 'guide']);
      expect(withAliases.toJson()['aliases'], ['consultant', 'guide']);

      final withTolerantAliases = PiAgentInfo.fromJson({
        'name': 'advisor',
        'aliases': [null, 42, 'guide', ''],
      });
      expect(withTolerantAliases.aliases, ['42', 'guide']);

      final withoutAliases = PiAgentInfo.fromJson({
        'name': 'advisor',
      });
      expect(withoutAliases.aliases, isEmpty);
      expect(withoutAliases.toJson().containsKey('aliases'), isFalse);

      final withNullAliases = PiAgentInfo.fromJson({
        'name': 'advisor',
        'aliases': null,
      });
      expect(withNullAliases.aliases, isEmpty);
    });
  });
}
