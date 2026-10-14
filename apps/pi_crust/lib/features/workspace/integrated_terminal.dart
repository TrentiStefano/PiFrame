import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:xterm/xterm.dart';

class TerminalTabSession {
  final String id;
  String title;
  final String shellName;
  final Terminal terminal;
  Process? process;
  bool isRunning = false;
  int? exitCode;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  TerminalTabSession({
    required this.id,
    required this.title,
    required this.shellName,
    required this.terminal,
  });

  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    try {
      process?.kill();
    } catch (_) {}
  }
}

class IntegratedTerminalPanel extends StatefulWidget {
  final String cwd;
  final CrustTokens tokens;
  final VoidCallback onCollapseDownward;
  final VoidCallback onClose;

  const IntegratedTerminalPanel({
    super.key,
    required this.cwd,
    required this.tokens,
    required this.onCollapseDownward,
    required this.onClose,
  });

  @override
  State<IntegratedTerminalPanel> createState() =>
      _IntegratedTerminalPanelState();
}

class _IntegratedTerminalPanelState extends State<IntegratedTerminalPanel> {
  final List<TerminalTabSession> _tabs = [];
  int _activeTabIndex = 0;
  int _counter = 0;

  final TextEditingController _cmdInputController = TextEditingController();
  final FocusNode _cmdFocusNode = FocusNode();
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _createNewTab();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    _cmdInputController.dispose();
    _cmdFocusNode.dispose();
    super.dispose();
  }

  TerminalTheme _buildTerminalTheme(CrustTokens tokens) {
    return TerminalTheme(
      cursor: tokens.accent,
      selection: tokens.accent.withValues(alpha: 0.35),
      foreground: tokens.displayText,
      background: tokens.chassis,
      black: tokens.surface,
      white: tokens.displayText,
      red: tokens.danger,
      green: tokens.success,
      yellow: tokens.warning,
      blue: tokens.info,
      magenta: tokens.accent,
      cyan: tokens.info,
      brightBlack: tokens.textMuted,
      brightRed: tokens.danger,
      brightGreen: tokens.success,
      brightYellow: tokens.warning,
      brightBlue: tokens.info,
      brightMagenta: tokens.accent,
      brightCyan: tokens.info,
      brightWhite: tokens.textPrimary,
      searchHitBackground: tokens.accent.withValues(alpha: 0.3),
      searchHitBackgroundCurrent: tokens.accent.withValues(alpha: 0.6),
      searchHitForeground: tokens.displayText,
    );
  }

  void _createNewTab({String? preferredShell}) {
    _counter++;
    final String shellExe;
    final List<String> shellArgs;
    final String shellName;

    if (Platform.isWindows) {
      if (preferredShell == 'cmd') {
        shellExe = 'cmd.exe';
        shellArgs = ['/k'];
        shellName = 'cmd';
      } else {
        shellExe = 'powershell.exe';
        shellArgs = ['-NoLogo'];
        shellName = 'PowerShell';
      }
    } else if (Platform.isMacOS) {
      final envShell = Platform.environment['SHELL'] ?? '/bin/zsh';
      shellExe = envShell;
      shellArgs = ['-l'];
      shellName = envShell.split('/').last;
    } else {
      final envShell = Platform.environment['SHELL'] ?? '/bin/bash';
      shellExe = envShell;
      shellArgs = ['-i'];
      shellName = envShell.split('/').last;
    }

    final terminal = Terminal(
      maxLines: 10000,
    );

    final session = TerminalTabSession(
      id: 'term_$_counter',
      title: '$shellName $_counter',
      shellName: shellName,
      terminal: terminal,
    );

    setState(() {
      _tabs.add(session);
      _activeTabIndex = _tabs.length - 1;
    });

    _startProcessForTab(session, shellExe, shellArgs);
  }

  Future<void> _startProcessForTab(
    TerminalTabSession session,
    String executable,
    List<String> args,
  ) async {
    final effectiveCwd = widget.cwd.isNotEmpty && Directory(widget.cwd).existsSync()
        ? widget.cwd
        : Directory.current.path;

    session.terminal.write(
      'Avvio sessione terminale in: $effectiveCwd\r\n\r\n',
    );

    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: effectiveCwd,
        runInShell: true,
      );

      session.process = process;
      session.isRunning = true;

      session.terminal.onOutput = (data) {
        try {
          process.stdin.write(data);
        } catch (_) {}
      };

      session._stdoutSub = process.stdout.listen((bytes) {
        if (!mounted) return;
        session.terminal.write(utf8.decode(bytes, allowMalformed: true));
      });

      session._stderrSub = process.stderr.listen((bytes) {
        if (!mounted) return;
        session.terminal.write(utf8.decode(bytes, allowMalformed: true));
      });

      process.exitCode.then((code) {
        if (!mounted) return;
        setState(() {
          session.isRunning = false;
          session.exitCode = code;
        });
        session.terminal.write(
          '\r\n[Processo terminato con codice $code]\r\n',
        );
      });
    } catch (e) {
      if (!mounted) return;
      session.terminal.write(
        'Impossibile avviare il processo della shell ($executable): $e\r\n',
      );
      setState(() {
        session.isRunning = false;
        session.exitCode = -1;
      });
    }
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final closing = _tabs[index];
    closing.dispose();

    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        widget.onClose();
      } else {
        if (_activeTabIndex >= _tabs.length) {
          _activeTabIndex = _tabs.length - 1;
        }
      }
    });
  }

  void _sendCommand(String command) {
    if (_tabs.isEmpty) return;
    final currentTab = _tabs[_activeTabIndex];
    if (currentTab.process == null) return;

    final trimmed = command.trim();
    if (trimmed.isNotEmpty) {
      _history.add(trimmed);
    }

    try {
      currentTab.process!.stdin.writeln(command);
    } catch (_) {}
    _cmdInputController.clear();
    _cmdFocusNode.requestFocus();
  }

  void _sendInterrupt() {
    if (_tabs.isEmpty) return;
    final currentTab = _tabs[_activeTabIndex];
    try {
      // Send Ctrl+C (character code 3)
      currentTab.process?.stdin.add([3]);
    } catch (_) {}
  }

  void _clearScreen() {
    if (_tabs.isEmpty) return;
    final currentTab = _tabs[_activeTabIndex];
    currentTab.terminal.buffer.clear();
    currentTab.terminal.setCursor(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;

    if (_tabs.isEmpty) {
      return Container(
        color: tokens.chassis,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nessun terminale aperto',
                style: TextStyle(color: tokens.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.surface,
                ),
                onPressed: () => _createNewTab(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Apri nuovo terminale'),
              ),
            ],
          ),
        ),
      );
    }

    final activeTab = _tabs[_activeTabIndex];

    return Container(
      decoration: BoxDecoration(
        color: tokens.chassis,
        border: Border(
          top: BorderSide(color: tokens.borderStrong, width: 1),
        ),
      ),
      child: Column(
        children: [
          // -------------------------------------------------------------
          // Top Tab Bar & Actions
          // -------------------------------------------------------------
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                // Scrollable Tabs
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    itemBuilder: (context, index) {
                      final tab = _tabs[index];
                      final isSelected = index == _activeTabIndex;

                      return InkWell(
                        onTap: () => setState(() => _activeTabIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? tokens.chassis
                                : tokens.surface,
                            border: Border(
                              right: BorderSide(color: tokens.border),
                              bottom: isSelected
                                  ? BorderSide(color: tokens.accent, width: 2)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.terminal,
                                size: 14,
                                color: isSelected
                                    ? tokens.accent
                                    : tokens.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tab.title,
                                style: TextStyle(
                                  color: isSelected
                                      ? tokens.displayText
                                      : tokens.textMuted,
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _closeTab(index),
                                borderRadius: BorderRadius.circular(tokens.radiusSm),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: tokens.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // "+" Add Tab Button
                PopupMenuButton<String>(
                  tooltip: 'Nuovo terminale',
                  icon: Icon(Icons.add, size: 16, color: tokens.displayText),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onSelected: (val) {
                    if (val == 'default') {
                      _createNewTab();
                    } else {
                      _createNewTab(preferredShell: val);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'default',
                      child: Row(
                        children: [
                          const Icon(Icons.terminal, size: 15),
                          const SizedBox(width: 8),
                          Text(
                            Platform.isWindows
                                ? 'Nuovo terminale (PowerShell)'
                                : 'Nuovo terminale',
                          ),
                        ],
                      ),
                    ),
                    if (Platform.isWindows)
                      PopupMenuItem(
                        value: 'cmd',
                        child: Row(
                          children: [
                            Icon(Icons.terminal, size: 15),
                            const SizedBox(width: 8),
                            Text('Command Prompt (cmd)'),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 4),

                // Clear screen action
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: 'Pulisci schermo (Clear)',
                  icon: const Icon(Icons.block, size: 14),
                  onPressed: _clearScreen,
                ),

                const SizedBox(width: 4),

                // Collapse Downward Button
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: 'Collassa in basso',
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  onPressed: widget.onCollapseDownward,
                ),

                const SizedBox(width: 4),

                // Close Button
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: 'Chiudi terminale',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // -------------------------------------------------------------
          // Terminal View Body
          // -------------------------------------------------------------
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              color: tokens.chassis,
              child: TerminalView(
                activeTab.terminal,
                theme: _buildTerminalTheme(tokens),
                textStyle: TerminalStyle(
                  fontSize: 12,
                  fontFamily: tokens.monoFontFamily,
                ),
                autofocus: false,
              ),
            ),
          ),

          // -------------------------------------------------------------
          // Quick Action Bar & Command Input Line
          // -------------------------------------------------------------
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  border: Border(
                    top: BorderSide(color: tokens.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Quick chips
                    if (!isNarrow) ...[
                      _buildQuickChip('git status', tokens),
                      const SizedBox(width: 4),
                      _buildQuickChip('git diff', tokens),
                      const SizedBox(width: 4),
                      _buildQuickChip('pi --version', tokens),
                      const SizedBox(width: 8),
                    ],

                    // Interrupt button
                Tooltip(
                  message: 'Interrompi processo corrente (Ctrl+C)',
                  child: InkWell(
                    onTap: _sendInterrupt,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: tokens.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stop, size: 12, color: tokens.danger),
                          const SizedBox(width: 2),
                          Text(
                            'Ctrl+C',
                            style: TextStyle(
                              color: tokens.danger,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Command Input Field
                Expanded(
                  child: SizedBox(
                    height: 26,
                    child: TextField(
                      controller: _cmdInputController,
                      focusNode: _cmdFocusNode,
                      style: TextStyle(
                        color: tokens.displayText,
                        fontSize: 11,
                        fontFamily: tokens.monoFontFamily,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Invia comando al terminale...',
                        hintStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          borderSide: BorderSide(color: tokens.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          borderSide: BorderSide(color: tokens.accent),
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          _sendCommand(value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Invia comando',
                  icon: Icon(Icons.arrow_forward, size: 14, color: tokens.accent),
                  onPressed: () {
                    final text = _cmdInputController.text;
                    if (text.isNotEmpty) {
                      _sendCommand(text);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String command, CrustTokens tokens) {
    return InkWell(
      onTap: () => _sendCommand(command),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: tokens.displaySurface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          command,
          style: TextStyle(
            color: tokens.displayText,
            fontSize: 10,
            fontFamily: tokens.monoFontFamily,
          ),
        ),
      ),
    );
  }
}
