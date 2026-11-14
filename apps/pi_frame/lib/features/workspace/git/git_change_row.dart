import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../ui/code/file_icon.dart';
import '../../../ui/frame_icon_action.dart';
import '../../../ui/frame_list_row.dart';
import '../../../ui/motion.dart';

/// Who touched a changed file, when PiFrame knows it.
enum _ChangeOrigin { pi, manual, piAndManual }

bool _pathSetContains(Set<String> paths, String path) =>
    paths.contains(path) ||
    paths.any((value) => value.toLowerCase() == path.toLowerCase());

_ChangeOrigin? _changeOrigin(
  String path,
  Set<String> piTouchedPaths,
  Set<String> manualSavedPaths,
) {
  final touchedByPi = _pathSetContains(piTouchedPaths, path);
  final savedHere = _pathSetContains(manualSavedPaths, path);
  if (touchedByPi && savedHere) return _ChangeOrigin.piAndManual;
  if (touchedByPi) return _ChangeOrigin.pi;
  if (savedHere) return _ChangeOrigin.manual;
  return null;
}

String _originLabel(_ChangeOrigin origin, AppStrings strings) =>
    switch (origin) {
      _ChangeOrigin.piAndManual => strings.gitOriginPiAndManual,
      _ChangeOrigin.pi => strings.gitOriginPiTool,
      _ChangeOrigin.manual => strings.gitOriginManualSave,
    };

/// One-letter badge for a daemon file status (`modified`, `untracked`, ...).
String _statusCode(String status) => switch (status) {
  'modified' => 'M',
  'added' => 'A',
  'deleted' => 'D',
  'renamed' => 'R',
  'copied' => 'C',
  'typechanged' => 'T',
  'untracked' => 'U',
  'unmerged' => '!',
  _ => '?',
};

Color _statusColor(String status, FrameTokens tokens) => switch (status) {
  'added' || 'untracked' => tokens.diffAddedFg,
  'deleted' => tokens.diffRemovedFg,
  'unmerged' => tokens.danger,
  'renamed' || 'copied' => tokens.info,
  _ => tokens.warning,
};

/// Splits a path into its file name and parent directory. [dir] is null for a
/// file at the root.
({String name, String? dir}) splitGitPath(String path) {
  final cut = [
    path.lastIndexOf('/'),
    path.lastIndexOf('\\'),
  ].reduce((a, b) => a > b ? a : b);
  if (cut < 0) return (name: path, dir: null);
  final dir = path.substring(0, cut);
  return (name: path.substring(cut + 1), dir: dir.isEmpty ? null : dir);
}

/// Companion width below which the Git list is treated as compact. Same
/// breakpoint as the shell's narrow layout (`app_shell.dart`).
const double gitCompactLayoutWidth = 900;

/// Whether the Git pane is in the compact layout (below [gitCompactLayoutWidth]).
bool gitCompactLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < gitCompactLayoutWidth;

/// Whether the row actions (stage, unstage, discard) stay visible without a
/// hover. True where there is no hover pointer: compact layouts, iOS and
/// Android, and mobile web (Flutter web reports the device platform there).
bool gitRowActionsAlwaysVisible(BuildContext context) {
  if (gitCompactLayout(context)) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };
}

/// One file row of the Git pane (staged or unstaged), on one line: the file
/// name in full, then its parent directory, then the status badge.
/// Tapping it opens the diff.
class GitChangeRow extends StatelessWidget {
  const GitChangeRow({
    super.key,
    required this.file,
    required this.isStaged,
    required this.hasUnstagedEdit,
    required this.piTouchedPaths,
    required this.manualSavedPaths,
    required this.blocked,
    required this.working,
    required this.strings,
    required this.onShowDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.selected = false,
    this.onContextMenu,
  });

  final Map<String, dynamic> file;
  final bool selected;
  final ValueChanged<Offset>? onContextMenu;
  final bool isStaged;
  final bool hasUnstagedEdit;
  final Set<String> piTouchedPaths;
  final Set<String> manualSavedPaths;
  final bool blocked;
  final bool working;
  final AppStrings strings;
  final ValueChanged<String> onShowDiff;
  final ValueChanged<String> onStage;
  final ValueChanged<String> onUnstage;
  final ValueChanged<String> onDiscard;

  @override
  Widget build(BuildContext context) {
    return FrameEnter(
      offset: FrameSpace.x1,
      duration: FrameMotion.small,
      child: _rowBody(context),
    );
  }

  Widget _rowBody(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final path = file['path'].toString();
    final status = file['status']?.toString() ?? 'modified';
    final parts = splitGitPath(path);
    final section = isStaged ? 'staged' : 'unstaged';
    final stateLabel = isStaged && hasUnstagedEdit
        ? strings.gitStateStagedAndUnstaged
        : isStaged
        ? strings.gitStateStaged
        : strings.gitStateUnstaged;
    final origin = _changeOrigin(path, piTouchedPaths, manualSavedPaths);
    final actionsBlocked = blocked || working;

    return FrameListRow(
      name: parts.name,
      secondary: parts.dir,
      inlineSecondary: true,
      // The Git list is one Tab stop; arrow keys move between rows. Mouse and
      // right-click work on the row directly.
      focusable: false,
      selected: selected,
      revealActionsWhenSelected: true,
      revealActionsAlways: gitRowActionsAlwaysVisible(context),
      onSecondaryTap: onContextMenu,
      onTap: () => onShowDiff(path),
      leading: FileIcon(path: path, size: FrameSize.icon),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (origin != null) ...[
            Tooltip(
              message: _originLabel(origin, strings),
              child: Icon(
                key: ValueKey('git-origin-$section-$path'),
                origin == _ChangeOrigin.manual
                    ? Icons.person_outline
                    : Icons.auto_awesome_outlined,
                size: FrameSize.icon,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(width: FrameSpace.x2),
          ],
          Tooltip(
            message: '${strings.gitFileStatusLabel(status)} · $stateLabel',
            child: SizedBox(
              width: FrameSize.icon,
              child: Text(
                _statusCode(status),
                textAlign: TextAlign.center,
                style: text.mono.copyWith(
                  color: _statusColor(status, tokens),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      // Excluded from Tab: Space and Delete on the focused list do the same.
      actions: [
        ExcludeFocus(
          child: FrameIconAction(
            key: ValueKey('git-$section-toggle-$path'),
            icon: isStaged ? Icons.remove_circle_outline : Icons.add_outlined,
            tooltip: isStaged
                ? strings.unstageFileTooltip(path)
                : strings.stageFileTooltip(path),
            onPressed: actionsBlocked
                ? null
                : () => isStaged ? onUnstage(path) : onStage(path),
          ),
        ),
        // Gap between stage and discard, so a misclick does not discard.
        const SizedBox(width: FrameSpace.x2),
        ExcludeFocus(
          child: FrameIconAction(
            key: ValueKey('git-$section-discard-$path'),
            icon: Icons.undo_outlined,
            tooltip: strings.discardFileTooltip(path),
            onPressed: actionsBlocked ? null : () => onDiscard(path),
          ),
        ),
      ],
    );
  }
}
