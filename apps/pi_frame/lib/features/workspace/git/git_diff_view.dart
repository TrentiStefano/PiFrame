import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/daemon/daemon_providers.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';
import '../../../ui/code/diff_block.dart';
import '../../../ui/frame_snack_bar.dart';

/// Loads the diff of [path] and shows it in a dialog.
Future<void> showGitDiffDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String sessionId,
  required String path,
}) async {
  final client = ref.read(pcpClientProvider);
  if (client == null) return;
  try {
    final result = await client.getWorkspaceDiff(sessionId, filePath: path);
    final diff = (result['data']?['diff'] ?? result['diff'])?.toString() ?? '';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.tokens;
        return Dialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            side: BorderSide(color: tokens.border, width: 1),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: context.tokens.monoFontFamily,
                            color: context.tokens.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: ref.read(appStringsProvider).closeDiffTooltip,
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DiffBlock(
                        diffText: diff.isEmpty
                            ? ref.read(appStringsProvider).noDifferencesFound
                            : diff,
                        filename: path,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } catch (error) {
    if (context.mounted) {
      final strings = ref.read(appStringsProvider);
      FrameSnackBar.show(context, message: strings.diffUnavailable(error));
    }
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
                const SizedBox(height: 8),
                Text(
                  '$path\n${status?['rootPath'] ?? '—'} · ${status?['branch'] ?? '—'}',
                ),
                const SizedBox(height: 8),
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
