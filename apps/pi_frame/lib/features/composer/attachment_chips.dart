import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/daemon/attachment_upload.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../domain/session/attachment_model.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_icon_action.dart';

class WebLinkInputDialog extends ConsumerStatefulWidget {
  const WebLinkInputDialog({super.key});

  static Future<ChatAttachment?> show(BuildContext context) {
    return showFrameDialogBuilder<ChatAttachment>(
      context: context,
      builder: (ctx) => const WebLinkInputDialog(),
    );
  }

  @override
  ConsumerState<WebLinkInputDialog> createState() => _WebLinkInputDialogState();
}

class _WebLinkInputDialogState extends ConsumerState<WebLinkInputDialog> {
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
    final strings = ref.read(appStringsProvider);
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() => _error = strings.attEnterValidUrl);
      return;
    }

    String formattedUrl = rawUrl;
    if (!formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }

    final uri = Uri.tryParse(formattedUrl);
    if (uri == null || !uri.hasAuthority) {
      setState(() => _error = strings.attInvalidUrlFormat);
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
    final strings = ref.watch(appStringsProvider);
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
                    child: Icon(Icons.link_outlined, size: FrameSize.iconLg, color: tokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    strings.attAddWebLinkTitle,
                    style: FrameText.of(context).title.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.bold, fontFamily: tokens.headingFontFamily),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('weblink-dialog-url-field'),
                controller: _urlController,
                autofocus: true,
                style: FrameText.of(context).body.copyWith(color: tokens.textPrimary, fontFamily: tokens.monoFontFamily),
                decoration: InputDecoration(
                  labelText: strings.attUrlFieldLabel,
                  hintText: 'https://example.com/docs',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.language_outlined, size: FrameSize.icon),
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
                style: FrameText.of(context).body.copyWith(color: tokens.textPrimary),
                decoration: InputDecoration(
                  labelText: strings.attTitleOptional,
                  hintText: strings.attTitleHint,
                  prefixIcon: const Icon(Icons.label_outlined, size: FrameSize.icon),
                  filled: true,
                  fillColor: tokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: FrameSpace.x4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.cancel, style: TextStyle(color: tokens.textMuted)),
                  ),
                  const SizedBox(width: FrameSpace.x2),
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
                    child: Text(strings.attAddLinkAction),
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

class ImagePreviewDialog extends ConsumerWidget {
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
    return showFrameDialogBuilder<void>(
      context: context,
      builder: (ctx) => ImagePreviewDialog(pathOrUrl: pathOrUrl, title: title),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);

    return Dialog(
      key: const ValueKey('image-lightbox-dialog'),
      backgroundColor: tokens.background.withValues(alpha: 0),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: FrameSpace.x6, vertical: FrameSpace.x6),
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
                color: tokens.overlay,
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
                padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x4, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: tokens.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: FrameSize.iconLg, color: tokens.accent),
                    const SizedBox(width: FrameSpace.x2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FrameText.of(context).bodyLarge.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            pathOrUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FrameText.of(context).caption.copyWith(color: tokens.textMuted, fontFamily: tokens.monoFontFamily),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_outlined, size: FrameSize.iconLg, color: tokens.textMuted),
                      tooltip: strings.attClosePreviewTooltip,
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
                    color: tokens.overlay,
                    child: InteractiveViewer(
                      maxScale: 5.0,
                      minScale: 0.5,
                      child: Center(
                        child: buildAttachmentImage(
                          pathOrUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, err, stack) => _buildError(context, tokens, strings),
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

  Widget _buildError(
    BuildContext context,
    FrameTokens tokens,
    AppStrings strings,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: tokens.danger),
        const SizedBox(height: FrameSpace.x2),
        Text(
          strings.attImageLoadError,
          style: FrameText.of(context).body.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}

class AttachmentChip extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);

    if (attachment.isImage) {
      return _buildImageThumbnail(context, tokens, strings);
    }

    if (attachment.isWebLink) {
      return _buildWebLinkChip(context, tokens, strings);
    }

    return _buildFileChip(context, tokens, strings);
  }

  /// Remove control: a focusable 28 px target (plan 2.6), so the chip can be cleared by keyboard.
  Widget _removeAction(AppStrings strings) {
    return FrameIconAction(
      key: ValueKey('attachment-remove-${attachment.id}'),
      icon: Icons.close_outlined,
      tooltip: strings.composerRemoveAttachmentTooltip,
      onPressed: onRemove,
    );
  }

  Widget _buildFileChip(BuildContext context, FrameTokens tokens, AppStrings strings) {
    return Container(
      key: ValueKey('attachment-file-${attachment.id}'),
      // An editable chip carries a 28 px remove target, so it takes no extra vertical padding.
      padding: EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: isEditable ? 0 : 4),
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
            size: FrameSize.iconSm,
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
                style: FrameText.of(context).caption.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w500, fontFamily: tokens.monoFontFamily),
              ),
            ),
          ),
          if (isEditable) ...[
            const SizedBox(width: 2),
            _removeAction(strings),
          ],
        ],
      ),
    );
  }

  Widget _buildWebLinkChip(BuildContext context, FrameTokens tokens, AppStrings strings) {
    return InkWell(
      key: ValueKey('attachment-link-${attachment.id}'),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      onTap: isEditable ? null : _handleLinkTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: FrameSpace.x1),
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
              Icons.link_outlined,
              size: FrameSize.iconSm,
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
                  style: FrameText.of(context).caption.copyWith(color: tokens.syntaxKeyword, fontWeight: FontWeight.w600, decoration: isEditable ? null : TextDecoration.underline),
                ),
              ),
            ),
            if (isEditable) ...[
              const SizedBox(width: 2),
              _removeAction(strings),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, FrameTokens tokens, AppStrings strings) {
    return Stack(
      key: ValueKey('attachment-image-${attachment.id}'),
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: strings.attClickToExpand(attachment.name),
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
                child: buildAttachmentImage(
                  attachment.pathOrUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      key: ValueKey('attachment-image-invalid-${attachment.id}'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          size: FrameSize.icon,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          strings.attImageInvalid,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FrameText.of(context).caption.copyWith(
                            color: tokens.textMuted,
                            height: 1,
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
        if (isEditable)
          Positioned(
            top: -10,
            right: -10,
            child: _removeAction(strings),
          ),
      ],
    );
  }
}

Widget buildAttachmentImage(
  String pathOrUrl, {
  double? width,
  double? height,
  required BoxFit fit,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  if (pathOrUrl.startsWith('data:')) {
    final uri = Uri.tryParse(pathOrUrl);
    final bytes = uri?.data?.contentAsBytes();
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
  }
  if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
    return Image.network(
      pathOrUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  if (kIsWeb) {
    // The file lives on the daemon host: preview it through the authenticated blob endpoint.
    final blobId = blobIdFromPath(pathOrUrl);
    if (blobId != null) {
      return Image.network(
        Uri.base.resolve('/api/blobs/$blobId').toString(),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
  }
  if (!kIsWeb) {
    return Image.file(
      File(pathOrUrl),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return Builder(
    builder: (ctx) => errorBuilder(ctx, StateError('Unsupported image source'), null),
  );
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
      padding: const EdgeInsets.only(bottom: FrameSpace.x2),
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
