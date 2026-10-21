import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_frame/data/update/github_update_client.dart';
import 'package:pi_frame/domain/update/update_models.dart';

void main() {
  group('GithubUpdateClient', () {
    test('fetches latest release successfully on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'api.github.com');
        expect(request.url.path, '/repos/TrentiStefano/piframe/releases/latest');
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.4.0',
            'name': 'PiFrame v1.4.0',
            'body': 'Initial update support',
            'html_url': 'https://github.com/TrentiStefano/piframe/releases/tag/v1.4.0',
            'assets': [
              {
                'name': 'PiFrame-Setup-1.4.0-windows-x64.exe',
                'browser_download_url': 'https://github.com/TrentiStefano/piframe/releases/download/v1.4.0/PiFrame-Setup-1.4.0-windows-x64.exe',
                'size': 1000,
              }
            ],
          }),
          200,
        );
      });

      final client = GithubUpdateClient(client: mockClient);
      final release = await client.fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.tagName, 'v1.4.0');
      expect(release.name, 'PiFrame v1.4.0');
      expect(release.assets.length, 1);
    });

    test('returns null when no release is found (404)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final client = GithubUpdateClient(client: mockClient);
      final release = await client.fetchLatestRelease();
      expect(release, isNull);
    });

    test('throws friendly UpdateException on rate limit (403)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('API rate limit exceeded', 403);
      });

      final client = GithubUpdateClient(client: mockClient);
      expect(
        () => client.fetchLatestRelease(),
        throwsA(isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('Limite di richieste GitHub raggiunto'),
        )),
      );
    });

    test('rejects unapproved download host for security', () async {
      final client = GithubUpdateClient();
      const maliciousAsset = ReleaseAsset(
        name: 'payload.exe',
        downloadUrl: 'https://malicious-site.com/payload.exe',
        size: 500,
        contentType: 'application/octet-stream',
      );

      final tempDir = Directory.systemTemp.createTempSync('pi_frame_sec_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      expect(
        () => client.downloadAsset(
          asset: maliciousAsset,
          destinationPath: '${tempDir.path}/payload.exe',
        ).toList(),
        throwsA(isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('dominio non autorizzato'),
        )),
      );
    });

    test('rejects insecure HTTP download URL for security', () async {
      final client = GithubUpdateClient();
      const insecureAsset = ReleaseAsset(
        name: 'payload.exe',
        downloadUrl: 'http://github.com/TrentiStefano/piframe/releases/download/v1.4.0/test.exe',
        size: 500,
        contentType: 'application/octet-stream',
      );

      final tempDir = Directory.systemTemp.createTempSync('pi_frame_sec_test2');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      expect(
        () => client.downloadAsset(
          asset: insecureAsset,
          destinationPath: '${tempDir.path}/test.exe',
        ).toList(),
        throwsA(isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('URL di download non valido'),
        )),
      );
    });

    test('sanitizes filenames correctly', () {
      expect(GithubUpdateClient.sanitizeFilename('test.exe'), 'test.exe');
      expect(
        GithubUpdateClient.sanitizeFilename('../../etc/passwd.exe'),
        'passwd.exe',
      );
      expect(
        GithubUpdateClient.sanitizeFilename('weird;name!file.deb'),
        'weird_name_file.deb',
      );
    });
  });
}
