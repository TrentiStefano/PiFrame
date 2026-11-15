import 'package:flutter/material.dart';
import '../../../ui/precision.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../app/row_context_menu.dart';
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
import '../../../ui/motion.dart';
import '../branch_picker_dialog.dart';
import '../../browser/browser_controller.dart';
import '../../browser/browser_models.dart';
import '../../composer/composer_draft.dart';
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
/// One entry of the Git list as the keyboard sees it. Every entry is one row
/// high. [render] builds it; [selected] marks the keyboard cursor.
class _GitEntry {
  _GitEntry({
    required this.key,
    required this.section,
    required this.render,
    this.path,
    this.isHeader = false,
    this.expanded = false,
  });

  /// A note under an empty section ("Nessun file preparato.").
  factory _GitEntry.note(String section, String message) => _GitEntry(
    key: 'n:$section',
    section: section,
    render: (_) => GitListNote(message: message),
  );

  final String key;

  /// 'staged' or 'unstaged'.
  final String section;
  final Widget Function(bool selected) render;

  /// File path, for file rows only.
  final String? path;
  final bool isHeader;

  /// Whether the section is open, for section headers only.
  final bool expanded;
}

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

  /// Commit message: the subject, and the optional body behind a toggle.
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _bodyOpen = false;

  /// The error of the last failed commit, shown inline until the next attempt.
  Object? _commitError;

  /// The Git list is one Tab stop; this node holds that focus.
  final _listFocus = FocusNode(debugLabel: 'git-list');
  final _listScroll = ScrollController();

  /// Keyboard cursor: the key of the focused entry, or null for the first one.
  String? _cursorKey;

  /// Row menus by entry key, opened by Shift+F10 or the Menu key on the cursor.
  final RowMenuRegistry _rowMenus = RowMenuRegistry();
  final Map<String, GlobalKey> _gitRowKeys = {};

  /// The file open in the pane's diff view, or null while the Git list shows.
  String? _diffPath;

  /// Horizontal travel of the list ↔ diff swap: +8 px to open, -8 px to go back.
  double _paneSlide = 0;

  /// Bumped on each status refresh, so the open diff reloads after a stage.
  int _statusRevision = 0;

  /// Rows that left a group in the last refresh. They stay in their old group
  /// for one exit fade (Spec F) while the counts already show the new state.
  final List<_DepartingRow> _departing = [];
  int _departureSeq = 0;

  /// 'staged:path' or 'unstaged:path' keys of rows that entered a group in the
  /// last refresh. They fade and slide into place once.
  Set<String> _arrivals = {};

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
      _departing.clear();
      _arrivals = {};
      _refresh();
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _listFocus.dispose();
    _listScroll.dispose();
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
        setState(() {
          final previous = _files;
          _status = (result['data'] as Map<String, dynamic>?) ?? result;
          _statusRevision++;
          _recordTravel(previous);
        });
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

  /// The rows shown in each group, keyed 'staged:path' or 'unstaged:path'.
  /// Mirrors the grouping in `build`: a file is Staged when `staged` is true,
  /// and Changes when it has unstaged edits or is not staged.
  static Map<String, Map<String, dynamic>> _sectionRows(
    List<Map<String, dynamic>> files,
  ) {
    final rows = <String, Map<String, dynamic>>{};
    for (final file in files) {
      final path = file['path'].toString();
      final staged = file['staged'] == true;
      if (staged) rows['staged:$path'] = file;
      if (file['unstaged'] == true || !staged) rows['unstaged:$path'] = file;
    }
    return rows;
  }

  /// Compares the groups before and after a refresh. A row that moved from one
  /// group to the other departs its old group and arrives in the new one.
  void _recordTravel(List<Map<String, dynamic>> previous) {
    final before = _sectionRows(previous);
    final after = _sectionRows(_files);
    _departing.clear();
    _arrivals = {};
    for (final entry in before.entries) {
      if (after.containsKey(entry.key)) continue;
      final isStaged = entry.key.startsWith('staged:');
      final path = entry.key.substring(entry.key.indexOf(':') + 1);
      final other = isStaged ? 'unstaged:$path' : 'staged:$path';
      if (!after.containsKey(other)) continue;
      _departing.add(
        _DepartingRow(
          id: ++_departureSeq,
          isStaged: isStaged,
          file: entry.value,
          hasUnstagedEdit: !isStaged || entry.value['unstaged'] == true,
        ),
      );
    }
    for (final key in after.keys) {
      if (before.containsKey(key)) continue;
      final isStaged = key.startsWith('staged:');
      final path = key.substring(key.indexOf(':') + 1);
      final other = isStaged ? 'unstaged:$path' : 'staged:$path';
      if (before.containsKey(other)) _arrivals.add(key);
    }
  }

  List<String> get _staged =>
      _files
          .where((f) => f['staged'] == true)
          .map((f) => f['path'].toString())
          .toList()
        ..sort();

  /// Runs one Git write and returns the daemon's reply, or null when it failed.
  /// A failure is a snackbar, or with [inlineErrors] the commit form's error.
  Future<Map<String, dynamic>?> _action(
    String action,
    List<String> paths, {
    String? message,
    List<String>? expected,
    bool inlineErrors = false,
  }) async {
    if (_working || (paths.isEmpty && !_remoteActions.contains(action))) {
      return null;
    }
    setState(() => _working = true);
    try {
      final reply = await ref.read(pcpClientProvider)!.workspaceGitAction(
        widget.sessionId,
        {
          'action': action,
          'paths': paths,
          'expectedStagedPaths': ?expected,
          'message': ?message,
        },
      );
      if (_remoteActions.contains(action) && mounted) {
        FrameSnackBar.show(
          context,
          message: ref.read(appStringsProvider).gitRemoteActionDone(action),
        );
      }
      if (action == 'discard' || action == 'commit') {
        ref
            .read(repositoryStateProvider(widget.sessionId).notifier)
            .clearManualSavedPaths(paths);
      }
      await _refresh();
      return reply;
    } catch (error) {
      if (mounted) {
        if (inlineErrors) {
          setState(() => _commitError = error);
        } else {
          final strings = ref.read(appStringsProvider);
          FrameSnackBar.show(
            context,
            message: strings.gitOperationFailed(error),
            isError: true,
          );
        }
      }
      return null;
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
    final text = FrameText.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: PressFeedback(enabled: (enabled ? () => _action(action, const []) : null) != null, child: OutlinedButton(
          key: ValueKey('git-$action-btn'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x1,
              vertical: FrameSpace.x1,
            ),
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
                Icon(icon, size: FrameSize.icon),
                const SizedBox(width: FrameSpace.x1),
                Text(label, style: text.caption),
              ],
            ),
          ),
        )),
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
          FrameSnackBar.show(
            context,
            message: strings.branchNotFound,
            isError: true,
          );
          await _refresh();
          return;
        } else if (error.code == 'BRANCH_INVALID_NAME') {
          FrameSnackBar.show(
            context,
            message: strings.branchInvalidName,
            isError: true,
          );
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
        FrameSnackBar.show(
          context,
          message: strings.branchNotFound,
          isError: true,
        );
        await _refresh();
      } else {
        FrameSnackBar.show(
          context,
          message: failureText(strings, strings.branchSwitchFailedTitle, error),
          isError: true,
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
    final text = FrameText.of(context);
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
            style: text.title.copyWith(color: tokens.textPrimary),
          ),
          content: Text(
            strings.workspaceDirtyDialogMessage(changedFiles, untrackedFiles),
            style: text.bodyLarge.copyWith(color: tokens.textMuted),
          ),
          actions: [
            PressFeedback(enabled: true, child: OutlinedButton(
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
            )),
            PressFeedback(enabled: true, child: FilledButton(
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
            )),
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
    final text = FrameText.of(context);
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
              Icon(Icons.error_outline, color: tokens.danger, size: FrameSize.iconLg),
              const SizedBox(width: FrameSpace.x2),
              Expanded(
                child: Text(
                  strings.branchSwitchFailedTitle,
                  style: text.title.copyWith(color: tokens.textPrimary),
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
                      padding: const EdgeInsets.all(FrameSpace.x2),
                      margin: const EdgeInsets.only(bottom: FrameSpace.x3),
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
                            size: FrameSize.iconLg,
                          ),
                          const SizedBox(width: FrameSpace.x2),
                          Expanded(
                            child: Text(
                              strings.stashRetainedSafeNotice(
                                stashMessage ?? '',
                              ),
                              style: text.body.copyWith(
                                color: tokens.textPrimary,
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
                    padding: const EdgeInsets.all(FrameSpace.x2),
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: SelectableText(
                      truncatedStderr,
                      style: text.mono.copyWith(color: tokens.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            PressFeedback(enabled: true, child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext),
              child: Text(strings.close),
            )),
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
    if (confirmed != true) return;
    await _action('discard', [path]);
    // A discarded file leaves the list, so the diff of it has nothing left to show.
    if (mounted && _diffPath == path && !_files.any((f) => f['path'] == path)) {
      _closeDiff();
    }
  }

  /// Commits the staged files with the subject and optional body from the
  /// inline form. Success shows the short hash of the new commit.
  Future<void> _commit() async {
    final staged = _staged;
    final subject = _subject.text.trim();
    if (staged.isEmpty || subject.isEmpty || _working) return;
    final body = _body.text.trim();
    final message = body.isEmpty ? subject : '$subject\n\n$body';
    setState(() => _commitError = null);
    final reply = await _action(
      'commit',
      staged,
      message: message,
      expected: staged,
      inlineErrors: true,
    );
    if (reply == null || !mounted) return;
    _subject.clear();
    _body.clear();
    final shortHash = await _headShortSha();
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    FrameSnackBar.show(context, message: strings.commitCreated(shortHash));
  }

  /// Short hash of HEAD, for the commit snackbar. The commit reply does not
  /// carry it, so it comes from the branch listing. Empty when that fails.
  Future<String> _headShortSha() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return '';
    try {
      final listing = await client.listBranches(widget.sessionId);
      return listing.headShortSha ?? '';
    } catch (_) {
      return '';
    }
  }

  /// A row that moved into its group fades and slides in once (Spec F). Reduced
  /// motion makes the move instant.
  Widget _buildGitFileRow({
    required Map<String, dynamic> file,
    required bool isStaged,
    required bool hasUnstagedEdit,
    required Set<String> piTouchedPaths,
    required Set<String> manualSavedPaths,
    required bool blocked,
    required AppStrings strings,
    bool selected = false,
    bool leaving = false,
  }) {
    final path = file['path'].toString();
    final section = isStaged ? 'staged' : 'unstaged';
    final rowKey = _gitRowKeys.putIfAbsent('r:$section:$path', GlobalKey.new);
    _rowMenus.register('r:$section:$path', () {
      final rowContext = rowKey.currentContext;
      if (rowContext == null) return;
      _showRowMenu(
        rowAnchorRect(rowContext),
        path: path,
        isStaged: isStaged,
        blocked: blocked,
      );
    });
    final row = KeyedSubtree(
      key: rowKey,
      child: GitChangeRow(
        file: file,
        isStaged: isStaged,
        hasUnstagedEdit: hasUnstagedEdit,
        piTouchedPaths: piTouchedPaths,
        manualSavedPaths: manualSavedPaths,
        blocked: blocked,
        working: _working,
        strings: strings,
        selected: selected,
        onShowDiff: (_) {
          _selectRow('r:$section:$path');
          _openDiff(path);
        },
        onContextMenu: (position) => _showRowMenu(
          pointerAnchorRect(position),
          path: path,
          isStaged: isStaged,
          blocked: blocked,
        ),
        onStage: (path) => _action('stage', [path]),
        onUnstage: (path) => _action('unstage', [path]),
        onDiscard: (path) => _discardFile(path),
      ),
    );
    if (leaving) {
      return ExcludeSemantics(
        child: IgnorePointer(
          child: KeyedSubtree(
            key: ValueKey('git-row-leaving-$section-$path'),
            child: row,
          ),
        ),
      );
    }
    return _RowTravelEnter(
      key: ValueKey('git-row-$section-$path'),
      animate:
          !FrameMotion.reduced(context) && _arrivals.contains('$section:$path'),
      child: row,
    );
  }

  /// Opens the diff of [path] in the pane, in place of the Git list. Chat stays
  /// visible above it.
  void _openDiff(String path) {
    setState(() {
      _diffPath = path;
      _paneSlide = FrameSpace.x2;
    });
  }

  /// Moves the open diff to [path] (Alt+arrow or the pane's next and previous
  /// buttons). The list cursor follows, so Escape lands on the same row.
  void _showDiffPath(String path) {
    final unstaged = _files.any(
      (f) =>
          f['path'] == path && (f['unstaged'] == true || f['staged'] != true),
    );
    setState(() {
      _diffPath = path;
      _cursorKey = 'r:${unstaged ? 'unstaged' : 'staged'}:$path';
    });
  }

  /// Back from the diff to the Git list, with keyboard focus returned to it.
  void _closeDiff() {
    setState(() {
      _diffPath = null;
      _paneSlide = -FrameSpace.x2;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listFocus.requestFocus();
    });
  }

  /// Moves the cursor to [key] and takes keyboard focus for the list.
  void _selectRow(String key) {
    setState(() => _cursorKey = key);
    _listFocus.requestFocus();
  }

  void _toggleSection(String section, bool expanded) {
    final provider = section == 'staged'
        ? gitStagedExpandedProvider
        : gitUnstagedExpandedProvider;
    ref.read(provider(widget.sessionId).notifier).state = !expanded;
  }

  int _cursorIndex(List<_GitEntry> entries) {
    final index = entries.indexWhere((e) => e.key == _cursorKey);
    return index < 0 ? 0 : index;
  }

  String _activeKey(List<_GitEntry> entries) =>
      entries[_cursorIndex(entries)].key;

  void _moveCursor(int index, List<_GitEntry> entries) {
    final target = index < 0
        ? 0
        : index >= entries.length
        ? entries.length - 1
        : index;
    setState(() => _cursorKey = entries[target].key);
    _ensureVisible(target);
  }

  /// Scrolls the list by the least amount that shows row [index]. Every entry
  /// is exactly `FrameSize.rowList` high, so the offset is arithmetic.
  void _ensureVisible(int index) {
    if (!_listScroll.hasClients) return;
    final position = _listScroll.position;
    final top = index * FrameSize.rowList;
    final bottom = top + FrameSize.rowList;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top;
    } else if (bottom > viewBottom) {
      target = bottom - position.viewportDimension;
    }
    if (target == null) return;
    _listScroll.jumpTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  /// Keys on the focused Git list: arrows move, Enter opens the diff (or
  /// toggles a section), Space stages or unstages (or toggles a section),
  /// Delete opens the discard confirmation.
  KeyEventResult _onListKey(
    KeyEvent event,
    List<_GitEntry> entries,
    bool blocked,
  ) {
    if (event is KeyUpEvent || entries.isEmpty) return KeyEventResult.ignored;
    final index = _cursorIndex(entries);
    final entry = entries[index];
    final key = event.logicalKey;
    final writesOff = blocked || _working;
    if (isContextMenuKey(event)) {
      _rowMenus.openFor(entry.key);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(index + 1, entries);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(index - 1, entries);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (entry.isHeader) {
        _toggleSection(entry.section, entry.expanded);
      } else if (entry.path != null) {
        _openDiff(entry.path!);
      }
    } else if (key == LogicalKeyboardKey.space) {
      if (entry.isHeader) {
        _toggleSection(entry.section, entry.expanded);
      } else if (entry.path != null && !writesOff) {
        _action(entry.section == 'staged' ? 'unstage' : 'stage', [entry.path!]);
      }
    } else if (key == LogicalKeyboardKey.delete) {
      if (entry.path != null && !writesOff) _discardFile(entry.path!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Right-click menu of a Git row. The actions are the existing ones: diff,
  /// stage or unstage, discard, copy path, and add to the chat (the same path
  /// the editor uses).
  Future<void> _showRowMenu(
    Rect anchor, {
    required String path,
    required bool isStaged,
    required bool blocked,
  }) async {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.read(appStringsProvider);
    final writesOff = blocked || _working;
    Widget item(IconData icon, String label, Color iconColor) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: FrameSize.icon, color: iconColor),
        const SizedBox(width: FrameSpace.x2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.body.copyWith(color: tokens.textPrimary),
          ),
        ),
      ],
    );
    final choice = await showMenu<String>(
      context: context,
      position: menuPositionFor(context, anchor),
      items: [
        PopupMenuItem<String>(
          key: const ValueKey('git-menu-open-diff'),
          value: 'diff',
          child: item(
            Icons.article_outlined,
            strings.gitMenuOpenDiff,
            tokens.textMuted,
          ),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('git-menu-toggle-stage'),
          value: 'toggle',
          enabled: !writesOff,
          child: item(
            isStaged ? Icons.remove_circle_outline : Icons.add_outlined,
            isStaged ? strings.gitMenuUnstage : strings.gitMenuStage,
            tokens.textMuted,
          ),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('git-menu-discard'),
          value: 'discard',
          enabled: !writesOff,
          child: item(Icons.undo_outlined, strings.gitMenuDiscard, tokens.danger),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('git-menu-copy-path'),
          value: 'copy',
          child: item(Icons.copy_outlined, strings.copyPath, tokens.textMuted),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('git-menu-add-chat'),
          value: 'chat',
          child: item(
            Icons.add_comment_outlined,
            strings.addPathToChat,
            tokens.accent,
          ),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'diff':
        _openDiff(path);
      case 'toggle':
        _action(isStaged ? 'unstage' : 'stage', [path]);
      case 'discard':
        _discardFile(path);
      case 'copy':
        Clipboard.setData(ClipboardData(text: path));
        FrameSnackBar.show(context, message: strings.pathCopied(path));
      case 'chat':
        appendFileMentionToComposer(ref, widget.sessionId, path);
        FrameSnackBar.show(context, message: strings.addedFileToChat(path));
    }
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
    // A row still fading out of a group keeps that group open until it is gone.
    final reduced = FrameMotion.reduced(context);
    final leavingStaged = reduced
        ? const <_DepartingRow>[]
        : _departing.where((d) => d.isStaged).toList();
    final leavingUnstaged = reduced
        ? const <_DepartingRow>[]
        : _departing.where((d) => !d.isStaged).toList();
    // Default rule: CHANGES opens when it has files; STAGED opens when it has
    // files and CHANGES is empty. A toggle by the user overrides the default.
    final isStagedExpanded =
        ref.watch(gitStagedExpandedProvider(widget.sessionId)) ??
        (leavingStaged.isNotEmpty ||
            (stagedFiles.isNotEmpty && unstagedFiles.isEmpty));
    final isUnstagedExpanded =
        ref.watch(gitUnstagedExpandedProvider(widget.sessionId)) ??
        (unstagedFiles.isNotEmpty || leavingUnstaged.isNotEmpty);
    final repo = _status?['isRepository'] == true;
    final root = _status?['rootPath']?.toString() ?? cwd;
    _GitEntry fileEntry(
      Map<String, dynamic> file, {
      required bool isStaged,
      required bool hasUnstagedEdit,
    }) {
      final path = file['path'].toString();
      final section = isStaged ? 'staged' : 'unstaged';
      return _GitEntry(
        key: 'r:$section:$path',
        section: section,
        path: path,
        render: (selected) => _buildGitFileRow(
          file: file,
          isStaged: isStaged,
          hasUnstagedEdit: hasUnstagedEdit,
          piTouchedPaths: piTouchedPaths,
          manualSavedPaths: repository.manualSavedPaths,
          blocked: blocked,
          strings: strings,
          selected: selected,
        ),
      );
    }

    // A row leaving its group keeps its old place for one exit fade. It is
    // not focusable: it has no path, so Space and Enter do nothing on it.
    _GitEntry departingEntry(_DepartingRow row) {
      final section = row.isStaged ? 'staged' : 'unstaged';
      return _GitEntry(
        key: 'x:${row.id}',
        section: section,
        render: (_) => _RowTravelLeave(
          onDone: () {
            if (mounted) {
              setState(() => _departing.removeWhere((d) => d.id == row.id));
            }
          },
          child: _buildGitFileRow(
            file: row.file,
            isStaged: row.isStaged,
            hasUnstagedEdit: row.hasUnstagedEdit,
            piTouchedPaths: piTouchedPaths,
            manualSavedPaths: repository.manualSavedPaths,
            blocked: blocked,
            strings: strings,
            leaving: true,
          ),
        ),
      );
    }

    final listEntries = <_GitEntry>[
      _GitEntry(
        key: 'h:staged',
        section: 'staged',
        isHeader: true,
        expanded: isStagedExpanded,
        render: (selected) => GitSectionHeader(
          title: strings.stagedChangesSectionUpper,
          count: stagedFiles.length,
          isExpanded: isStagedExpanded,
          selected: selected,
          onToggle: () => _toggleSection('staged', isStagedExpanded),
          trailing: stagedFiles.isEmpty || blocked || _working
              ? null
              : ExcludeFocus(
                  child: FrameIconAction(
                    key: const ValueKey('git-unstage-all-btn'),
                    tooltip: strings.unstageAllTooltip,
                    icon: Icons.remove_circle_outline,
                    onPressed: () => _action(
                      'unstage',
                      stagedFiles.map((f) => f['path'].toString()).toList(),
                    ),
                  ),
                ),
        ),
      ),
      if (isStagedExpanded)
        ...(stagedFiles.isEmpty && leavingStaged.isEmpty
            ? [_GitEntry.note('staged', strings.noStagedFiles)]
            : [
                for (final file in stagedFiles)
                  fileEntry(
                    file,
                    isStaged: true,
                    hasUnstagedEdit: file['unstaged'] == true,
                  ),
                for (final row in leavingStaged) departingEntry(row),
              ]),
      _GitEntry(
        key: 'h:unstaged',
        section: 'unstaged',
        isHeader: true,
        expanded: isUnstagedExpanded,
        render: (selected) => GitSectionHeader(
          title: strings.changesSectionUpper,
          count: unstagedFiles.length,
          isExpanded: isUnstagedExpanded,
          selected: selected,
          onToggle: () => _toggleSection('unstaged', isUnstagedExpanded),
          trailing: unstagedFiles.isEmpty || blocked || _working
              ? null
              : ExcludeFocus(
                  child: FrameIconAction(
                    key: const ValueKey('git-stage-all-btn'),
                    tooltip: strings.stageAllTooltip,
                    icon: Icons.add_outlined,
                    onPressed: () => _action(
                      'stage',
                      unstagedFiles.map((f) => f['path'].toString()).toList(),
                    ),
                  ),
                ),
        ),
      ),
      if (isUnstagedExpanded)
        ...(unstagedFiles.isEmpty && leavingUnstaged.isEmpty
            ? [_GitEntry.note('unstaged', strings.noUnstagedChanges)]
            : [
                for (final file in unstagedFiles)
                  fileEntry(file, isStaged: false, hasUnstagedEdit: true),
                for (final row in leavingUnstaged) departingEntry(row),
              ]),
    ];

    // Files the diff pane steps through: staged first, then unstaged, as listed.
    final unstagedPaths = {for (final f in unstagedFiles) f['path'].toString()};
    final diffTargets = <GitDiffTarget>[];
    for (final f in [...stagedFiles, ...unstagedFiles]) {
      final path = f['path'].toString();
      if (diffTargets.any((t) => t.path == path)) continue;
      diffTargets.add(
        GitDiffTarget(path: path, stagedOnly: !unstagedPaths.contains(path)),
      );
    }
    final diffOpen =
        _diffPath != null && diffTargets.any((t) => t.path == _diffPath);
    if (_diffPath != null && !diffOpen) {
      // The file left the list (committed or changed elsewhere): show the list again.
      final stalePath = _diffPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _diffPath == stalePath &&
            !_files.any((f) => f['path'] == stalePath)) {
          setState(() => _diffPath = null);
        }
      });
    }

    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          workspacePaneHeader(
            context,
            strings.gitChangesLabel,
            Icons.source_outlined,
            companionTabs: widget.companionTabs,
            companionTabLabels: workspaceCompanionTabLabels(strings),
            activeCompanionTab: widget.activeCompanionTab ?? WorkspacePane.git,
            onSelectCompanionTab: widget.onSelectCompanionTab,
            titleWidget: Row(
                children: [
                  Icon(Icons.source_outlined, size: FrameSize.icon, color: tokens.accent),
                  const SizedBox(width: FrameSpace.x2),
                  // Title and chip share the header width and shrink with an
                  // ellipsis at large text scale, instead of scrolling off.
                  Flexible(
                    child: Text(
                      strings.gitChangesLabel.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.label.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (ref.watch(browserPaneSupportedProvider)) ...[
                    const SizedBox(width: FrameSpace.x2),
                    Flexible(
                    child: InkWell(
                      key: const ValueKey('right-pane-switch-browser-chip'),
                      onTap: () {
                        ref.read(rightPaneModeProvider.notifier).state =
                            RightPaneMode.browser;
                      },
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FrameSpace.x1,
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
                              Icons.language_outlined,
                              size: 12,
                              color: tokens.textMuted,
                            ),
                            const SizedBox(width: FrameSpace.x1),
                            Flexible(
                              child: Text(
                                strings.browserPaneLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.caption.copyWith(
                                  color: tokens.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                  ],
                ],
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
                    icon: const Icon(Icons.language_outlined, size: FrameSize.icon),
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
                  icon: const Icon(Icons.refresh_outlined, size: FrameSize.icon),
                ),
                if (widget.onCollapse != null) ...[
                  const SizedBox(width: FrameSpace.x1),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(FrameSpace.x1),
                    constraints: const BoxConstraints(),
                    tooltip: strings.collapseGitPanelTooltip,
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_right_outlined, size: FrameSize.iconLg),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: FrameSwitcher(
              slide: _paneSlide,
              child: diffOpen
                  ? GitDiffPane(
                      key: const ValueKey('git-pane-diff'),
                      sessionId: widget.sessionId,
                      targets: diffTargets,
                      path: _diffPath!,
                      revision: _statusRevision,
                      writesOff: blocked || _working,
                      onBack: _closeDiff,
                      onOpenPath: _showDiffPath,
                      onStageToggle: (target) => _action(
                        target.stagedOnly ? 'unstage' : 'stage',
                        [target.path],
                      ),
                      onDiscard: _discardFile,
                    )
                  : Column(
                      key: const ValueKey('git-pane-list'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            FrameSpace.x3,
                            FrameSpace.x1,
                            FrameSpace.x3,
                            FrameSpace.x2,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  root,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.caption.copyWith(
                                    color: tokens.textMuted,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                ),
                              ),
                              if (repo ||
                                  _status?['branch'] != null ||
                                  _status?['detached'] == true) ...[
                                const SizedBox(width: FrameSpace.x1),
                                Builder(
                                  builder: (context) {
                                    final branchDisabled =
                                        blocked || _working || _loading;
                                    final chipTooltip = (blocked && !readOnly)
                                        ? strings.branchSwitchAgentWorking
                                        : strings.branchChipTooltip;
                                    return Tooltip(
                                      message: chipTooltip,
                                      child: InkWell(
                                        key: const ValueKey('git-branch-chip'),
                                        onTap: branchDisabled
                                            ? null
                                            : _openBranchPicker,
                                        borderRadius: BorderRadius.circular(
                                          tokens.radiusSm,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: FrameSpace.x1,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: tokens.surface,
                                            borderRadius: BorderRadius.circular(
                                              tokens.radiusSm,
                                            ),
                                            border: Border.all(
                                              color: tokens.border,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.fork_right_outlined,
                                                size: 13,
                                                color: branchDisabled
                                                    ? tokens.textMuted
                                                    : tokens.accent,
                                              ),
                                              const SizedBox(
                                                width: FrameSpace.x1,
                                              ),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 160,
                                                    ),
                                                child: Text(
                                                  _status?['detached'] == true
                                                      ? (_status?['headShortSha']
                                                                ?.toString() ??
                                                            'detached')
                                                      : (_status?['branch']
                                                                ?.toString() ??
                                                            '—'),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: text.caption.copyWith(
                                                    color: branchDisabled
                                                        ? tokens.textMuted
                                                        : tokens.textPrimary,
                                                    fontFamily:
                                                        tokens.monoFontFamily,
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
                                          rawError.contains(
                                            'Session not found',
                                          ))) ||
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
                                      style: text.body.copyWith(
                                        color: tokens.textMuted,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return Expanded(
                                child: Center(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(
                                      FrameSpace.x3,
                                    ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: FrameSpace.x3,
                            ),
                            child: Wrap(
                              spacing: 4,
                              children: [
                                Text(
                                  strings.gitFilesCount(files.length),
                                  style: text.caption.copyWith(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                Text(
                                  '+${_status?['totalAdditions'] ?? 0}',
                                  style: text.caption.copyWith(
                                    color: tokens.diffAddedFg,
                                  ),
                                ),
                                Text(
                                  '-${_status?['totalDeletions'] ?? 0}',
                                  style: text.caption.copyWith(
                                    color: tokens.diffRemovedFg,
                                  ),
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
                                      actionIcon: Icons.refresh_outlined,
                                      onAction: _loading
                                          ? null
                                          : () => _refresh(),
                                    )
                                  : Focus(
                                      focusNode: _listFocus,
                                      onFocusChange: (_) => setState(() {}),
                                      onKeyEvent: (node, event) => _onListKey(
                                        event,
                                        listEntries,
                                        blocked,
                                      ),
                                      child: ListView.builder(
                                        key: const ValueKey('git-list'),
                                        controller: _listScroll,
                                        itemExtent: FrameSize.rowList,
                                        itemCount: listEntries.length,
                                        itemBuilder: (context, index) {
                                          final entry = listEntries[index];
                                          return entry.render(
                                            _listFocus.hasFocus &&
                                                entry.key ==
                                                    _activeKey(listEntries),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ),
                          if (_working)
                            LinearProgressIndicator(
                              key: const ValueKey('git-working-progress'),
                              minHeight: 2,
                              // Reduced motion: a static full bar instead of the sweep.
                              value: FrameMotion.reduced(context) ? 1 : null,
                              color: tokens.accent,
                              backgroundColor: tokens.surface,
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              FrameSpace.x2,
                              FrameSpace.x1,
                              FrameSpace.x2,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Always reserved, so the list above does not move when a run
                                // starts or ends. Shows the reason writes are paused.
                                SizedBox(
                                  height: FrameSize.icon,
                                  child: blocked
                                      ? Row(
                                          key: const ValueKey(
                                            'git-writes-disabled',
                                          ),
                                          children: [
                                            Icon(
                                              Icons.pause_circle_outline,
                                              size: FrameSize.icon,
                                              color: tokens.warning,
                                            ),
                                            const SizedBox(
                                              width: FrameSpace.x2,
                                            ),
                                            Expanded(
                                              child: Text(
                                                readOnly
                                                    ? strings
                                                          .writesDisabledReadOnly(
                                                            readOnlyReason,
                                                          )
                                                    : strings
                                                          .writesDisabledPiWorking,
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
                                GitCommitFields(
                                  subject: _subject,
                                  body: _body,
                                  bodyOpen: _bodyOpen,
                                  canWrite: !blocked && !_working,
                                  strings: strings,
                                  error: _commitError,
                                  onToggleBody: () =>
                                      setState(() => _bodyOpen = !_bodyOpen),
                                  onCommit: _commit,
                                ),
                                const SizedBox(height: FrameSpace.x2),
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
                                        Icons.arrow_downward_outlined,
                                        strings.gitPullLabel,
                                        strings.gitPullTooltip,
                                      ),
                                      (
                                        'push',
                                        Icons.arrow_upward_outlined,
                                        strings.gitPushLabel,
                                        strings.gitPushTooltip,
                                      ),
                                      (
                                        'sync',
                                        Icons.sync_outlined,
                                        strings.gitSyncLabel,
                                        strings.gitSyncTooltip,
                                      ),
                                    ].indexed) ...[
                                      if (i > 0)
                                        const SizedBox(width: FrameSpace.x1),
                                      _remoteButton(
                                        action: spec.$1,
                                        icon: spec.$2,
                                        label: spec.$3,
                                        tooltip: spec.$4,
                                        enabled:
                                            !blocked && !_working && !_loading,
                                        tokens: tokens,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              FrameSpace.x2,
                              FrameSpace.x1,
                              FrameSpace.x2,
                              FrameSpace.x2,
                            ),
                            // Rebuilt as the subject changes, so the button
                            // enables as soon as a subject is typed.
                            child: ListenableBuilder(
                              listenable: _subject,
                              builder: (context, _) => GitCommitButton(
                                label: strings.commitButtonLabel(staged.length),
                                tooltip: strings.commitShortcutTooltip,
                                enabled:
                                    !blocked &&
                                    !_working &&
                                    staged.isNotEmpty &&
                                    _subject.text.trim().isNotEmpty,
                                fullWidth: gitCompactLayout(context),
                                onPressed: _commit,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row that left one group for the other in the last status refresh.
class _DepartingRow {
  const _DepartingRow({
    required this.id,
    required this.isStaged,
    required this.file,
    required this.hasUnstagedEdit,
  });

  final int id;
  final bool isStaged;
  final Map<String, dynamic> file;
  final bool hasUnstagedEdit;
}

/// Fades a row in and rises it 4 px into its group: opacity 0 to 1 and y +4
/// to 0 over `FrameMotion.small` (Spec F). Only rows that just arrived pass
/// [animate]; every other row mounts at rest.
class _RowTravelEnter extends StatefulWidget {
  const _RowTravelEnter({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<_RowTravelEnter> createState() => _RowTravelEnterState();
}

class _RowTravelEnterState extends State<_RowTravelEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FrameMotion.small,
      value: widget.animate ? 0 : 1,
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: FrameMotion.enterCurve,
    );
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * FrameSpace.x1),
          child: child,
        ),
      ),
    );
  }
}

/// Fades a row out and lifts it 4 px while it leaves its group: opacity 1 to 0
/// and y 0 to -4 over `FrameMotion.smallExit` (Spec F). [onDone] runs when the
/// fade ends, so the row can be dropped from the list.
class _RowTravelLeave extends StatefulWidget {
  const _RowTravelLeave({required this.onDone, required this.child});

  final VoidCallback onDone;
  final Widget child;

  @override
  State<_RowTravelLeave> createState() => _RowTravelLeaveState();
}

class _RowTravelLeaveState extends State<_RowTravelLeave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: FrameMotion.smallExit)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) widget.onDone();
          });
    _curve = CurvedAnimation(
      parent: _controller,
      curve: FrameMotion.enterCurve,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: 1 - _curve.value,
        child: Transform.translate(
          offset: Offset(0, -FrameSpace.x1 * _curve.value),
          child: child,
        ),
      ),
    );
  }
}
