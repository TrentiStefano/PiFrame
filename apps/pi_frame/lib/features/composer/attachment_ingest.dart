import 'dart:typed_data';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../data/daemon/attachment_upload.dart';
import '../../domain/session/attachment_model.dart';

/// Turns a picked/dropped file into a [ChatAttachment] the agent can actually read.
///
/// Desktop: the file already lives on the daemon host, so its path is used directly.
/// Browser/phone: [XFile.path] is a `blob:` URL that only exists in the browser tab, so the bytes
/// are uploaded to the daemon first and the resulting absolute path on the host is referenced.
Future<ChatAttachment> ingestPickedFile(
  XFile file, {
  required String idPrefix,
  required int index,
  bool forceImage = false,
  bool Function()? isWeb,
  Future<UploadedBlob> Function(String name, Uint8List bytes, String? mime)?
  uploader,
}) async {
  final id = '${idPrefix}_${DateTime.now().microsecondsSinceEpoch}_$index';
  final name = _displayName(file);
  final isImage = forceImage || isImageExtension(name) || _isImageMime(file.mimeType);

  if (!(isWeb?.call() ?? kIsWeb)) {
    return ChatAttachment(
      id: id,
      type: isImage ? AttachmentType.image : AttachmentType.externalFile,
      name: name,
      pathOrUrl: file.path,
    );
  }

  final bytes = await file.readAsBytes();
  final blob = uploader != null
      ? await uploader(name, bytes, file.mimeType)
      : await uploadAttachmentBytes(
          name: name,
          bytes: bytes,
          mimeType: file.mimeType,
        );
  return ChatAttachment(
    id: id,
    type: isImage ? AttachmentType.image : AttachmentType.externalFile,
    name: name,
    pathOrUrl: blob.path,
    sizeBytes: blob.size,
  );
}

bool _isImageMime(String? mime) => mime != null && mime.startsWith('image/');

/// Plain file name: some pickers report a full path in [XFile.name].
String _displayName(XFile file) {
  final raw = file.name.isNotEmpty ? file.name : file.path;
  return raw.split(RegExp(r'[/\\]')).last;
}
