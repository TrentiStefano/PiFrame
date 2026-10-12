import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final composerDraftProvider = StateProvider.family<String, String>(
  (ref, id) => '',
);

void appendComposerContext(WidgetRef ref, String sessionId, String context) {
  final draft = ref.read(composerDraftProvider(sessionId).notifier);
  final current = draft.state;
  final separator = current.isEmpty
      ? ''
      : current.endsWith('\n')
      ? '\n'
      : '\n\n';
  draft.state = '$current$separator$context';
}

void appendCodeSelectionToComposer(
  WidgetRef ref,
  String sessionId,
  String path,
  String source,
  TextSelection selection,
) {
  if (!selection.isValid || selection.isCollapsed) return;
  final text = source.substring(selection.start, selection.end);
  if (text.trim().isEmpty) return;
  final startLine =
      '\n'.allMatches(source.substring(0, selection.start)).length + 1;
  final endOffset = selection.end - 1;
  final endLine = '\n'.allMatches(source.substring(0, endOffset)).length + 1;
  final language = path.contains('.') ? path.split('.').last : '';
  var fence = '```';
  while (text.contains(fence)) {
    fence += '`';
  }
  appendComposerContext(
    ref,
    sessionId,
    'Code reference: `$path:$startLine-$endLine`\n$fence$language\n$text\n$fence',
  );
}

void appendFileMentionToComposer(WidgetRef ref, String sessionId, String path) {
  final draft = ref.read(composerDraftProvider(sessionId).notifier);
  final current = draft.state;
  final separator = current.isEmpty || current.endsWith(' ') ? '' : ' ';
  draft.state = '$current$separator@$path ';
}
