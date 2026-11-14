import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/daemon/daemon_providers.dart';
import '../../../domain/session/agent_status.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';

import '../repository_state.dart';

Future<bool> switchSessionSafely(
  BuildContext context,
  WidgetRef ref,
  String nextId,
) async {
  final currentId = ref.read(activeSessionIdProvider);
  if (currentId == nextId) return true;
  if (!context.mounted) return false;
  if (!await resolveDirtyRepository(context, ref, currentId)) return false;
  if (!context.mounted) return false;
  ref.read(activeSessionIdProvider.notifier).state = nextId;
  return true;
}

Future<bool> resolveDirtyRepository(
  BuildContext context,
  WidgetRef ref,
  String? sessionId,
) async {
  if (sessionId == null) return true;
  final controller = ref.read(repositoryStateProvider(sessionId).notifier);
  if (!controller.currentState.dirty) return true;
  final tokens = context.tokens;
  final session = ref.read(sessionStateFamily(sessionId));
  final strings = ref.read(appStringsProvider);
  final writesBlocked = sessionWritesBlocked(session);
  final canSave = !writesBlocked && ref.read(pcpClientProvider) != null;
  final blockedReason = session.readOnly
      ? (session.readOnlyReason ?? strings.readOnlySessionLower)
      : writesBlocked
      ? session.agentStatus.label
      : strings.daemonNotConnectedLower;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: tokens.surface,
      title: Text(strings.unsavedChangesTitle),
      content: Text(
        canSave
            ? strings.unsavedChangesContentCanSave
            : strings.unsavedChangesContentBlocked(blockedReason),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cancel'),
          child: Text(strings.cancel),
        ),
        if (canSave)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(strings.discard),
          ),
        if (!canSave)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(strings.discard),
          ),
        if (canSave)
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(strings.save),
          ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'discard') {
    controller.discardDirty();
    return true;
  }
  if (choice != 'save') return false;
  try {
    for (final entry
        in controller.currentState.buffers.entries
            .where((entry) => entry.value.dirty)
            .toList()) {
      await saveRepositoryFile(context, ref, sessionId, entry.key);
      if (!context.mounted ||
          controller.currentState.buffers[entry.key]?.dirty == true) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> saveRepositoryFile(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  String path,
) async {
  final session = ref.read(sessionStateFamily(sessionId));
  final strings = ref.read(appStringsProvider);
  if (sessionWritesBlocked(session)) {
    throw StateError(
      session.readOnly
          ? (session.readOnlyReason ?? strings.readOnlySessionCapital)
          : session.agentStatus.label,
    );
  }
  final controller = ref.read(repositoryStateProvider(sessionId).notifier);
  try {
    await controller.save(path);
  } catch (error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('conflict') &&
        !message.contains('changed on disk') &&
        !message.contains('reload before saving')) {
      rethrow;
    }
    final disk = await controller.currentDisk(path);
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.fileModifiedExternallyTitle),
        content: Text(strings.fileModifiedExternallyContent(path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: Text(strings.keepChanges),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'reload'),
            child: Text(strings.reloadFromDisk),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
            child: Text(strings.overwriteExplicitly),
          ),
        ],
      ),
    );
    if (choice == 'reload') {
      controller.reload(path, disk.content, disk.revision);
    }
    if (choice == 'overwrite') {
      await controller.save(path, revisionOverride: disk.revision);
    }
    if (choice == 'keep') rethrow;
  }
}
