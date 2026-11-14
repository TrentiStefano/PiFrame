import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/daemon/daemon_providers.dart';
import '../../../data/daemon/pcp_client.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../data/language/strings_errors.dart';
import '../../../domain/errors/user_facing_error.dart';
import '../../../domain/session/agent_status.dart';
import '../../../domain/session/session_state.dart';
import '../../../ui/frame_empty_state.dart';
import '../../../ui/frame_error_callout.dart';
import '../../../ui/frame_icon_action.dart';
import '../../../ui/frame_snack_bar.dart';
import '../branch_picker_dialog.dart';
import '../../browser/browser_controller.dart';
import '../../browser/browser_models.dart';
import '../../session_changes/session_changes_provider.dart';
import '../workspace_change_paths.dart';
import '../workspace_pane.dart';
import '../workspace_pane_header.dart';
import '../repository_state.dart';
import 'git_change_row.dart';
import 'git_commit_form.dart';
import 'git_diff_view.dart';
import 'git_loading_rows.dart';
import 'git_section_header.dart';

/// Expansion of the STAGED and CHANGES groups. Null means "not toggled yet":
/// the default rule applies (see `build`).
final gitStagedExpandedProvider = StateProvider.family<bool?, String>(
  (ref, sessionId) => null,
);

final gitUnstagedExpandedProvider = StateProvider.family<bool?, String>(
  (ref, sessionId) => null,
);

Set<String> _piTouchedPaths(SessionState session) => piTouchedPaths(session);

class GitChangesPane extends ConsumerStatefulWidget {
  const GitChangesPane({
    super.key,
    required this.sessionId,
    this.onCollapse,
    this.companionTabs,
    this.activeCompanionTab,
    this.onSelectCompanionTab,
  });
  final String sessionId;
  final VoidCallback? onCollapse;
  final List<WorkspacePane>? companionTabs;
  final WorkspacePane? activeCompanionTab;
  final ValueChanged<WorkspacePane>? onSelectCompanionTab;
  @override
  ConsumerState<GitChangesPane> createState() => _GitChangesPaneState();
}

class _GitChangesPaneState extends ConsumerState<GitChangesPane> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  bool _working = false;
  bool _branchPickerOpen = false;
  final _message = TextEditingController();
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(GitChangesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _status = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void>? _refreshing;
  bool _refreshAgain = false;

  /// Opening a session fires several refresh triggers in a row (cwd, idle, touched files). While one
  /// refresh runs, further requests collapse into a single follow-up, so the result is still current.
  Future<void> _refresh() {
    if (_refreshing != null) {
      _refreshAgain = true;
      return _refreshing!;
    }
    return _refreshing = () async {
      try {
        do {
          _refreshAgain = false;
          await _refreshOnce();
        } while (_refreshAgain && mounted);
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _refreshOnce() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) setState(() => _status = {'error': 'Daemon non connesso'});
      return;
    }
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final result = await client.refreshWorkspace(widget.sessionId);
      if (mounted) {
        setState(
          () => _status = (result['data'] as Map<String, dynamic>?) ?? result,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = {'error': e.toString()});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _files =>
      ((_status?['files'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .toList();
  List<String> get _staged =>
      _files
          .where((f) => f['staged'] == true)
          .map((f) => f['path'].toString())
          .toList()
        ..sort();
  Future<void> _action(
    String action,
    List<String> paths, {
    String? message,
    List<String>? expected,
  }) async {
    if (_working || (paths.isEmpty && !_remoteActions.contains(action))) return;
    setState(() => _working = true);
    try {
      await ref.read(pcpClientProvider)!.workspaceGitAction(widget.sessionId, {
        'action': action,
        'paths': paths,
        'expectedStagedPaths': ?expected,
        'message': ?message,
      });
      if (action == 'discard' || action == 'commit') {
        ref
            .read(repositoryStateProvider(widget.sessionId).notifier)
            .clearManualSavedPaths(paths);
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.gitOperationFailed(error));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static const _remoteActions = {'fetch', 'pull', 'push', 'sync'};

  Widget _remoteButton({
    required String action,
    required IconData icon,
    required String label,
    required String tooltip,
    required bool enabled,
    required FrameTokens tokens,
  }) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          key: ValueKey('git-$action-btn'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(0, 30),
            visualDensity: VisualDensity.compact,
            foregroundColor: tokens.textPrimary,
            side: BorderSide(color: tokens.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
          ),
          onPressed: enabled ? () => _action(action, const []) : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBranchPicker() async {
    final session = ref.read(sessionStateFamily(widget.sessionId));
    final readOnly = session.readOnly;
    final agentStatus = session.agentStatus;
    final blocked =
        readOnly ||
        const {
          AgentStatus.working,
          AgentStatus.retrying,
          AgentStatus.compacting,
          AgentStatus.awaitingUser,
        }.contains(agentStatus);
    if (_branchPickerOpen || _loading || _working || blocked) return;
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    _branchPickerOpen = true;
    try {
      final current = _status?['branch']?.toString();
      final targetBranch = await BranchPickerDialog.show(
        context,
        sessionId: widget.sessionId,
        client: client,
        currentBranch: current,
      );
      if (targetBranch != null && mounted) {
        await _handleSwitchBranch(targetBranch);
      }
    } finally {
      _branchPickerOpen = false;
    }
  }

  Future<void> _handleSwitchBranch(String branch, {bool stash = false}) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    final strings = ref.read(appStringsProvider);
    setState(() => _loading = true);
    try {
      final result = await client.switchBranch(
        widget.sessionId,
        branch,
        onDirty: stash ? 'stash' : 'block',
      );
      await _refresh();
      try {
        await ref
            .read(sessionChangesProvider(widget.sessionId).notifier)
            .refresh();
      } catch (_) {}
      if (!mounted) return;
      if (result.stashed) {
        FrameSnackBar.show(
          context,
          message:
              '${strings.branchSwitched(branch)}. ${strings.branchSwitchedStashNotice(result.stashMessage ?? '')}',
        );
      } else {
        FrameSnackBar.show(context, message: strings.branchSwitched(branch));
      }
    } catch (error) {
      if (!mounted) return;
      if (error is PcpException) {
        if (error.code == 'WORKSPACE_DIRTY') {
          final shouldStash = await _showDirtyWorkspaceDialog(
            changedFiles: error.changedFiles,
            untrackedFiles: error.untrackedFiles,
          );
          if (shouldStash == true && mounted) {
            await _handleSwitchBranch(branch, stash: true);
          }
          return;
        } else if (error.code == 'BRANCH_SWITCH_FAILED') {
          await _showBranchSwitchFailedDialog(
            stderr: error.stderr ?? error.message,
            stashRetained: error.stashRetained,
            stashMessage: error.stashMessage,
          );
          return;
        } else if (error.code == 'COMMAND_REJECTED' ||
            error.message.toLowerCase().contains('read-only') ||
            error.message.toLowerCase().contains('busy') ||
            error.message.toLowerCase().contains('working')) {
          FrameSnackBar.show(
            context,
            message: strings.branchSwitchAgentWorking,
          );
          return;
        } else if (error.code == 'BRANCH_NOT_FOUND') {
          FrameSnackBar.show(context, message: strings.branchNotFound);
          await _refresh();
          return;
        } else if (error.code == 'BRANCH_INVALID_NAME') {
          FrameSnackBar.show(context, message: strings.branchInvalidName);
          await _refresh();
          return;
        }
      }
      final msg = error.toString();
      if (msg.toLowerCase().contains('read-only') ||
          msg.toLowerCase().contains('working') ||
          msg.toLowerCase().contains('busy') ||
          msg.toLowerCase().contains('active')) {
        FrameSnackBar.show(context, message: strings.branchSwitchAgentWorking);
      } else if (msg.contains('BRANCH_NOT_FOUND')) {
        FrameSnackBar.show(context, message: strings.branchNotFound);
        await _refresh();
      } else {
        FrameSnackBar.show(
          context,
          message: failureText(strings, strings.branchSwitchFailedTitle, error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showDirtyWorkspaceDialog({
    required int changedFiles,
    required int untrackedFiles,
  }) {
    final strings = ref.read(appStringsProvider);
    final tokens = context.tokens;
    var popped = false;
    void popOnce(BuildContext dialogContext, bool result) {
      if (popped) return;
      popped = true;
      Navigator.of(dialogContext).pop(result);
    }

    return showDialog<bool>(
      context: context,
      barrierColor: tokens.overlay,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            side: BorderSide(color: tokens.border),
          ),
          title: Text(
            strings.workspaceDirtyDialogTitle,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            strings.workspaceDirtyDialogMessage(changedFiles, untrackedFiles),
            style: TextStyle(color: tokens.textMuted, fontSize: 14),
          ),
          actions: [
            OutlinedButton(
              key: const ValueKey('git-cancel-switch-btn'),
              autofocus: true,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textPrimary,
                side: BorderSide(color: tokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const ValueKey('git-stash-and-switch-btn'),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext, true),
              child: Text(strings.stashAndSwitchBtn),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBranchSwitchFailedDialog({
    required String stderr,
    required bool stashRetained,
    String? stashMessage,
  }) {
    final strings = ref.read(appStringsProvider);
    final tokens = context.tokens;
    final truncatedStderr = stderr.length > 2048
        ? '${stderr.substring(0, 2048)}\n…'
        : stderr;
    var popped = false;
    void popOnce(BuildContext dialogContext) {
      if (popped) return;
      popped = true;
      Navigator.of(dialogContext).pop();
    }

    return showDialog<void>(
      context: context,
      barrierColor: tokens.overlay,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            side: BorderSide(color: tokens.border),
          ),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: tokens.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.branchSwitchFailedTitle,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stashRetained) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: tokens.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: tokens.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              strings.stashRetainedSafeNotice(
                                stashMessage ?? '',
                              ),
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: SelectableText(
                      truncatedStderr,
                      style: TextStyle(
                        fontFamily: tokens.monoFontFamily,
                        fontSize: 12,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext),
              child: Text(strings.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _discardFile(String path) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    var diff = '';
    try {
      final result = await client.getWorkspaceDiff(
        widget.sessionId,
        filePath: path,
      );
      diff = (result['data']?['diff'] ?? result['diff'])?.toString() ?? '';
    } catch (_) {}
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    final confirmed = await showGitDiscardDialog(
      context: context,
      strings: strings,
      path: path,
      diff: diff,
      status: _status,
    );
    if (!mounted) return;
    if (confirmed == true) await _action('discard', [path]);
  }

  Future<void> _commit() async {
    final staged = _staged;
    if (staged.isEmpty) return;
    final strings = ref.read(appStringsProvider);
    final message = await showGitCommitDialog(
      context: context,
      strings: strings,
      controller: _message,
      staged: staged,
      status: _status,
    );
    if (message == null || message.isEmpty) return;
    _message.clear();
    await _action('commit', staged, message: message, expected: staged);
  }

  /// Each row fades in where it appears, so a file moving between Staged and Changes is visible.
  Widget _buildGitFileRow({
    required Map<String, dynamic> file,
    required bool isStaged,
    required bool hasUnstagedEdit,
    required Set<String> piTouchedPaths,
    required Set<String> manualSavedPaths,
    required bool blocked,
    required AppStrings strings,
  }) {
    final path = file['path'].toString();
    return GitChangeRow(
      key: ValueKey(
        'git-row-${isStaged ? 'staged' : 'unstaged'}-${file['path']}',
      ),
      file: file,
      isStaged: isStaged,
      hasUnstagedEdit: hasUnstagedEdit,
      piTouchedPaths: piTouchedPaths,
      manualSavedPaths: manualSavedPaths,
      blocked: blocked,
      working: _working,
      strings: strings,
      onShowDiff: (_) => showGitDiffDialog(
        context: context,
        ref: ref,
        sessionId: widget.sessionId,
        path: path,
      ),
      onStage: (path) => _action('stage', [path]),
      onUnstage: (path) => _action('unstage', [path]),
      onDiscard: (path) => _discardFile(path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final (readOnly, readOnlyReason, agentStatus, cwd, touchedKey) = ref.watch(
      sessionStateFamily(widget.sessionId).select(
        (s) => (
          s.readOnly,
          s.readOnlyReason,
          s.agentStatus,
          s.cwd,
          _piTouchedPaths(s).join('\x00'),
        ),
      ),
    );
    final repository = ref.watch(repositoryStateProvider(widget.sessionId));

    ref.listen<String>(
      sessionStateFamily(widget.sessionId).select((s) => s.cwd),
      (prev, next) {
        if (next.isNotEmpty &&
            (prev == null || prev.isEmpty || _status?['error'] != null)) {
          _refresh();
        }
      },
    );

    ref.listen<String>(
      sessionStateFamily(widget.sessionId)
          .select((s) => _piTouchedPaths(s).join('\x00')),
      (prev, next) {
        if (prev != null && prev != next) {
          _refresh();
        }
      },
    );

    ref.listen<AgentStatus>(
      sessionStateFamily(widget.sessionId).select((s) => s.agentStatus),
      (prev, next) {
        if (prev != null && prev != next && next == AgentStatus.idle) {
          _refresh();
        }
      },
    );

    final piTouchedPaths = touchedKey.isEmpty
        ? const <String>{}
        : touchedKey.split('\x00').toSet();
    final blocked =
        readOnly ||
        const {
          AgentStatus.working,
          AgentStatus.retrying,
          AgentStatus.compacting,
          AgentStatus.awaitingUser,
        }.contains(agentStatus);
    final files = _files;
    final staged = _staged.toSet();
    final stagedFiles = files
        .where((f) => staged.contains(f['path'].toString()))
        .toList();
    final unstagedFiles = files
        .where(
          (f) =>
              f['unstaged'] == true || !staged.contains(f['path'].toString()),
        )
        .toList();
    // Default rule: CHANGES opens when it has files; STAGED opens when it has
    // files and CHANGES is empty. A toggle by the user overrides the default.
    final isStagedExpanded =
        ref.watch(gitStagedExpandedProvider(widget.sessionId)) ??
        (stagedFiles.isNotEmpty && unstagedFiles.isEmpty);
    final isUnstagedExpanded =
        ref.watch(gitUnstagedExpandedProvider(widget.sessionId)) ??
        unstagedFiles.isNotEmpty;
    final repo = _status?['isRepository'] == true;
    final root = _status?['rootPath']?.toString() ?? cwd;
    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          workspacePaneHeader(
            context,
            'Git Changes',
            Icons.source_outlined,
            companionTabs: widget.companionTabs,
            activeCompanionTab: widget.activeCompanionTab ?? WorkspacePane.git,
            onSelectCompanionTab: widget.onSelectCompanionTab,
            titleWidget: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(Icons.source_outlined, size: 16, color: tokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    'GIT CHANGES',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11.5,
                      fontFamily: tokens.uiFontFamily,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (ref.watch(browserPaneSupportedProvider)) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      key: const ValueKey('right-pane-switch-browser-chip'),
                      onTap: () {
                        ref.read(rightPaneModeProvider.notifier).state =
                            RightPaneMode.browser;
                      },
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.language,
                              size: 12,
                              color: tokens.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Browser',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ref.watch(browserPaneSupportedProvider))
                  IconButton(
                    key: const ValueKey('git-switch-to-browser-btn'),
                    tooltip: strings.switchToWebBrowserTooltip,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    onPressed: () {
                      ref.read(rightPaneModeProvider.notifier).state =
                          RightPaneMode.browser;
                    },
                    icon: const Icon(Icons.language, size: 16),
                  ),
                IconButton(
                  tooltip: strings.refreshGitStatusTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                ),
                if (widget.onCollapse != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: strings.collapseGitPanelTooltip,
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_right, size: 18),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    root,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ),
                if (repo ||
                    _status?['branch'] != null ||
                    _status?['detached'] == true) ...[
                  const SizedBox(width: 6),
                  Builder(
                    builder: (context) {
                      final branchDisabled = blocked || _working || _loading;
                      final chipTooltip = (blocked && !readOnly)
                          ? strings.branchSwitchAgentWorking
                          : strings.branchChipTooltip;
                      return Tooltip(
                        message: chipTooltip,
                        child: InkWell(
                          key: const ValueKey('git-branch-chip'),
                          onTap: branchDisabled ? null : _openBranchPicker,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
                              border: Border.all(color: tokens.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fork_right,
                                  size: 13,
                                  color: branchDisabled
                                      ? tokens.textMuted
                                      : tokens.accent,
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 160,
                                  ),
                                  child: Text(
                                    _status?['detached'] == true
                                        ? (_status?['headShortSha']
                                                  ?.toString() ??
                                              'detached')
                                        : (_status?['branch']?.toString() ??
                                              '—'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: branchDisabled
                                          ? tokens.textMuted
                                          : tokens.textPrimary,
                                      fontSize: 11,
                                      fontFamily: tokens.monoFontFamily,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          if (!repo)
            Builder(
              builder: (context) {
                final rawError = _status?['error']?.toString();
                final isAttaching =
                    (rawError != null &&
                        (rawError.contains('not found') ||
                            rawError.contains('Session not found'))) ||
                    (_status == null && cwd.isEmpty);

                if (_loading || isAttaching) {
                  // Skeleton rows in the place of the file rows, so the
                  // list does not jump when the status arrives.
                  return Expanded(
                    child: GitLoadingRows(
                      key: const ValueKey('git-loading'),
                      label: strings.gitLoadingStatus,
                    ),
                  );
                }

                if (rawError == null) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        strings.noGitRepository,
                        style: text.body.copyWith(color: tokens.textMuted),
                      ),
                    ),
                  );
                }
                return Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: FrameErrorCallout(
                        keyPrefix: 'git-status-error',
                        title: strings.gitStatusLoadFailed,
                        error: describeError(rawError, strings),
                        strings: strings,
                        onRetry: _refresh,
                      ),
                    ),
                  ),
                );
              },
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 4,
                children: [
                  Text(
                    strings.gitFilesCount(files.length),
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                  Text(
                    '+${_status?['totalAdditions'] ?? 0}',
                    style: TextStyle(color: tokens.diffAddedFg, fontSize: 11),
                  ),
                  Text(
                    '-${_status?['totalDeletions'] ?? 0}',
                    style: TextStyle(color: tokens.diffRemovedFg, fontSize: 11),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRect(
                // The summary line stays outside the scroll view. The clip
                // keeps scrolled group headers from painting over it.
                child: files.isEmpty
                    ? FrameEmptyState(
                        keyPrefix: 'git-empty',
                        icon: Icons.check_circle_outline,
                        title: strings.gitCleanTitle,
                        message: strings.gitCleanMessage(
                          _status?['branch']?.toString() ?? '—',
                        ),
                        actionLabel: strings.gitRefreshAction,
                        actionIcon: Icons.refresh,
                        onAction: _loading ? null : () => _refresh(),
                      )
                    : ListView(
                        children: [
                          GitSectionHeader(
                            title: strings.stagedChangesSectionUpper,
                            count: stagedFiles.length,
                            isExpanded: isStagedExpanded,
                            onToggle: () {
                              ref
                                      .read(
                                        gitStagedExpandedProvider(
                                          widget.sessionId,
                                        ).notifier,
                                      )
                                      .state =
                                  !isStagedExpanded;
                            },
                            trailing: stagedFiles.isEmpty || blocked || _working
                                ? null
                                : FrameIconAction(
                                    key: const ValueKey('git-unstage-all-btn'),
                                    tooltip: strings.unstageAllTooltip,
                                    icon: Icons.remove_circle_outline,
                                    onPressed: () => _action(
                                      'unstage',
                                      stagedFiles
                                          .map((f) => f['path'].toString())
                                          .toList(),
                                    ),
                                  ),
                          ),
                          if (isStagedExpanded) ...[
                            if (stagedFiles.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Text(
                                  strings.noStagedFiles,
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            else
                              for (final file in stagedFiles)
                                _buildGitFileRow(
                                  file: file,
                                  isStaged: true,
                                  hasUnstagedEdit: file['unstaged'] == true,
                                  piTouchedPaths: piTouchedPaths,
                                  manualSavedPaths: repository.manualSavedPaths,
                                  blocked: blocked,
                                  strings: strings,
                                ),
                          ],
                          GitSectionHeader(
                            title: strings.changesSectionUpper,
                            count: unstagedFiles.length,
                            isExpanded: isUnstagedExpanded,
                            onToggle: () {
                              ref
                                      .read(
                                        gitUnstagedExpandedProvider(
                                          widget.sessionId,
                                        ).notifier,
                                      )
                                      .state =
                                  !isUnstagedExpanded;
                            },
                            trailing:
                                unstagedFiles.isEmpty || blocked || _working
                                ? null
                                : FrameIconAction(
                                    key: const ValueKey('git-stage-all-btn'),
                                    tooltip: strings.stageAllTooltip,
                                    icon: Icons.add,
                                    onPressed: () => _action(
                                      'stage',
                                      unstagedFiles
                                          .map((f) => f['path'].toString())
                                          .toList(),
                                    ),
                                  ),
                          ),
                          if (isUnstagedExpanded) ...[
                            if (unstagedFiles.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Text(
                                  strings.noUnstagedChanges,
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            else
                              for (final file in unstagedFiles)
                                _buildGitFileRow(
                                  file: file,
                                  isStaged: false,
                                  hasUnstagedEdit: true,
                                  piTouchedPaths: piTouchedPaths,
                                  manualSavedPaths: repository.manualSavedPaths,
                                  blocked: blocked,
                                  strings: strings,
                                ),
                          ],
                        ],
                      ),
              ),
            ),
            if (_working)
              LinearProgressIndicator(
                key: const ValueKey('git-working-progress'),
                minHeight: 2,
                color: tokens.accent,
                backgroundColor: tokens.surface,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Always reserved, so the list above does not move when a run
                  // starts or ends. Shows the reason writes are paused.
                  SizedBox(
                    height: FrameSize.icon,
                    child: blocked
                        ? Row(
                            key: const ValueKey('git-writes-disabled'),
                            children: [
                              Icon(
                                Icons.pause_circle_outline,
                                size: FrameSize.icon,
                                color: tokens.warning,
                              ),
                              const SizedBox(width: FrameSpace.x2),
                              Expanded(
                                child: Text(
                                  readOnly
                                      ? strings.writesDisabledReadOnly(
                                          readOnlyReason,
                                        )
                                      : strings.writesDisabledPiWorking,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.caption.copyWith(
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                  Row(
                    children: [
                      for (final (i, spec) in [
                        (
                          'fetch',
                          Icons.cloud_download_outlined,
                          strings.gitFetchLabel,
                          strings.gitFetchTooltip,
                        ),
                        (
                          'pull',
                          Icons.arrow_downward,
                          strings.gitPullLabel,
                          strings.gitPullTooltip,
                        ),
                        (
                          'push',
                          Icons.arrow_upward,
                          strings.gitPushLabel,
                          strings.gitPushTooltip,
                        ),
                        (
                          'sync',
                          Icons.sync,
                          strings.gitSyncLabel,
                          strings.gitSyncTooltip,
                        ),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _remoteButton(
                          action: spec.$1,
                          icon: spec.$2,
                          label: spec.$3,
                          tooltip: spec.$4,
                          enabled: !blocked && !_working && !_loading,
                          tokens: tokens,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: blocked || _working || staged.isEmpty
                      ? null
                      : _commit,
                  child: Text(strings.commitButtonLabel(staged.length)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
