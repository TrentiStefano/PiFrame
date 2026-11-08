import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'web_token_stub.dart' if (dart.library.html) 'web_token_html.dart';

/// Result of uploading an attachment to the daemon host.
class UploadedBlob {
  final String blobId;
  final String name;

  /// Absolute path on the machine running the daemon (what the agent can read).
  final String path;
  final int size;

  const UploadedBlob({
    required this.blobId,
    required this.name,
    required this.path,
    required this.size,
  });
}

class AttachmentUploadException implements Exception {
  final String message;
  final String? code;
  const AttachmentUploadException(this.message, {this.code});

  bool get requiresControlMode => code == 'REMOTE_FORBIDDEN';

  @override
  String toString() => message;
}

const _mimeByExtension = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'heic': 'image/heic',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'md': 'text/plain',
  'json': 'application/json',
};

String guessMimeType(String fileName, {String? declared}) {
  if (declared != null && declared.isNotEmpty) return declared;
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return _mimeByExtension[ext] ?? 'application/octet-stream';
}

/// Matches a path inside the daemon blob store: `.../blobs/blob_<32 hex>/<file>`.
final RegExp _blobPathRegex = RegExp(r'[\\/]blobs[\\/](blob_[a-f0-9]{32})[\\/]');

/// Returns the blob id when [pathOrUrl] points into the daemon blob store, else null.
String? blobIdFromPath(String pathOrUrl) =>
    _blobPathRegex.firstMatch(pathOrUrl)?.group(1);

/// Uploads [bytes] to the daemon (`POST /api/blobs`) of the origin the web app was loaded from.
/// Only meaningful in the browser: desktop clients reference local paths directly.
Future<UploadedBlob> uploadAttachmentBytes({
  required String name,
  required Uint8List bytes,
  String? mimeType,
  http.Client? client,
  Uri? base,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final http_ = client ?? http.Client();
  try {
    final token = await getWebDeviceToken();
    final response = await http_
        .post(
          (base ?? Uri.base).resolve('/api/blobs'),
          headers: {
            'Content-Type': guessMimeType(name, declared: mimeType),
            'X-File-Name': Uri.encodeComponent(name),
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: bytes,
        )
        .timeout(timeout);

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw AttachmentUploadException(
        body['error']?.toString() ?? 'Upload failed (HTTP ${response.statusCode})',
        code: body['code']?.toString() ??
            (response.statusCode == 413 ? 'TOO_LARGE' : null),
      );
    }
    final path = body['path']?.toString();
    final blobId = body['blobId']?.toString();
    if (path == null || path.isEmpty || blobId == null) {
      throw const AttachmentUploadException('Unexpected upload response');
    }
    return UploadedBlob(
      blobId: blobId,
      name: body['name']?.toString() ?? name,
      path: path,
      size: (body['size'] as num?)?.toInt() ?? bytes.length,
    );
  } on AttachmentUploadException {
    rethrow;
  } catch (e) {
    throw AttachmentUploadException(e.toString());
  } finally {
    if (client == null) http_.close();
  }
}
