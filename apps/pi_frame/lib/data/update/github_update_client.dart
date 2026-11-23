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

  const DownloadProgress({required this.downloadedBytes, required this.totalBytes, required this.fraction});
}

/// Why an update check or download failed; the translation tables word it
/// for the user (`updateFailureMessage`).
enum UpdateFailure {
  rateLimited,
  checkFailed,
  unreachable,
  timeout,
  unexpected,
  invalidDownloadUrl,
  downloadFailed,
  cancelled,
  emptyDownload,
}

class UpdateException implements Exception {
  /// English technical message, for logs and details.
  final String message;
  final int? statusCode;
  final UpdateFailure? failure;

  const UpdateException(this.message, [this.statusCode, this.failure]);

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

  GithubUpdateClient({http.Client? client, this.repository = defaultRepository}) : _client = client ?? http.Client();

  Uri get _releasesLatestUri => Uri.https('api.github.com', '/repos/$repository/releases/latest');

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
      final response = await _client
          .get(uri, headers: {'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'PiFrame-App'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return AppRelease.fromJson(data);
        }
        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateException('GitHub rate limit reached. Try again later.', 403, UpdateFailure.rateLimited);
      } else {
        throw UpdateException(
          'Update check failed (HTTP ${response.statusCode})',
          response.statusCode,
          UpdateFailure.checkFailed,
        );
      }
    } on SocketException {
      throw const UpdateException(
        'Cannot reach GitHub. Check the Internet connection.',
        null,
        UpdateFailure.unreachable,
      );
    } on TimeoutException {
      throw const UpdateException('The GitHub update request timed out.', null, UpdateFailure.timeout);
    } catch (e) {
      if (e is UpdateException) rethrow;
      throw UpdateException('Unexpected error while checking for updates: $e', null, UpdateFailure.unexpected);
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
        'Invalid download URL or domain not allowed for security.',
        null,
        UpdateFailure.invalidDownloadUrl,
      );
    }

    final destFile = File(destinationPath);
    // Sanitize directory creation
    final parentDir = destFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final request = http.Request('GET', uri)
      ..headers.addAll({'Accept': 'application/octet-stream', 'User-Agent': 'PiFrame-App'});

    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode != 200) {
      throw UpdateException(
        'Update download failed (HTTP ${streamedResponse.statusCode})',
        streamedResponse.statusCode,
        UpdateFailure.downloadFailed,
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
          throw const UpdateException('Download cancelled by the user.', null, UpdateFailure.cancelled);
        }
        sink.add(chunk);
        downloadedBytes += chunk.length;
        final fraction = totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        yield DownloadProgress(downloadedBytes: downloadedBytes, totalBytes: totalBytes, fraction: fraction);
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
      throw const UpdateException('The downloaded file is empty or invalid.', null, UpdateFailure.emptyDownload);
    }
  }

  static String sanitizeFilename(String filename) {
    return p.basename(filename).replaceAll(RegExp(r'[^\w\.-]'), '_');
  }
}
