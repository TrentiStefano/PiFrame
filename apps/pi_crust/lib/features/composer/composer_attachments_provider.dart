import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/session/attachment_model.dart';

final composerAttachmentsProvider =
    StateNotifierProvider.family<ComposerAttachmentsNotifier, List<ChatAttachment>, String>(
      (ref, sessionId) => ComposerAttachmentsNotifier(),
    );

class ComposerAttachmentsNotifier extends StateNotifier<List<ChatAttachment>> {
  ComposerAttachmentsNotifier() : super(const []);

  void add(ChatAttachment attachment) {
    if (!state.any((a) => a.pathOrUrl == attachment.pathOrUrl)) {
      state = [...state, attachment];
    }
  }

  void addAll(List<ChatAttachment> attachments) {
    final updated = List<ChatAttachment>.from(state);
    for (final a in attachments) {
      if (!updated.any((existing) => existing.pathOrUrl == a.pathOrUrl)) {
        updated.add(a);
      }
    }
    state = updated;
  }

  void remove(String attachmentId) {
    state = state.where((a) => a.id != attachmentId).toList();
  }

  void removeByPathOrUrl(String pathOrUrl) {
    state = state.where((a) => a.pathOrUrl != pathOrUrl).toList();
  }

  void clear() {
    state = const [];
  }
}
