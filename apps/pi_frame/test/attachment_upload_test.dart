import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_frame/data/daemon/attachment_upload.dart';
import 'package:pi_frame/domain/session/attachment_model.dart';
import 'package:pi_frame/features/composer/attachment_ingest.dart';

const _id = 'blob_0123456789abcdef0123456789abcdef';

void main() {
  group('blobIdFromPath', () {
    test('extracts the id from Windows and POSIX daemon paths', () {
      expect(blobIdFromPath('C:\\Users\\me\\.piframe\\blobs\\$_id\\shot.png'), _id);
      expect(blobIdFromPath('/home/me/.piframe/blobs/$_id/shot.png'), _id);
      expect(blobIdFromPath('/home/me/other/shot.png'), isNull);
      expect(blobIdFromPath('blob:https://host/6ef106b5'), isNull);
    });
  });

  group('uploadAttachmentBytes', () {
    test('posts the bytes with name and mime and returns the host path', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'blobId': _id,
            'name': 'IMG 7660.png',
            'path': '/home/me/.piframe/blobs/$_id/IMG 7660.png',
            'size': 3,
          }),
          201,
        );
      });

      final blob = await uploadAttachmentBytes(
        name: 'IMG 7660.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        client: client,
        base: Uri.parse('https://desktop.ts.net/'),
      );

      expect(seen.url.toString(), 'https://desktop.ts.net/api/blobs');
      expect(seen.headers['Content-Type'], 'image/png');
      expect(Uri.decodeComponent(seen.headers['X-File-Name']!), 'IMG 7660.png');
      expect(seen.bodyBytes, [1, 2, 3]);
      expect(blob.path, contains(_id));
    });

    test('maps a view-mode rejection to a control-mode error', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': false,
            'code': 'REMOTE_FORBIDDEN',
            'error': 'File uploads require control mode permission',
          }),
          403,
        ),
      );
      await expectLater(
        uploadAttachmentBytes(
          name: 'a.png',
          bytes: Uint8List(1),
          client: client,
          base: Uri.parse('https://h/'),
        ),
        throwsA(
          isA<AttachmentUploadException>().having(
            (e) => e.requiresControlMode,
            'requiresControlMode',
            isTrue,
          ),
        ),
      );
    });

    test('reports an oversized upload', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': false, 'error': 'Payload Too Large (max 50MB)'}),
          413,
        ),
      );
      await expectLater(
        uploadAttachmentBytes(
          name: 'a.bin',
          bytes: Uint8List(1),
          client: client,
          base: Uri.parse('https://h/'),
        ),
        throwsA(
          isA<AttachmentUploadException>().having((e) => e.code, 'code', 'TOO_LARGE'),
        ),
      );
    });
  });

  group('ingestPickedFile', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pf-ingest-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('desktop keeps the local path and does not upload', () async {
      var uploads = 0;
      final attachment = await ingestPickedFile(
        XFile('/tmp/notes.txt', name: 'notes.txt'),
        idPrefix: 'att',
        index: 0,
        isWeb: () => false,
        uploader: (n, b, m) async {
          uploads++;
          throw StateError('must not upload on desktop');
        },
      );
      expect(uploads, 0);
      expect(attachment.pathOrUrl, '/tmp/notes.txt');
      expect(attachment.type, AttachmentType.externalFile);
    });

    test('browser uploads the bytes and references the host path', () async {
      final file = File('${tmp.path}/IMG_7660.png')..writeAsBytesSync([9, 9]);
      Uint8List? sent;
      final attachment = await ingestPickedFile(
        XFile(file.path),
        idPrefix: 'att',
        index: 1,
        isWeb: () => true,
        uploader: (name, bytes, mime) async {
          sent = bytes;
          return UploadedBlob(
            blobId: _id,
            name: name,
            path: '/home/me/.piframe/blobs/$_id/$name',
            size: bytes.length,
          );
        },
      );
      expect(sent, [9, 9]);
      expect(attachment.type, AttachmentType.image);
      expect(attachment.name, 'IMG_7660.png');
      expect(attachment.pathOrUrl, startsWith('/home/me/.piframe/blobs/blob_'));
      expect(attachment.pathOrUrl.startsWith('blob:'), isFalse);
    });
  });
}
