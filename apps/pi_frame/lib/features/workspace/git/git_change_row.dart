import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../ui/code/file_icon.dart';
import '../../../ui/motion.dart';

/// One file row of the Git pane (staged or unstaged). Tapping it opens the diff.
bool _pathSetContains(Set<String> paths, String path) =>
    paths.contains(path) ||
    paths.any((value) => value.toLowerCase() == path.toLowerCase());

String _changeOriginLabel(
  String path,
  Set<String> piTouchedPaths,
  Set<String> manualSavedPaths, [
  AppStrings? strings,
]) {
  final touchedByPi = _pathSetContains(piTouchedPaths, path);
  final savedHere = _pathSetContains(manualSavedPaths, path);
  if (touchedByPi && savedHere) {
    return strings?.gitOriginPiAndManual ?? 'Tool Pi + salvataggio PiFrame';
  }
  if (touchedByPi) {
    return strings?.gitOriginPiTool ?? 'Tool Pi ha scritto il percorso';
  }
  if (savedHere) {
    return strings?.gitOriginManualSave ?? 'Salvato da te in PiFrame';
  }
  return strings?.gitOriginUndetermined ?? 'Origine non determinata';
}

class GitChangeRow extends StatelessWidget {
  const GitChangeRow({
    super.key,
    required this.file,
    required this.isStaged,
    required this.hasUnstagedEdit,
    required this.tokens,
    required this.piTouchedPaths,
    required this.manualSavedPaths,
    required this.blocked,
    required this.working,
    required this.strings,
    required this.onShowDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final Map<String, dynamic> file;
  final bool isStaged;
  final bool hasUnstagedEdit;
  final FrameTokens tokens;
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
      offset: 4,
      duration: FrameMotion.small,
      child: _rowBody(),
    );
  }

  Widget _rowBody() {
    final path = file['path'].toString();
    final stateLabel = isStaged && hasUnstagedEdit
        ? strings.gitStateStagedAndUnstaged
        : isStaged
        ? strings.gitStateStaged
        : strings.gitStateUnstaged;

    return Material(
      color: tokens.surface.withValues(alpha: 0),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.only(left: 16, right: 8),
        onTap: () => onShowDiff(path),
        leading: FileIcon(path: path, size: 16),
        title: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 12,
            fontFamily: tokens.uiFontFamily,
          ),
        ),
        subtitle: Text(
          '${strings.gitFileStatusLabel(file['status']?.toString() ?? 'modified')} · $stateLabel · ${_changeOriginLabel(path, piTouchedPaths, manualSavedPaths, strings)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isStaged ? tokens.accent : tokens.textMuted,
            fontSize: 9,
          ),
        ),
        trailing: SizedBox(
          width: 88,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isStaged)
                IconButton(
                  tooltip: strings.unstageFileTooltip(path),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: blocked || working ? null : () => onUnstage(path),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                )
              else if (hasUnstagedEdit || !isStaged)
                IconButton(
                  tooltip: strings.stageFileTooltip(path),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: blocked || working ? null : () => onStage(path),
                  icon: const Icon(Icons.add, size: 17),
                ),
              IconButton(
                tooltip: strings.discardFileTooltip(path),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: blocked || working ? null : () => onDiscard(path),
                icon: const Icon(Icons.undo, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
