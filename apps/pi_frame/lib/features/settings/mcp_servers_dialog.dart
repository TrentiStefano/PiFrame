import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pi_frame_theme/pi_frame_theme.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_empty_state.dart';
import '../../ui/frame_icon_action.dart';
import '../../ui/frame_status_tag.dart';
import '../../ui/frame_snack_bar.dart';
import '../transcript/rich_content.dart';

class McpServerItem {
  final String name;
  final String scope;
  final String sourcePath;
  final bool enabled;
  final String transport;
  final String state;
  final List<String> tools;
  final String? description;
  final String? error;

  const McpServerItem({
    required this.name,
    this.scope = 'global',
    required this.sourcePath,
    this.enabled = true,
    this.transport = '',
    this.state = 'unknown',
    this.tools = const [],
    this.description,
    this.error,
  });

  McpServerItem copyWith({
    String? name,
    String? scope,
    String? sourcePath,
    bool? enabled,
    String? transport,
    String? state,
    List<String>? tools,
    String? description,
    String? error,
  }) {
    return McpServerItem(
      name: name ?? this.name,
      scope: scope ?? this.scope,
      sourcePath: sourcePath ?? this.sourcePath,
      enabled: enabled ?? this.enabled,
      transport: transport ?? this.transport,
      state: state ?? this.state,
      tools: tools ?? this.tools,
      description: description ?? this.description,
      error: error ?? this.error,
    );
  }
}

/// The MCP servers manager: a [FrameDialog] that lists the configured
/// servers, toggles them and shows what to do when there are none.
///
/// Opened from the Pi CLI section through [show]. The list and its state live
/// in [_McpServersBody], which is the dialog body.
class McpServersDialog extends StatelessWidget {
  final FrameTokens tokens;
  final String? projectDir;
  final List<McpServerItem>? initialServers;
  final AppStrings? strings;

  const McpServersDialog({
    super.key,
    required this.tokens,
    this.projectDir,
    this.initialServers,
    this.strings,
  });

  static Future<void> show(
    BuildContext context,
    FrameTokens tokens, {
    String? projectDir,
    List<McpServerItem>? initialServers,
    AppStrings? strings,
  }) {
    return showFrameDialog<void>(
      context: context,
      dialog: _buildDialog(
        context,
        tokens: tokens,
        projectDir: projectDir,
        initialServers: initialServers,
        strings: strings,
      ),
    );
  }

  static FrameDialog<void> _buildDialog(
    BuildContext context, {
    required FrameTokens tokens,
    String? projectDir,
    List<McpServerItem>? initialServers,
    AppStrings? strings,
  }) {
    final resolved = strings ?? _stringsFor(context);
    return FrameDialog<void>(
      title: resolved.mcpDialogTitle,
      body: _McpServersBody(
        tokens: tokens,
        projectDir: projectDir,
        initialServers: initialServers,
        strings: strings,
      ),
      // Passive close is a text button; there is no filled primary here.
      actions: [
        FrameDialogAction<void>(
          label: resolved.close,
          role: FrameDialogActionRole.cancel,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildDialog(
      context,
      tokens: tokens,
      projectDir: projectDir,
      initialServers: initialServers,
      strings: strings,
    );
  }
}

AppStrings _stringsFor(BuildContext context) {
  try {
    return ProviderScope.containerOf(context, listen: false)
        .read(appStringsProvider);
  } catch (_) {
    return const AppStrings(AppLanguage.it);
  }
}

class _McpServersBody extends StatefulWidget {
  final FrameTokens tokens;
  final String? projectDir;
  final List<McpServerItem>? initialServers;
  final AppStrings? strings;

  const _McpServersBody({
    required this.tokens,
    this.projectDir,
    this.initialServers,
    this.strings,
  });

  @override
  State<_McpServersBody> createState() => _McpServersBodyState();
}

class _McpServersBodyState extends State<_McpServersBody> {
  AppStrings get _strings {
    if (widget.strings != null) return widget.strings!;
    try {
      return ProviderScope.containerOf(context, listen: false).read(appStringsProvider);
    } catch (_) {
      return const AppStrings(AppLanguage.it);
    }
  }

  bool _isLoading = true;
  String? _errorMessage;
  List<McpServerItem> _servers = [];
  final Set<String> _togglingServers = {};
  final Set<String> _expandedTools = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialServers != null) {
      _servers = List.from(widget.initialServers!);
      _isLoading = false;
    } else {
      _loadServers();
    }
  }

  String _getGlobalMcpConfigPath() {
    if (kIsWeb) return '';
    final home = Platform.isWindows
        ? (Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '')
        : (Platform.environment['HOME'] ?? '');
    return p.join(home, '.pi', 'agent', 'mcp.json');
  }

  Future<void> _loadServers() async {
    // MCP configuration lives on the host machine: browsers can only report
    // the servers the daemon already exposes.
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _errorMessage = _strings.mcpDesktopOnly;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final globalPath = _getGlobalMcpConfigPath();
      final serversMap = <String, McpServerItem>{};

      // 1. Read global config file directly
      final globalFile = File(globalPath);
      if (await globalFile.exists()) {
        try {
          final content = await globalFile.readAsString();
          final parsed = jsonDecode(content);
          if (parsed is Map && parsed['mcpServers'] is Map) {
            final mcpServers = parsed['mcpServers'] as Map;
            for (final entry in mcpServers.entries) {
              final name = entry.key.toString();
              final conf = entry.value;
              if (conf is Map) {
                final isEnabled = conf['enabled'] != false && conf['disabled'] != true;
                final desc = conf['description']?.toString();
                final cmd = conf['command']?.toString() ?? conf['url']?.toString() ?? '';
                final args = conf['args'] is List
                    ? (conf['args'] as List).map((e) => e.toString()).join(' ')
                    : '';
                final transport = args.isNotEmpty ? '$cmd $args' : cmd;

                serversMap[name] = McpServerItem(
                  name: name,
                  scope: 'global',
                  sourcePath: globalPath,
                  enabled: isEnabled,
                  transport: transport,
                  state: isEnabled ? 'unknown' : 'disabled',
                  description: desc,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing $globalPath: $e');
        }
      }

      // 2. Read local project config if available
      if (widget.projectDir != null && widget.projectDir!.isNotEmpty) {
        final projectPath = p.join(widget.projectDir!, '.pi', 'mcp.json');
        final projectFile = File(projectPath);
        if (await projectFile.exists()) {
          try {
            final content = await projectFile.readAsString();
            final parsed = jsonDecode(content);
            if (parsed is Map && parsed['mcpServers'] is Map) {
              final mcpServers = parsed['mcpServers'] as Map;
              for (final entry in mcpServers.entries) {
                final name = entry.key.toString();
                final conf = entry.value;
                if (conf is Map) {
                  final isEnabled = conf['enabled'] != false && conf['disabled'] != true;
                  final desc = conf['description']?.toString();
                  final cmd = conf['command']?.toString() ?? conf['url']?.toString() ?? '';
                  final args = conf['args'] is List
                      ? (conf['args'] as List).map((e) => e.toString()).join(' ')
                      : '';
                  final transport = args.isNotEmpty ? '$cmd $args' : cmd;

                  // Project entry overrides global entry with same name
                  serversMap[name] = McpServerItem(
                    name: name,
                    scope: 'project',
                    sourcePath: projectPath,
                    enabled: isEnabled,
                    transport: transport.isNotEmpty ? transport : (serversMap[name]?.transport ?? ''),
                    state: isEnabled ? 'unknown' : 'disabled',
                    description: desc ?? serversMap[name]?.description,
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing $projectPath: $e');
          }
        }
      }

      // 3. Try to query live status from `pi mcp list --json`
      try {
        final result = Platform.isWindows
            ? await Process.run('cmd.exe', [
                '/c',
                'pi',
                'mcp',
                'list',
                '--json',
              ]).timeout(const Duration(seconds: 4))
            : await Process.run('pi', [
                'mcp',
                'list',
                '--json',
              ]).timeout(const Duration(seconds: 4));

        if (result.stdout != null) {
          final rawOutput = result.stdout.toString().trim();
          if (rawOutput.isNotEmpty) {
            final decoded = jsonDecode(rawOutput);
            if (decoded is Map && decoded['servers'] is List) {
              for (final item in decoded['servers'] as List) {
                if (item is Map) {
                  final name = item['name']?.toString() ?? '';
                  if (name.isEmpty) continue;

                  final enabled = item['enabled'] == true;
                  final state = item['state']?.toString() ?? (enabled ? 'connected' : 'disabled');
                  final transport = item['transport']?.toString() ?? '';
                  final source = item['source']?.toString() ?? globalPath;
                  final scope = item['scope']?.toString() ?? 'global';
                  final error = item['error']?.toString();

                  final toolsList = <String>[];
                  if (item['tools'] is List) {
                    for (final t in item['tools'] as List) {
                      toolsList.add(t.toString());
                    }
                  }

                  final existing = serversMap[name];
                  serversMap[name] = McpServerItem(
                    name: name,
                    scope: scope,
                    sourcePath: source,
                    enabled: enabled,
                    transport: transport.isNotEmpty ? transport : (existing?.transport ?? ''),
                    state: state,
                    tools: toolsList.isNotEmpty ? toolsList : (existing?.tools ?? const []),
                    description: existing?.description,
                    error: error,
                  );
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Note: pi mcp list --json unavailable: $e');
      }

      if (mounted) {
        setState(() {
          _servers = serversMap.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _strings.mcpLoadError(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleServer(McpServerItem server, bool newEnabled) async {
    setState(() {
      _togglingServers.add(server.name);
      final idx = _servers.indexWhere((s) => s.name == server.name);
      if (idx != -1) {
        _servers[idx] = _servers[idx].copyWith(
          enabled: newEnabled,
          state: newEnabled ? 'enabled' : 'disabled',
        );
      }
    });

    try {
      final file = File(server.sourcePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final parsed = jsonDecode(content);
        if (parsed is Map) {
          final mcpServers = (parsed['mcpServers'] as Map?) ?? <String, dynamic>{};
          if (mcpServers.containsKey(server.name)) {
            final conf = mcpServers[server.name];
            if (conf is Map) {
              conf['enabled'] = newEnabled;
              conf.remove('disabled');
            }
          } else {
            mcpServers[server.name] = <String, dynamic>{'enabled': newEnabled};
          }
          parsed['mcpServers'] = mcpServers;
          await file.writeAsString(const JsonEncoder.withIndent('  ').convert(parsed));
        }
      }
    } catch (e) {
      debugPrint('Error updating server ${server.name} in ${server.sourcePath}: $e');
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _strings.mcpSaveError(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingServers.remove(server.name);
        });
      }
    }
  }

  /// Opens the folder that holds the global MCP config, with the file selected.
  void _openConfigFile() {
    openInOsFileExplorer(_getGlobalMcpConfigPath());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final strings = _strings;
    final text = FrameText.of(context);
    final enabledCount = _servers.where((s) => s.enabled).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Neutral icon tile, subtitle and refresh share the top row.
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(FrameSpace.x2),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Icon(
                Icons.hub_outlined,
                size: FrameSize.iconLg,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(width: FrameSpace.x3),
            Expanded(
              child: Text(
                strings.mcpDialogSubtitle,
                style: text.body.copyWith(color: tokens.textSecondary),
              ),
            ),
            FrameIconAction(
              icon: Icons.refresh,
              tooltip: strings.mcpRefreshListTooltip,
              onPressed: _isLoading ? null : _loadServers,
            ),
          ],
        ),
        const SizedBox(height: FrameSpace.x3),

        // Height follows the content, with a 240 px floor.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 240),
          child: _buildContent(tokens, strings),
        ),

        const SizedBox(height: FrameSpace.x3),
        Text(
          _servers.isEmpty
              ? strings.mcpZeroServers
              : strings.mcpActiveServersCount(enabledCount, _servers.length),
          style: text.label.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }

  Widget _buildContent(FrameTokens tokens, AppStrings strings) {
    final text = FrameText.of(context);
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: FrameSize.iconLg,
              height: FrameSize.iconLg,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: FrameSpace.x3),
            Text(
              strings.mcpLoadingServers,
              style: text.body.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FrameSpace.x4),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: text.body.copyWith(color: tokens.danger),
          ),
        ),
      );
    }
    if (_servers.isEmpty) {
      return FrameEmptyState(
        keyPrefix: 'mcp-empty',
        icon: Icons.dns_outlined,
        title: strings.mcpEmptyTitle,
        message: strings.mcpEmptySubtitle,
        actionLabel: strings.mcpOpenConfigBtn,
        actionIcon: Icons.open_in_new,
        onAction: _openConfigFile,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _servers.length; i++) ...[
          if (i > 0) const SizedBox(height: FrameSpace.x2),
          _buildServerCard(tokens, _servers[i], strings),
        ],
      ],
    );
  }

  Widget _buildServerCard(
      FrameTokens tokens, McpServerItem server, AppStrings strings) {
    final text = FrameText.of(context);
    final isToggling = _togglingServers.contains(server.name);
    final isToolsExpanded = _expandedTools.contains(server.name);

    final statusLabel = !server.enabled
        ? strings.mcpStatusDisabled
        : server.state == 'connected'
            ? strings.mcpStatusConnected
            : server.state == 'failed'
                ? strings.mcpStatusFailed
                : strings.mcpStatusEnabled;

    return Container(
      decoration: BoxDecoration(
        color: server.enabled
            ? tokens.surface
            : tokens.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(
          color: server.enabled ? tokens.borderStrong : tokens.border,
          width: server.enabled ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x3,
              vertical: FrameSpace.x2 + FrameSpace.x1 / 2,
            ),
            child: Row(
              children: [
                // Checkbox to enable/disable
                SizedBox(
                  width: FrameSize.iconLg,
                  height: FrameSize.iconLg,
                  child: isToggling
                      ? Center(
                          child: SizedBox(
                            width: FrameSize.icon - 2,
                            height: FrameSize.icon - 2,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.accent,
                            ),
                          ),
                        )
                      : Checkbox(
                          key: ValueKey('mcp-checkbox-${server.name}'),
                          value: server.enabled,
                          activeColor: tokens.accent,
                          checkColor: tokens.surface,
                          side: BorderSide(
                              color: tokens.borderStrong, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              _toggleServer(server, val);
                            }
                          },
                        ),
                ),
                const SizedBox(width: FrameSpace.x2),

                // Name & badges
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          overflow: TextOverflow.ellipsis,
                          style: text.mono.copyWith(
                            color: server.enabled
                                ? tokens.textPrimary
                                : tokens.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: FrameSpace.x2),
                      FrameStatusTag(
                        label: statusLabel,
                        tone: _statusTone(server),
                      ),
                      if (server.scope == 'project') ...[
                        const SizedBox(width: FrameSpace.x2),
                        Text(
                          strings.mcpScopeProject,
                          style: text.caption.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Tool count chip, expands the tool list
                if (server.tools.isNotEmpty)
                  Tooltip(
                    message: isToolsExpanded
                        ? strings.mcpHideToolsTooltip
                        : strings.mcpShowToolsTooltip,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isToolsExpanded) {
                            _expandedTools.remove(server.name);
                          } else {
                            _expandedTools.add(server.name);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FrameSpace.x2 - 2,
                          vertical: FrameSpace.x1,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.build_outlined,
                                size: FrameSize.icon, color: tokens.textSecondary),
                            const SizedBox(width: FrameSpace.x1),
                            Text(
                              strings.mcpToolsCount(server.tools.length),
                              style: text.caption.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: FrameSpace.x1 / 2),
                            Icon(
                              isToolsExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: FrameSize.icon,
                              color: tokens.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Description if present
          if (server.description != null && server.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, FrameSpace.x3, FrameSpace.x2 - 2),
              child: Text(
                server.description!,
                style: text.caption.copyWith(color: tokens.textSecondary),
              ),
            ),

          // Transport snippet, with a copy action
          if (server.transport.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, FrameSpace.x3, FrameSpace.x2),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FrameSpace.x2,
                  vertical: FrameSpace.x1,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        server.transport,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption.copyWith(
                          color: tokens.textMuted,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ),
                    FrameIconAction(
                      icon: Icons.copy_outlined,
                      tooltip: strings.mcpCopyCommandTooltip,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: server.transport));
                        FrameSnackBar.show(
                          context,
                          message: strings.mcpCommandCopiedSnackBar,
                          duration: const Duration(seconds: 1),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Expandable tools list
          if (isToolsExpanded && server.tools.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(44, 0, FrameSpace.x3, FrameSpace.x2),
              padding: const EdgeInsets.all(FrameSpace.x2),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Wrap(
                spacing: FrameSpace.x2 - 2,
                runSpacing: FrameSpace.x1,
                children: [
                  for (final tool in server.tools)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FrameSpace.x2 - 2,
                        vertical: FrameSpace.x1 / 2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.syntaxFunction.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.syntaxFunction.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        tool,
                        style: text.caption.copyWith(
                          color: tokens.syntaxFunction,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Error text if present
          if (server.error != null && server.error!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, FrameSpace.x3, FrameSpace.x2),
              child: Text(
                server.error!,
                style: text.caption.copyWith(color: tokens.danger),
              ),
            ),
        ],
      ),
    );
  }

  /// Maps the server state onto a status tone. Only a failure is a danger.
  FrameStatusTone _statusTone(McpServerItem server) {
    if (!server.enabled) return FrameStatusTone.neutral;
    if (server.state == 'connected') return FrameStatusTone.success;
    if (server.state == 'failed') return FrameStatusTone.danger;
    return FrameStatusTone.info;
  }
}
