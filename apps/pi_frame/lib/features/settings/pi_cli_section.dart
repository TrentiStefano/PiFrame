import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../data/platform/platform_environment.dart';

import 'mcp_servers_dialog.dart';
import '../../ui/frame_section.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/frame_status_tag.dart';
import 'sections/settings_common.dart';

class PiCommandItem {
  final String label;
  final String command;
  final List<String> args;
  final String description;
  final IconData icon;
  final bool isPrimary;

  const PiCommandItem({
    required this.label,
    required this.command,
    required this.args,
    required this.description,
    required this.icon,
    this.isPrimary = false,
  });
}

List<PiCommandItem> get kBuiltinPiCommands =>
    getBuiltinPiCommands(const AppStrings(AppLanguage.it));

List<PiCommandItem> getBuiltinPiCommands(AppStrings strings) => [
  PiCommandItem(
    label: strings.piCmdUpdateCliLabel,
    command: 'pi update',
    args: ['update'],
    description: strings.piCmdUpdateCliDesc,
    icon: Icons.system_update_alt,
    isPrimary: true,
  ),
  PiCommandItem(
    label: strings.piCmdUpdateExtLabel,
    command: 'pi update --extensions',
    args: ['update', '--extensions'],
    description: strings.piCmdUpdateExtDesc,
    icon: Icons.extension_outlined,
    isPrimary: true,
  ),
  PiCommandItem(
    label: strings.piCmdUpdateModelsLabel,
    command: 'pi update --models',
    args: ['update', '--models'],
    description: strings.piCmdUpdateModelsDesc,
    icon: Icons.psychology_outlined,
  ),
  PiCommandItem(
    label: strings.piCmdUpdateAllLabel,
    command: 'pi update --all',
    args: ['update', '--all'],
    description: strings.piCmdUpdateAllDesc,
    icon: Icons.auto_awesome,
  ),
  PiCommandItem(
    label: strings.piCmdListLabel,
    command: 'pi list',
    args: ['list'],
    description: strings.piCmdListDesc,
    icon: Icons.list_alt,
  ),
  PiCommandItem(
    label: strings.piCmdMcpListLabel,
    command: 'pi mcp list',
    args: ['mcp', 'list'],
    description: strings.piCmdMcpListDesc,
    icon: Icons.hub_outlined,
  ),
  PiCommandItem(
    label: strings.piCmdModelsLabel,
    command: 'pi --list-models',
    args: ['--list-models'],
    description: strings.piCmdModelsDesc,
    icon: Icons.view_list_outlined,
  ),
  PiCommandItem(
    label: strings.piCmdVersionLabel,
    command: 'pi --version',
    args: ['--version'],
    description: strings.piCmdVersionDesc,
    icon: Icons.info_outline,
  ),
];

class PiCliSection extends StatefulWidget {
  final FrameTokens tokens;
  final VoidCallback? onRecheck;
  final AppStrings? strings;
  final Future<void> Function()? onPackagesChanged;

  const PiCliSection({
    super.key,
    required this.tokens,
    this.onRecheck,
    this.strings,
    this.onPackagesChanged,
  });

  @override
  State<PiCliSection> createState() => _PiCliSectionState();
}

class _PiCliSectionState extends State<PiCliSection> {
  AppStrings get _strings {
    if (widget.strings != null) return widget.strings!;
    try {
      return ProviderScope.containerOf(context, listen: false).read(appStringsProvider);
    } catch (_) {
      return const AppStrings(AppLanguage.it);
    }
  }

  final TextEditingController _customCmdController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  bool _isExecuting = false;
  String? _currentCommand;
  String _consoleOutput = '';
  int? _exitCode;
  DateTime? _startTime;
  Duration? _executionDuration;
  Process? _activeProcess;

  @override
  void dispose() {
    _customCmdController.dispose();
    _logScrollController.dispose();
    _activeProcess?.kill();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _executeCommand(String displayCmd, List<String> args) async {
    if (_isExecuting) return;
    // Shell commands run on the host only; the browser cannot spawn processes.
    if (kIsWeb) {
      setState(() {
        _consoleOutput = _strings.piCliDesktopOnly;
        _exitCode = -1;
      });
      return;
    }

    setState(() {
      _isExecuting = true;
      _currentCommand = displayCmd;
      _consoleOutput = '\$ $displayCmd\n';
      _exitCode = null;
      _startTime = DateTime.now();
      _executionDuration = null;
    });

    try {
      final Process process;
      final piExe = PlatformEnvironment.findExecutable('pi');
      if (Platform.isWindows) {
        process = await Process.start(
          'cmd.exe',
          ['/c', piExe ?? 'pi', ...args],
          environment: PlatformEnvironment.environment,
          runInShell: true,
        );
      } else {
        if (piExe != null) {
          process = await Process.start(
            piExe,
            args,
            environment: PlatformEnvironment.environment,
            runInShell: false,
          );
        } else {
          process = await Process.start(
            'pi',
            args,
            environment: PlatformEnvironment.environment,
            runInShell: true,
          );
        }
      }

      _activeProcess = process;

      final stdoutDone = process.stdout.transform(utf8.decoder).forEach((data) {
        if (!mounted) return;
        setState(() {
          _consoleOutput += data;
        });
        _scrollToBottom();
      });

      final stderrDone = process.stderr.transform(utf8.decoder).forEach((data) {
        if (!mounted) return;
        setState(() {
          _consoleOutput += data;
        });
        _scrollToBottom();
      });

      final code = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);

      if (!mounted) return;
      final duration = _startTime != null
          ? DateTime.now().difference(_startTime!)
          : null;

      setState(() {
        _exitCode = code;
        _isExecuting = false;
        _activeProcess = null;
        _executionDuration = duration;
        _consoleOutput += _strings.piCliProcessCompleted(
          code,
          duration?.inMilliseconds ?? 0,
        );
      });
      _scrollToBottom();
      if (args.isNotEmpty &&
          const {'install', 'update', 'remove'}.contains(args.first)) {
        await widget.onPackagesChanged?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _activeProcess = null;
        _exitCode = -1;
        _consoleOutput += _strings.piCliExecutionError(e);
      });
      _scrollToBottom();
    }
  }

  void _runCustomCommand() {
    final raw = _customCmdController.text.trim();
    if (raw.isEmpty) return;

    final parts = raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;

    final display = 'pi $raw';
    _executeCommand(display, parts);
  }

  void _copyConsoleOutput() {
    if (_consoleOutput.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _consoleOutput));
    FrameSnackBar.show(
      context,
      message: _strings.piCliOutputCopiedSnackBar,
      duration: const Duration(seconds: 2),
    );
  }

  void _clearConsoleOutput() {
    setState(() {
      _consoleOutput = '';
      _currentCommand = null;
      _exitCode = null;
      _executionDuration = null;
    });
  }

  void _cancelActiveProcess() {
    if (_activeProcess != null) {
      _activeProcess!.kill();
      setState(() {
        _consoleOutput += _strings.piCliCommandCancelled;
        _isExecuting = false;
        _activeProcess = null;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final strings = _strings;
    final text = FrameText.of(context);
    final commands = getBuiltinPiCommands(strings);

    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        Row(
          children: [
            Icon(Icons.terminal, color: tokens.accent, size: FrameSize.iconLg),
            const SizedBox(width: FrameSpace.x3),
            Text(
              strings.piCliTitle,
              style: text.title.copyWith(color: tokens.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: FrameSpace.x1),
        Text(
          strings.piCliSubtitle,
          style: text.body.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: FrameSpace.x6),

        FrameSection(
          title: strings.piCliFastCommands,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cmd in commands) _buildActionRow(tokens, cmd, strings),
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x6),

        FrameSection(
          title: strings.piCliCustomCmdHeader,
          child: Row(
            children: [
              Expanded(
                child: buildSettingsFieldBox(
                  tokens,
                  Row(
                    children: [
                      Text(
                        'pi ',
                        style: text.mono.copyWith(
                          color: tokens.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('pi-cli-custom-command-field'),
                          controller: _customCmdController,
                          enabled: !_isExecuting,
                          style: text.mono.copyWith(color: tokens.textPrimary),
                          decoration: InputDecoration(
                            hintText: strings.piCliCustomCmdHint,
                            hintStyle: text.caption.copyWith(
                              color: tokens.textMuted,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _runCustomCommand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: FrameSpace.x2),
              SizedBox(
                height: FrameSize.rowForm,
                child: FilledButton.icon(
                  key: const ValueKey('pi-cli-custom-run-btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: FrameSpace.x4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  onPressed: _isExecuting ? null : _runCustomCommand,
                  icon: const Icon(Icons.play_arrow, size: FrameSize.icon),
                  label: Text(strings.piCliRunBtn),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x6),

        FrameSection(
          title: strings.piCliConsoleOutputHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConsoleToolbar(tokens, text, strings),
              const SizedBox(height: FrameSpace.x2),
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: tokens.chassis,
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                  border: Border.all(color: tokens.borderStrong),
                ),
                child: _consoleOutput.isEmpty && !_isExecuting
                    ? Center(
                        child: Text(
                          strings.piCliEmptyOutput,
                          style: text.caption.copyWith(color: tokens.textMuted),
                        ),
                      )
                    : Scrollbar(
                        controller: _logScrollController,
                        child: SingleChildScrollView(
                          controller: _logScrollController,
                          padding: const EdgeInsets.all(FrameSpace.x3),
                          child: SelectableText(
                            _consoleOutput,
                            style: text.mono.copyWith(
                              color: tokens.displayText,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x6),

        // System verification footer: flat, no second border level.
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: FrameSize.icon,
              color: tokens.success,
            ),
            const SizedBox(width: FrameSpace.x3),
            Expanded(
              child: Text(
                strings.piCliSystemPathNotice,
                style: text.caption.copyWith(color: tokens.textMuted),
              ),
            ),
            if (widget.onRecheck != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, FrameSize.rowForm),
                ),
                onPressed: widget.onRecheck,
                child: Text(strings.piCliRecheckBtn),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildConsoleToolbar(
    FrameTokens tokens,
    FrameText text,
    AppStrings strings,
  ) {
    return Row(
      children: [
        if (_isExecuting) ...[
          SizedBox(
            width: FrameSize.icon - FrameSpace.x1,
            height: FrameSize.icon - FrameSpace.x1,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: FrameSpace.x2),
          Flexible(
            child: Text(
              strings.piCliRunningNotice(_currentCommand ?? ''),
              overflow: TextOverflow.ellipsis,
              style: text.caption.copyWith(color: tokens.accent),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: tokens.danger),
            onPressed: _cancelActiveProcess,
            icon: const Icon(Icons.stop, size: FrameSize.icon),
            label: Text(strings.piCliStopBtn),
          ),
        ] else ...[
          if (_exitCode != null)
            FrameStatusTag(
              key: const ValueKey('pi-cli-exit-status'),
              label: _exitCode == 0
                  ? strings.piCliSuccessCode
                  : strings.piCliExitCode(_exitCode!),
              tone: _exitCode == 0
                  ? FrameStatusTone.success
                  : FrameStatusTone.danger,
            ),
          if (_executionDuration != null) ...[
            const SizedBox(width: FrameSpace.x2),
            Text(
              '${(_executionDuration!.inMilliseconds / 1000).toStringAsFixed(2)}s',
              style: text.caption.copyWith(color: tokens.textMuted),
            ),
          ],
          const Spacer(),
        ],
        if (_consoleOutput.isNotEmpty) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: strings.piCliCopyOutputTooltip,
            icon: const Icon(Icons.copy, size: FrameSize.icon),
            onPressed: _copyConsoleOutput,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: strings.piCliClearOutputTooltip,
            icon: const Icon(Icons.clear_all, size: FrameSize.iconLg),
            onPressed: _clearConsoleOutput,
          ),
        ],
      ],
    );
  }

  Widget _buildActionRow(
    FrameTokens tokens,
    PiCommandItem item,
    AppStrings strings,
  ) {
    final text = FrameText.of(context);
    final isRunning = _currentCommand == item.command && _isExecuting;
    final isMcpRow = item.command == 'pi mcp list';

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: FrameSpace.x2),
      child: Row(
        children: [
          Icon(item.icon, size: FrameSize.icon, color: tokens.textSecondary),
          const SizedBox(width: FrameSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: text.label.copyWith(color: tokens.textPrimary),
                ),
                Text(
                  item.command,
                  style: text.mono.copyWith(color: tokens.textMuted),
                ),
                Text(
                  item.description,
                  style: text.caption.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: FrameSpace.x2),
          if (isMcpRow) ...[
            OutlinedButton(
              key: const ValueKey('btn-manage-mcp-servers'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textPrimary,
                side: BorderSide(color: tokens.borderStrong),
                minimumSize: const Size(0, FrameSize.hitMin),
              ),
              onPressed: () => McpServersDialog.show(
                context,
                tokens,
                strings: strings,
              ),
              child: Text(strings.piCliManageMcpBtn),
            ),
            const SizedBox(width: FrameSpace.x2),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: item.isPrimary
                  ? tokens.accent
                  : tokens.surfaceElevated,
              foregroundColor: item.isPrimary
                  ? tokens.surface
                  : tokens.textPrimary,
              minimumSize: const Size(0, FrameSize.hitMin),
            ),
            onPressed: _isExecuting
                ? null
                : () => _executeCommand(item.command, item.args),
            icon: isRunning
                ? SizedBox(
                    width: FrameSize.icon,
                    height: FrameSize.icon,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: item.isPrimary ? tokens.surface : tokens.accent,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: FrameSize.icon),
            label: Text(isRunning ? strings.piCliInProgress : strings.piCliRunBtn),
          ),
        ],
      ),
    );

    if (isMcpRow) {
      return Material(
        key: const ValueKey('pi-cli-card-pi-mcp-list'),
        type: MaterialType.transparency,
        child: Tooltip(
          message: strings.piCliMcpCardTooltip,
          child: InkWell(
            onTap: () => McpServersDialog.show(
              context,
              tokens,
              strings: strings,
            ),
            child: row,
          ),
        ),
      );
    }

    return row;
  }
}
