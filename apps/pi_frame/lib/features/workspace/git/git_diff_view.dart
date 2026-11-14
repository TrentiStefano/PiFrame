import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/daemon/daemon_providers.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../domain/errors/user_facing_error.dart';
import '../../../ui/code/diff_block.dart';
import '../../../ui/frame_dialog.dart';
import '../../../ui/frame_error_callout.dart';
import '../../../ui/frame_icon_action.dart';
import '../../../ui/frame_pane_header.dart';
import '../../../ui/frame_snack_bar.dart';
import '../../../ui/motion.dart';
import 'git_change_row.dart';

/// Widest the "Apri in finestra" dialog gets. Wider than the default dialog,
/// so diff lines fit without scrolling sideways.
const double gitDiffWindowMaxWidth = 900;

/// A file the diff pane steps through, in list order (staged, then unstaged).
class GitDiffTarget {
  const GitDiffTarget({required this.path, required this.stagedOnly});

  final String path;

  /// True when the file has no unstaged edits, so its row action is Unstage.
  final bool stagedOnly;
}

/// Loads the diff of [path] from the daemon.
Future<String> _loadDiffText(
  WidgetRef ref,
  String sessionId,
  String path,
) async {
  final client = ref.read(pcpClientProvider);
  if (client == null) throw StateError('daemon not connected');
  final result = await client.getWorkspaceDiff(sessionId, filePath: path);
  return (result['data']?['diff'] ?? result['diff'])?.toString() ?? '';
}

/// "Apri in finestra": the diff of [path] in a dialog. The width follows the
/// window up to [gitDiffWindowMaxWidth]; the height fits the content up to the
/// dialog's cap, then the body scrolls.
Future<void> showGitDiffWindowDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String sessionId,
  required String path,
}) async {
  final strings = ref.read(appStringsProvider);
  try {
    final diff = await _loadDiffText(ref, sessionId, path);
    if (!context.mounted) return;
    await showFrameDialog<void>(
      context: context,
      dialog: FrameDialog<void>(
        title: path,
        maxWidth: gitDiffWindowMaxWidth,
        body: DiffBlock(
          diffText: diff.isEmpty ? strings.noDifferencesFound : diff,
          filename: path,
        ),
        actions: [
          FrameDialogAction<void>(
            label: strings.close,
            role: FrameDialogActionRole.cancel,
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      FrameSnackBar.show(context, message: strings.diffUnavailable(error));
    }
  }
}

/// The diff of one file, shown in the companion pane in place of the Git list.
/// The pane above it, with the companion tabs, stays on screen.
///
/// Keys, all local to this view: Escape or Alt+Left goes back; Alt+Down and
/// Alt+Up go to the next and previous file, instantly. They sit in this
/// view's own [Focus], so a shell-level Escape layer can later call the same
/// [GitDiffPane.onBack] and [GitDiffPane.onOpenPath] actions from its own
/// registry without this widget changing.
class GitDiffPane extends ConsumerStatefulWidget {
  const GitDiffPane({
    super.key,
    required this.sessionId,
    required this.targets,
    required this.path,
    required this.revision,
    required this.writesOff,
    required this.onBack,
    required this.onOpenPath,
    required this.onStageToggle,
    required this.onDiscard,
  });

  final String sessionId;

  /// Every file the pane can step through, in list order. [path] must be one
  /// of them.
  final List<GitDiffTarget> targets;

  /// The file on screen.
  final String path;

  /// Changes on each Git status refresh, so the diff reloads after a stage.
  final int revision;

  /// True while writes are paused (read-only session, or Pi is working).
  final bool writesOff;

  final VoidCallback onBack;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<GitDiffTarget> onStageToggle;
  final ValueChanged<String> onDiscard;

  @override
  ConsumerState<GitDiffPane> createState() => _GitDiffPaneState();
}

class _GitDiffPaneState extends ConsumerState<GitDiffPane> {
  final _focus = FocusNode(debugLabel: 'git-diff-pane');

  /// Horizontal travel of the file swap: +8 px going forward, -8 px going back.
  double _slide = 0;

  /// Set by Alt+arrow. Keyboard file-to-file moves do not animate.
  bool _instant = false;

  @override
  void initState() {
    super.initState();
    // Take keyboard focus once the pane is on screen, so Escape and Alt+arrow
    // work straight after the diff opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _index => widget.targets.indexWhere((t) => t.path == widget.path);

  void _step(int delta, {required bool keyboard}) {
    final next = _index + delta;
    if (next < 0 || next >= widget.targets.length) return;
    setState(() {
      _slide = delta > 0 ? FrameSpace.x2 : -FrameSpace.x2;
      _instant = keyboard;
    });
    widget.onOpenPath(widget.targets[next].path);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (key == LogicalKeyboardKey.escape ||
        (alt && key == LogicalKeyboardKey.arrowLeft)) {
      widget.onBack();
    } else if (alt && key == LogicalKeyboardKey.arrowDown) {
      _step(1, keyboard: true);
    } else if (alt && key == LogicalKeyboardKey.arrowUp) {
      _step(-1, keyboard: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final index = _index;
    final target = widget.targets[index];
    final name = splitGitPath(target.path).name;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FramePaneHeader(
            title: name,
            subtitle: splitGitPath(target.path).dir,
            actions: [
              FrameIconAction(
                key: const ValueKey('git-diff-prev-btn'),
                icon: Icons.keyboard_arrow_up,
                tooltip: strings.gitDiffPreviousFile,
                onPressed: index > 0 ? () => _step(-1, keyboard: false) : null,
              ),
              FrameIconAction(
                key: const ValueKey('git-diff-next-btn'),
                icon: Icons.keyboard_arrow_down,
                tooltip: strings.gitDiffNextFile,
                onPressed: index < widget.targets.length - 1
                    ? () => _step(1, keyboard: false)
                    : null,
              ),
              FrameIconAction(
                key: const ValueKey('git-diff-stage-btn'),
                icon: target.stagedOnly
                    ? Icons.remove_circle_outline
                    : Icons.add,
                tooltip: target.stagedOnly
                    ? strings.unstageFileTooltip(target.path)
                    : strings.stageFileTooltip(target.path),
                onPressed: widget.writesOff
                    ? null
                    : () => widget.onStageToggle(target),
              ),
              FrameIconAction(
                key: const ValueKey('git-diff-discard-btn'),
                icon: Icons.undo,
                tooltip: strings.discardFileTooltip(target.path),
                onPressed: widget.writesOff
                    ? null
                    : () => widget.onDiscard(target.path),
              ),
              FrameIconAction(
                key: const ValueKey('git-diff-window-btn'),
                icon: Icons.open_in_new,
                tooltip: strings.gitDiffOpenWindow,
                onPressed: () => showGitDiffWindowDialog(
                  context: context,
                  ref: ref,
                  sessionId: widget.sessionId,
                  path: target.path,
                ),
              ),
            ],
            tabs: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
              child: Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('git-diff-back-btn'),
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, size: FrameSize.icon),
                    label: Text(strings.gitBackToChanges, style: text.label),
                  ),
                  const Spacer(),
                  Text(
                    strings.gitDiffPosition(index + 1, widget.targets.length),
                    key: const ValueKey('git-diff-position'),
                    style: text.mono.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FrameSwitcher(
              slide: _slide,
              animate: !_instant,
              child: _GitDiffFile(
                key: ValueKey('git-diff-file-${target.path}'),
                sessionId: widget.sessionId,
                path: target.path,
                revision: widget.revision,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The loaded diff of one file. Reloads when [revision] changes.
class _GitDiffFile extends ConsumerStatefulWidget {
  const _GitDiffFile({
    super.key,
    required this.sessionId,
    required this.path,
    required this.revision,
  });

  final String sessionId;
  final String path;
  final int revision;

  @override
  ConsumerState<_GitDiffFile> createState() => _GitDiffFileState();
}

class _GitDiffFileState extends ConsumerState<_GitDiffFile> {
  late Future<String> _diff = _load();

  Future<String> _load() => _loadDiffText(ref, widget.sessionId, widget.path);

  @override
  void didUpdateWidget(_GitDiffFile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _diff = _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    return FutureBuilder<String>(
      future: _diff,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(FrameSpace.x2),
            child: FrameErrorCallout(
              keyPrefix: 'git-diff',
              title: strings.diffUnavailableShort,
              error: describeError(snapshot.error!, strings),
              strings: strings,
              onRetry: () => setState(() => _diff = _load()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Center(
            child: Text(
              strings.gitDiffLoading,
              style: text.body.copyWith(color: tokens.textMuted),
            ),
          );
        }
        final diff = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(FrameSpace.x2),
          child: DiffBlock(
            diffText: diff.isEmpty ? strings.noDifferencesFound : diff,
            filename: widget.path,
          ),
        );
      },
    );
  }
}

/// Confirms discarding the working-tree changes of [path], previewing [diff].
/// Returns true when the user confirmed.
Future<bool?> showGitDiscardDialog({
  required BuildContext context,
  required AppStrings strings,
  required String path,
  required String diff,
  required Map<String, dynamic>? status,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.discardAllChangesTitle),
      content: Builder(
        builder: (dialogContext) {
          final mediaSize = MediaQuery.sizeOf(dialogContext);
          return SizedBox(
            width: (mediaSize.width * 0.8).clamp(280.0, 640.0),
            height: (mediaSize.height * 0.6).clamp(240.0, 380.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.discardAllChangesWarning,
                  key: const ValueKey('discard-file-warning'),
                ),
                const SizedBox(height: FrameSpace.x2),
                Text(
                  '$path\n${status?['rootPath'] ?? '—'} · ${status?['branch'] ?? '—'}',
                ),
                const SizedBox(height: FrameSpace.x2),
                Expanded(
                  child: SingleChildScrollView(
                    child: DiffBlock(
                      diffText: diff.isEmpty
                          ? strings.diffUnavailableShort
                          : diff,
                      filename: path,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          key: const ValueKey('discard-file-cancel-btn'),
          autofocus: true,
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('discard-file-confirm-btn'),
          style: FilledButton.styleFrom(
            backgroundColor: dialogContext.tokens.danger,
            foregroundColor: dialogContext.tokens.surface,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(strings.discardChangesBtn),
        ),
      ],
    ),
  );
}
