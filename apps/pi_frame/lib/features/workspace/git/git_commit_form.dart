import 'package:flutter/material.dart';
import '../../../ui/precision.dart';
import 'package:flutter/services.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../domain/errors/user_facing_error.dart';
import '../../../ui/frame_error_callout.dart';

/// Soft guide for the commit subject, in characters. Past it the counter
/// turns the warning colour; the commit is still allowed.
const int gitCommitSubjectGuide = 72;

/// The commit message fields of the Git pane, shown inline above the remote
/// buttons: the subject, an optional body behind a toggle, and the error of a
/// failed commit.
///
/// Ctrl+Enter (Cmd+Enter on macOS) commits from either field. [onCommit] is
/// called when writes are allowed; [onCommit] itself checks the subject.
class GitCommitFields extends StatelessWidget {
  const GitCommitFields({
    super.key,
    required this.subject,
    required this.body,
    required this.bodyOpen,
    required this.canWrite,
    required this.strings,
    required this.onToggleBody,
    required this.onCommit,
    this.error,
  });

  final TextEditingController subject;
  final TextEditingController body;
  final bool bodyOpen;

  /// False while writes are paused: the fields are read-only then.
  final bool canWrite;

  final AppStrings strings;
  final VoidCallback onToggleBody;
  final VoidCallback onCommit;

  /// The error of the last failed commit, shown until the next attempt.
  final Object? error;

  void _commitFromKeyboard() {
    if (canWrite) onCommit();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final failure = error;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _commitFromKeyboard,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _commitFromKeyboard,
      },
      child: Column(
        key: const ValueKey('git-commit-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListenableBuilder(
            listenable: subject,
            builder: (context, _) {
              final length = subject.text.length;
              final over = length > gitCommitSubjectGuide;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('git-commit-subject'),
                    controller: subject,
                    enabled: canWrite,
                    maxLines: 1,
                    style: text.body.copyWith(color: tokens.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: FrameSpace.x2,
                        vertical: FrameSpace.x2,
                      ),
                      hintText: strings.commitSubjectLabel,
                    ),
                  ),
                  // Body toggle and subject counter share one line, to keep the
                  // form short above the list.
                  Row(
                    children: [
                      TextButton(
                        key: const ValueKey('git-commit-body-toggle'),
                        onPressed: onToggleBody,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, FrameSize.hitMin),
                          padding: const EdgeInsets.symmetric(
                            horizontal: FrameSpace.x2,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          bodyOpen
                              ? strings.commitBodyHide
                              : strings.commitBodyShow,
                          style: text.label,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        strings.commitSubjectCount(
                          length,
                          gitCommitSubjectGuide,
                        ),
                        key: const ValueKey('git-commit-subject-counter'),
                        style: text.caption.copyWith(
                          color: over ? tokens.warning : tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          if (bodyOpen)
            TextField(
              key: const ValueKey('git-commit-body'),
              controller: body,
              enabled: canWrite,
              minLines: 2,
              maxLines: 4,
              style: text.body.copyWith(color: tokens.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FrameSpace.x2,
                  vertical: FrameSpace.x2,
                ),
                hintText: strings.commitBodyLabel,
              ),
            ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: FrameSpace.x1),
              child: FrameErrorCallout(
                keyPrefix: 'git-commit',
                title: strings.commitFailedTitle,
                error: describeError(failure, strings),
                strings: strings,
                onRetry: canWrite ? onCommit : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// The Commit button. Full width in the compact layout, under the four remote
/// buttons; right-aligned on wide layouts.
class GitCommitButton extends StatelessWidget {
  const GitCommitButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.fullWidth,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool enabled;
  final bool fullWidth;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Tooltip(
      message: tooltip,
      child: PressFeedback(enabled: (enabled ? onPressed : null) != null, child: FilledButton(
        key: const ValueKey('git-commit-btn'),
        onPressed: enabled ? onPressed : null,
        child: Text(label),
      )),
    );
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return Align(alignment: Alignment.centerRight, child: button);
  }
}
