import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/app_version.dart';
import '../../domain/changelog/changelog_models.dart';

typedef ChangelogLoader = Future<String?> Function();

class ChangelogService {
  final http.Client _client;
  final ChangelogLoader? _customLoader;
  final ChangelogParser _parser;
  final String repository;

  static const defaultRepository = 'TrentiStefano/PiFrame';

  ChangelogService({
    http.Client? client,
    this._customLoader,
    this._parser = const ChangelogParser(),
    this.repository = defaultRepository,
  }) : _client = client ?? http.Client();

  /// Loads the changelog release for [version] (defaults to [piFrameVersion]).
  Future<ChangelogRelease?> loadRelease({String? version}) async {
    final targetVersion = version ?? piFrameVersion;

    // 1. Try loading from bundled asset or local changelog loader
    final localMarkdown = await _loadLocalMarkdown();
    if (localMarkdown != null && localMarkdown.isNotEmpty) {
      final releases = _parser.parseChangelog(localMarkdown);
      final match = releases.cast<ChangelogRelease?>().firstWhere(
            (r) => r?.version == targetVersion,
            orElse: () => null,
          );
      if (match != null && match.isNotEmpty) {
        return match;
      }
      // If version wasn't exact match, but we have releases, save the newest as fallback
      if (releases.isNotEmpty && releases.first.isNotEmpty) {
        // Return latest known if targetVersion is not yet in CHANGELOG (e.g. uncommitted bump)
        // only if online check fails.
      }
    }

    // 2. Try fetching from GitHub Releases API
    try {
      final tag = 'v$targetVersion';
      final uri = Uri.https(
        'api.github.com',
        '/repos/$repository/releases/tags/$tag',
      );
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'PiFrame-App',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final body = data['body']?.toString() ?? '';
          final publishedAt = data['published_at']?.toString();
          final parsed = _parser.parseReleaseBody(
            targetVersion,
            body,
            date: publishedAt?.split('T').first,
          );
          if (parsed.isNotEmpty) {
            return parsed;
          }
        }
      }
    } catch (_) {}

    // 3. Try raw GitHub CHANGELOG.md as secondary online fallback
    try {
      final rawUri = Uri.https(
        'raw.githubusercontent.com',
        '/$repository/main/CHANGELOG.md',
      );
      final rawResponse = await _client.get(
        rawUri,
        headers: {'User-Agent': 'PiFrame-App'},
      ).timeout(const Duration(seconds: 6));

      if (rawResponse.statusCode == 200) {
        final releases = _parser.parseChangelog(rawResponse.body);
        final match = releases.cast<ChangelogRelease?>().firstWhere(
              (r) => r?.version == targetVersion,
              orElse: () => null,
            );
        if (match != null && match.isNotEmpty) {
          return match;
        }
      }
    } catch (_) {}

    // 4. Fallback to the latest available release from local markdown if available
    if (localMarkdown != null && localMarkdown.isNotEmpty) {
      final releases = _parser.parseChangelog(localMarkdown);
      if (releases.isNotEmpty) {
        return releases.first;
      }
    }

    return null;
  }

  Future<String?> _loadLocalMarkdown() async {
    final loader = _customLoader;
    if (loader != null) {
      return await loader();
    }

    // Attempt rootBundle first (packaged asset)
    try {
      return await rootBundle.loadString('assets/CHANGELOG.md');
    } catch (_) {}

    // In unit tests or dev without Flutter asset bundle initialized, read from file system
    try {
      final file = File('assets/CHANGELOG.md');
      if (await file.exists()) {
        return await file.readAsString();
      }
      final rootFile = File('../../CHANGELOG.md');
      if (await rootFile.exists()) {
        return await rootFile.readAsString();
      }
      final directRoot = File('CHANGELOG.md');
      if (await directRoot.exists()) {
        return await directRoot.readAsString();
      }
    } catch (_) {}

    return null;
  }
}

final changelogServiceProvider = Provider<ChangelogService>((ref) {
  return ChangelogService();
});
