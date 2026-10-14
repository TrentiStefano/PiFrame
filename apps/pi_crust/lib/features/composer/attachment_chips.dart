import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/session/attachment_model.dart';

class WebLinkInputDialog extends StatefulWidget {
  const WebLinkInputDialog({super.key});

  static Future<ChatAttachment?> show(BuildContext context) {
    return showDialog<ChatAttachment>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const WebLinkInputDialog(),
    );
  }

  @override
  State<WebLinkInputDialog> createState() => _WebLinkInputDialogState();
}

class _WebLinkInputDialogState extends State<WebLinkInputDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() => _error = 'Inserisci un URL valido');
      return;
    }

    String formattedUrl = rawUrl;
    if (!formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }

    final uri = Uri.tryParse(formattedUrl);
    if (uri == null || !uri.hasAuthority) {
      setState(() => _error = 'Formato URL non valido');
      return;
    }

    final rawName = _nameController.text.trim();
    final name = rawName.isNotEmpty ? rawName : formattedUrl;

    Navigator.of(context).pop(
      ChatAttachment(
        id: 'att_link_${DateTime.now().microsecondsSinceEpoch}',
        type: AttachmentType.webLink,
        name: name,
        pathOrUrl: formattedUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Dialog(
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(Icons.link, size: 18, color: tokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Aggiungi Link Web',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: tokens.headingFontFamily,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('weblink-dialog-url-field'),
                controller: _urlController,
                autofocus: true,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontFamily: tokens.monoFontFamily,
                ),
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com/docs',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.language, size: 16),
                  filled: true,
                  fillColor: tokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('weblink-dialog-name-field'),
                controller: _nameController,
                style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Titolo o etichetta (opzionale)',
                  hintText: 'Documentazione API, PR GitHub...',
                  prefixIcon: const Icon(Icons.label_outline, size: 16),
                  filled: true,
                  fillColor: tokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Annulla', style: TextStyle(color: tokens.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const ValueKey('weblink-dialog-submit-btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.accentContrast,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text('Aggiungi Link'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ImagePreviewDialog extends StatelessWidget {
  final String pathOrUrl;
  final String title;

  const ImagePreviewDialog({
    super.key,
    required this.pathOrUrl,
    required this.title,
  });

  static Future<void> show(
    BuildContext context, {
    required String pathOrUrl,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      barrierDismissible: true,
      builder: (ctx) => ImagePreviewDialog(pathOrUrl: pathOrUrl, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isLocal = !pathOrUrl.startsWith('http://') && !pathOrUrl.startsWith('https://');

    return Dialog(
      key: const ValueKey('image-lightbox-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 960,
          maxHeight: 780,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            border: Border.all(color: tokens.borderStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: tokens.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 18, color: tokens.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            pathOrUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: tokens.textMuted),
                      tooltip: 'Chiudi anteprima',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Image Viewer with interactive pan & zoom
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(tokens.radiusLg),
                    bottomRight: Radius.circular(tokens.radiusLg),
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: InteractiveViewer(
                      maxScale: 5.0,
                      minScale: 0.5,
                      child: Center(
                        child: isLocal
                            ? Image.file(
                                File(pathOrUrl),
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => _buildError(tokens),
                              )
                            : Image.network(
                                pathOrUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => _buildError(tokens),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(CrustTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: tokens.danger),
        const SizedBox(height: 8),
        Text(
          'Impossibile caricare l\'immagine',
          style: TextStyle(color: tokens.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

class AttachmentChip extends StatelessWidget {
  final ChatAttachment attachment;
  final bool isEditable;
  final VoidCallback? onRemove;
  final VoidCallback? onImageTap;

  const AttachmentChip({
    super.key,
    required this.attachment,
    this.isEditable = false,
    this.onRemove,
    this.onImageTap,
  });

  Future<void> _handleLinkTap() async {
    final uri = Uri.tryParse(attachment.pathOrUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (attachment.isImage) {
      return _buildImageThumbnail(context, tokens);
    }

    if (attachment.isWebLink) {
      return _buildWebLinkChip(context, tokens);
    }

    return _buildFileChip(context, tokens);
  }

  Widget _buildFileChip(BuildContext context, CrustTokens tokens) {
    return Container(
      key: ValueKey('attachment-file-${attachment.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: tokens.borderStrong,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.type == AttachmentType.repoFile
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
            size: 14,
            color: tokens.accent,
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: attachment.pathOrUrl,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
            ),
          ),
          if (isEditable) ...[
            const SizedBox(width: 4),
            InkWell(
              key: ValueKey('attachment-remove-${attachment.id}'),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: tokens.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebLinkChip(BuildContext context, CrustTokens tokens) {
    return InkWell(
      key: ValueKey('attachment-link-${attachment.id}'),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      onTap: isEditable ? null : _handleLinkTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: tokens.syntaxKeyword.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link,
              size: 14,
              color: tokens.syntaxKeyword,
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: attachment.pathOrUrl,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.syntaxKeyword,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    decoration: isEditable ? null : TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (isEditable) ...[
              const SizedBox(width: 4),
              InkWell(
                key: ValueKey('attachment-remove-${attachment.id}'),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12, color: tokens.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, CrustTokens tokens) {
    final isLocal =
        !attachment.pathOrUrl.startsWith('http://') &&
        !attachment.pathOrUrl.startsWith('https://');

    return Stack(
      key: ValueKey('attachment-image-${attachment.id}'),
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: '${attachment.name} (Clicca per ingrandire)',
          child: InkWell(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            onTap: onImageTap ??
                () => ImagePreviewDialog.show(
                      context,
                      pathOrUrl: attachment.pathOrUrl,
                      title: attachment.name,
                    ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.borderStrong, width: 1.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radiusSm - 1),
                child: isLocal
                    ? Image.file(
                        File(attachment.pathOrUrl),
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Icon(
                          Icons.image_not_supported_outlined,
                          size: 22,
                          color: tokens.textMuted,
                        ),
                      )
                    : Image.network(
                        attachment.pathOrUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Icon(
                          Icons.image_not_supported_outlined,
                          size: 22,
                          color: tokens.textMuted,
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (isEditable)
          Positioned(
            top: -4,
            right: -4,
            child: InkWell(
              key: ValueKey('attachment-remove-${attachment.id}'),
              borderRadius: BorderRadius.circular(10),
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.borderStrong, width: 1),
                ),
                child: Icon(Icons.close, size: 10, color: tokens.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class AttachmentListBar extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final bool isEditable;
  final void Function(ChatAttachment attachment)? onRemove;
  final void Function(ChatAttachment attachment)? onImageTap;

  const AttachmentListBar({
    super.key,
    required this.attachments,
    this.isEditable = false,
    this.onRemove,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in attachments)
            AttachmentChip(
              attachment: a,
              isEditable: isEditable,
              onRemove: onRemove != null ? () => onRemove!(a) : null,
              onImageTap: onImageTap != null ? () => onImageTap!(a) : null,
            ),
        ],
      ),
    );
  }
}
