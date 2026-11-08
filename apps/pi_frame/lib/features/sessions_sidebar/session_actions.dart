import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../workspace/repository_workspace.dart';
import 'pinned_sessions_provider.dart';
import 'removed_repos_provider.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../ui/frame_snack_bar.dart';

Future<String?> _chooseSessionDirectory(
  BuildContext context,
  String initialDirectory,
) => showDialog<String>(
  context: context,
  builder: (_) => _SessionDirectoryDialog(initialDirectory: initialDirectory),
);

class _SessionDirectoryDialog extends ConsumerStatefulWidget {
  const _SessionDirectoryDialog({required this.initialDirectory});
  final String initialDirectory;

  @override
  ConsumerState<_SessionDirectoryDialog> createState() =>
      _SessionDirectoryDialogState();
}

class _SessionDirectoryDialogState extends ConsumerState<_SessionDirectoryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDirectory,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    try {
      final directory = await getDirectoryPath();
      if (mounted && directory != null) {
        setState(() => _controller.text = directory);
      }
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: ref.read(appStringsProvider).directoryNotAvailable(error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return AlertDialog(
      title: Text(strings.newSessionDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('new-session-cwd'),
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: strings.workingDirectoryLabel,
              hintText: 'C:\\Projects\\my-project',
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            Text(
              strings.browserPathNotice,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!kIsWeb)
          TextButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(strings.chooseFolderAction),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text.trim()),
          child: Text(strings.createAction),
        ),
      ],
    );
  }
}

Future<void> createSession(
  BuildContext context,
  WidgetRef ref, {
  String? name,
  String? cwd,
}) async {
  final client = ref.read(pcpClientProvider);
  if (client == null) return;
  if (!await resolveDirtyRepository(
    context,
    ref,
    ref.read(activeSessionIdProvider),
  )) {
    return;
  }
  if (!context.mounted) return;

  var workingDirectory = cwd;
  if (workingDirectory == null) {
    final activeId = ref.read(activeSessionIdProvider);
    final initialDirectory = activeId == null
        ? ''
        : ref.read(sessionStateFamily(activeId)).cwd;
    workingDirectory = await _chooseSessionDirectory(context, initialDirectory);
  }
  if (!context.mounted) return;
  if (workingDirectory == null || workingDirectory.trim().isEmpty) return;

  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await client.sendCommand(
      PcpCommand(
        protocol: 1,
        id: 'cmd_$now',
        ts: now,
        commandId: PcpClient.newCommandId('crt'),
        type: 'session.create',
        payload: {'name': ?name, 'cwd': workingDirectory.trim()},
      ),
    );
    if (!context.mounted) return;
    final data = (result['data'] as Map<String, dynamic>?) ?? result;
    final session = (data['session'] as Map<String, dynamic>?) ?? data;
    final id = (session['id'] ?? data['id']) as String?;
    if (id != null) {
      if (!await switchSessionSafely(context, ref, id)) return;
      ref.invalidate(sessionListProvider);
    }
  } catch (error) {
    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: ref.read(appStringsProvider).creationFailedNotice(error),
      );
    }
  }
}

Future<void> deleteSessionWithConfirmation(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required String sessionName,
}) async {
  final strings = ref.read(appStringsProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final tokens = ctx.tokens;
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: tokens.danger, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(strings.deleteSessionDialogTitle)),
          ],
        ),
        content: Text(
          strings.deleteSessionConfirmBody(sessionName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.surface,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.deleteAction),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final client = ref.read(pcpClientProvider);
  if (client == null) return;

  try {
    await client.deleteSession(sessionId);
    if (ref.read(activeSessionIdProvider) == sessionId) {
      ref.read(activeSessionIdProvider.notifier).state = null;
    }
    ref.read(pinnedSessionsProvider.notifier).unpin(sessionId);

    ref.invalidate(sessionListProvider);

    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: strings.sessionDeletedNotice(sessionName),
      );
    }
  } catch (error) {
    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: strings.deletionFailedNotice(error),
      );
    }
  }
}

Future<void> removeRepoWithConfirmation(
  BuildContext context,
  WidgetRef ref, {
  required String folder,
  required String repoName,
  required List<Map<String, dynamic>> folderSessions,
}) async {
  final strings = ref.read(appStringsProvider);
  // Step 1: Choice dialog
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final tokens = ctx.tokens;
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_delete_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.removeRepoDialogTitle(repoName),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.repoSessionsCountNotice(folderSessions.length),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            InkWell(
              key: const ValueKey('hide-repo-only-btn'),
              onTap: () => Navigator.pop(ctx, 'hide'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.visibility_off_outlined, color: tokens.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.removeOnlyFromViewTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings.removeOnlyFromViewSubtitle,
                            style: TextStyle(fontSize: 11, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              key: const ValueKey('delete-all-repo-sessions-btn'),
              onTap: () => Navigator.pop(ctx, 'delete_all'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.danger.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_outlined, color: tokens.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.deleteAllRepoSessionsTitle,
                            style: TextStyle(fontWeight: FontWeight.bold, color: tokens.danger, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings.deleteAllRepoSessionsSubtitle,
                            style: TextStyle(fontSize: 11, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
        ],
      );
    },
  );

  if (choice == null || !context.mounted) return;

  if (choice == 'hide') {
    ref.read(removedReposProvider.notifier).removeRepo(folder);
    ref.invalidate(sessionListProvider);
    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: strings.repoRemovedNotice(repoName),
        action: SnackBarAction(
          label: strings.restoreAction,
          onPressed: () {
            ref.read(removedReposProvider.notifier).restoreRepo(folder);
            ref.invalidate(sessionListProvider);
          },
        ),
      );
    }
    return;
  }

  if (choice == 'delete_all') {
    // Step 2: Second warning with type "delete" box
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteRepoConfirmDialog(
        folder: folder,
        repoName: repoName,
        sessionsCount: folderSessions.length,
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    try {
      final activeId = ref.read(activeSessionIdProvider);
      for (final s in folderSessions) {
        final id = s['id'] as String?;
        if (id != null) {
          try {
            await client.deleteSession(id);
            if (id == activeId) {
              ref.read(activeSessionIdProvider.notifier).state = null;
            }
            ref.read(pinnedSessionsProvider.notifier).unpin(id);
          } catch (_) {}
        }
      }

      ref.read(removedReposProvider.notifier).removeRepo(folder);
      ref.invalidate(sessionListProvider);

      if (context.mounted) {
        FrameSnackBar.show(
          context,
          message: strings.allRepoSessionsDeletedNotice(repoName),
        );
      }
    } catch (error) {
      if (context.mounted) {
        FrameSnackBar.show(
          context,
          message: strings.deletionErrorNotice(error),
        );
      }
    }
  }
}

class _DeleteRepoConfirmDialog extends ConsumerStatefulWidget {
  final String folder;
  final String repoName;
  final int sessionsCount;

  const _DeleteRepoConfirmDialog({
    required this.folder,
    required this.repoName,
    required this.sessionsCount,
  });

  @override
  ConsumerState<_DeleteRepoConfirmDialog> createState() =>
      _DeleteRepoConfirmDialogState();
}

class _DeleteRepoConfirmDialogState extends ConsumerState<_DeleteRepoConfirmDialog> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final canDelete = _textController.text.trim().toLowerCase() == 'delete';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: tokens.danger, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(strings.warningDeletionTitle)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.deleteRepoWarningBody(widget.sessionsCount, widget.folder),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'delete',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.danger,
            foregroundColor: tokens.surface,
          ),
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          child: Text(strings.deleteAllAction),
        ),
      ],
    );
  }
}

