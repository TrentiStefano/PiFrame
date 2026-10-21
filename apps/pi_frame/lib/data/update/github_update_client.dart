import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../domain/update/update_models.dart';

class DownloadProgress {
  final int downloadedBytes;
  final int totalBytes;
  final double fraction;

  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.fraction,
  });
}

class UpdateException implements Exception {
  final String message;
  final int? statusCode;

  const UpdateException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

abstract class UpdateClient {
  Future<AppRelease?> fetchLatestRelease();
  Stream<DownloadProgress> downloadAsset({
    required ReleaseAsset asset,
    required String destinationPath,
    Future<void>? cancelSignal,
  });
}

class GithubUpdateClient implements UpdateClient {
  final http.Client _client;
  final String repository;

  static const defaultRepository = 'TrentiStefano/piframe';

  GithubUpdateClient({
    http.Client? client,
    this.repository = defaultRepository,
  }) : _client = client ?? http.Client();

  Uri get _releasesLatestUri =>
      Uri.https('api.github.com', '/repos/$repository/releases/latest');

  bool _isAllowedHost(String host) {
    final lower = host.toLowerCase();
    return lower == 'github.com' ||
        lower == 'api.github.com' ||
        lower == 'objects.githubusercontent.com' ||
        lower == 'raw.githubusercontent.com' ||
        lower.endsWith('.githubusercontent.com') ||
        lower.endsWith('.github.com');
  }

  @override
  Future<AppRelease?> fetchLatestRelease() async {
    final uri = _releasesLatestUri;
    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'PiFrame-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return AppRelease.fromJson(data);
        }
        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateException(
          'Limite di richieste GitHub raggiunto. Riprova più tardi.',
          403,
        );
      } else {
        throw UpdateException(
          'Errore durante il controllo degli aggiornamenti (HTTP ${response.statusCode})',
          response.statusCode,
        );
      }
    } on SocketException {
      throw const UpdateException(
        'Impossibile contattare GitHub. Verifica la connessione a Internet.',
      );
    } on TimeoutException {
      throw const UpdateException(
        'La richiesta di aggiornamento a GitHub è scaduta (timeout).',
      );
    } catch (e) {
      if (e is UpdateException) rethrow;
      throw UpdateException('Errore imprevisto durante il controllo: $e');
    }
  }

  @override
  Stream<DownloadProgress> downloadAsset({
    required ReleaseAsset asset,
    required String destinationPath,
    Future<void>? cancelSignal,
  }) async* {
    final uri = Uri.tryParse(asset.downloadUrl);
    if (uri == null || uri.scheme != 'https' || !_isAllowedHost(uri.host)) {
      throw const UpdateException(
        'URL di download non valido o dominio non autorizzato per sicurezza.',
      );
    }

    final destFile = File(destinationPath);
    // Sanitize directory creation
    final parentDir = destFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Accept': 'application/octet-stream',
        'User-Agent': 'PiFrame-App',
      });

    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode != 200) {
      throw UpdateException(
        'Errore durante il download del file di aggiornamento (HTTP ${streamedResponse.statusCode})',
        streamedResponse.statusCode,
      );
    }

    final totalBytes = streamedResponse.contentLength ?? asset.size;
    var downloadedBytes = 0;

    final sink = destFile.openWrite();
    var isCancelled = false;

    final cancelSub = cancelSignal?.asStream().listen((_) {
      isCancelled = true;
    });

    try {
      await for (final chunk in streamedResponse.stream) {
        if (isCancelled) {
          throw const UpdateException('Download annullato dall\'utente.');
        }
        sink.add(chunk);
        downloadedBytes += chunk.length;
        final fraction = totalBytes > 0
            ? (downloadedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;
        yield DownloadProgress(
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          fraction: fraction,
        );
      }
      await sink.flush();
    } finally {
      await cancelSub?.cancel();
      await sink.close();
      if (isCancelled && await destFile.exists()) {
        try {
          await destFile.delete();
        } catch (_) {}
      }
    }

    // Verify downloaded file exists and is non-empty
    if (!await destFile.exists() || await destFile.length() == 0) {
      throw const UpdateException('Il file scaricato è vuoto o non valido.');
    }
  }

  static String sanitizeFilename(String filename) {
    return p.basename(filename).replaceAll(RegExp(r'[^\w\.-]'), '_');
  }
}
