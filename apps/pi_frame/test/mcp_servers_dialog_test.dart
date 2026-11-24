import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/data/platform/process_service.dart';
import 'package:pi_frame/features/settings/mcp_servers_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'support/fake_platform_services.dart';

void main() {
  group('McpServersDialog config files and pi CLI', () {
    final globalPath = p.join('/home/tester', '.pi', 'agent', 'mcp.json');
    final projectPath = p.join('/work/app', '.pi', 'mcp.json');

    late FakeFileSystemService files;
    late FakeProcessService processes;

    setUp(() {
      files = FakeFileSystemService();
      processes = FakeProcessService();
      files.files[globalPath] = jsonEncode({
        'mcpServers': {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
            'description': 'Official Dart server',
          },
        },
      });
      files.files[projectPath] = jsonEncode({
        'mcpServers': {
          'git': {'command': 'git-mcp', 'enabled': false},
        },
      });
    });

    Future<void> pumpDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileSystemServiceProvider.overrideWithValue(files),
            processServiceProvider.overrideWithValue(processes),
            hostEnvironmentServiceProvider.overrideWithValue(
              FakeHostEnvironmentService(variables: const {'HOME': '/home/tester'}),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: McpServersDialog(tokens: FrameTokens.dark, projectDir: '/work/app'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists servers from the global and project config files and asks pi for live status', (tester) async {
      processes.output = ProcessOutput(
        exitCode: 0,
        stdout: jsonEncode({
          'servers': [
            {
              'name': 'dart',
              'enabled': true,
              'state': 'connected',
              'transport': 'dart mcp-server',
              'tools': ['run_tests'],
            },
          ],
        }),
      );

      await pumpDialog(tester);

      expect(find.text('dart'), findsOneWidget);
      expect(find.text('git'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(processes.commands, contains('pi mcp list --json'));
    });

    testWidgets('unticking a server rewrites its entry in the config file it came from', (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.byKey(const ValueKey('mcp-checkbox-dart')));
      await tester.pumpAndSettle();

      final saved = jsonDecode(files.files[globalPath]!) as Map<String, dynamic>;
      final servers = saved['mcpServers'] as Map<String, dynamic>;
      expect((servers['dart'] as Map)['enabled'], isFalse);
      expect(servers['dart'] as Map, containsPair('command', 'dart'));
    });
  });

  group('McpServersDialog', () {
    testWidgets('renders server list with checkbox and badges', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const tokens = FrameTokens.dark;
      final testServers = [
        const McpServerItem(
          name: 'dart',
          scope: 'global',
          sourcePath: '/path/to/mcp.json',
          enabled: true,
          transport: 'dart mcp-server',
          state: 'connected',
          tools: ['run_tests', 'analyze_files'],
          description: 'Official Dart server',
        ),
        const McpServerItem(
          name: 'git',
          scope: 'project',
          sourcePath: '/project/.pi/mcp.json',
          enabled: false,
          transport: 'git-mcp',
          state: 'disabled',
          tools: [],
          description: 'Git integration',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileSystemServiceProvider.overrideWithValue(FakeFileSystemService()),
            processServiceProvider.overrideWithValue(FakeProcessService()),
            hostEnvironmentServiceProvider.overrideWithValue(FakeHostEnvironmentService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: McpServersDialog(tokens: tokens, initialServers: testServers),
            ),
          ),
        ),
      );

      await tester.pump();

      // Check title and servers
      expect(find.text('Available MCP Servers'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('git'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Project'), findsOneWidget);
      expect(find.text('1 of 2 servers active'), findsOneWidget);

      // Checkboxes exist for each server
      expect(find.byKey(const ValueKey('mcp-checkbox-dart')), findsOneWidget);
      expect(find.byKey(const ValueKey('mcp-checkbox-git')), findsOneWidget);

      final dartCheckbox = tester.widget<Checkbox>(find.byKey(const ValueKey('mcp-checkbox-dart')));
      expect(dartCheckbox.value, isTrue);

      final gitCheckbox = tester.widget<Checkbox>(find.byKey(const ValueKey('mcp-checkbox-git')));
      expect(gitCheckbox.value, isFalse);

      // Tap on tools chip for dart
      expect(find.text('2 tools'), findsOneWidget);
      await tester.tap(find.text('2 tools'));
      await tester.pump();

      expect(find.text('run_tests'), findsOneWidget);
      expect(find.text('analyze_files'), findsOneWidget);
    });
  });
}
