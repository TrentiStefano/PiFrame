import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../domain/session/attachment_model.dart';
import '../composer/composer_attachments_provider.dart';

class ChatDropTarget extends ConsumerStatefulWidget {
  final String sessionId;
  final Widget child;

  const ChatDropTarget({
    super.key,
    required this.sessionId,
    required this.child,
  });

  @override
  ConsumerState<ChatDropTarget> createState() => _ChatDropTargetState();
}

class _ChatDropTargetState extends ConsumerState<ChatDropTarget> {
  bool _isDragging = false;

  void _onDragDone(DropDoneDetails detail) {
    setState(() => _isDragging = false);

    if (detail.files.isEmpty) return;

    final newAttachments = <ChatAttachment>[];
    for (var i = 0; i < detail.files.length; i++) {
      final f = detail.files[i];
      final isImg = isImageExtension(f.path);
      final filename = f.name.isNotEmpty && !f.name.contains('/') && !f.name.contains(r'\')
          ? f.name
          : f.path.split(RegExp(r'[/\\]')).last;
      newAttachments.add(
        ChatAttachment(
          id: 'att_drop_${DateTime.now().microsecondsSinceEpoch}_$i',
          type: isImg ? AttachmentType.image : AttachmentType.externalFile,
          name: filename,
          pathOrUrl: f.path,
        ),
      );
    }

    ref
        .read(composerAttachmentsProvider(widget.sessionId).notifier)
        .addAll(newAttachments);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newAttachments.length == 1
              ? 'File allegato: ${newAttachments.first.name}'
              : '${newAttachments.length} file allegati al messaggio',
        ),
        backgroundColor: context.tokens.surfaceElevated,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return DropTarget(
      key: const ValueKey('chat-drop-target'),
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: _onDragDone,
      child: Stack(
        children: [
          widget.child,
          // Animated Drop Overlay with scale (0.96 -> 1.0) and opacity (0.0 -> 1.0)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_isDragging,
              child: AnimatedOpacity(
                key: const ValueKey('chat-drop-overlay-opacity'),
                duration: const Duration(milliseconds: 200),
                curve: _isDragging ? Curves.easeOutCubic : Curves.easeInCubic,
                opacity: _isDragging ? 1.0 : 0.0,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  curve: _isDragging ? Curves.easeOutCubic : Curves.easeInCubic,
                  scale: _isDragging ? 1.0 : 0.96,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(tokens.radiusLg),
                      border: Border.all(
                        color: tokens.accent,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.2),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          border: Border.all(color: tokens.borderStrong),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: tokens.accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.file_download_outlined,
                                size: 36,
                                color: tokens.accent,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Rilascia i file qui per allegarli',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: tokens.headingFontFamily,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Supporta file del repository, file locali e immagini',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
