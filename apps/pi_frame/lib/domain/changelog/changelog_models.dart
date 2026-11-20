import 'package:flutter/foundation.dart';

/// Single item within a changelog release (either a feature or a bug fix).
@immutable
class ChangelogItem {
  /// The conventional commit scope (e.g. `agentd`, `chat`, `git`, `settings`), if any.
  final String? scope;

  /// The cleaned human-readable message.
  final String message;

  /// The commit short hash if detected in the entry.
  final String? commitHash;

  /// The commit URL if detected in the entry.
  final String? commitUrl;

  /// Whether this item is a feature (`true`) or a bug fix (`false`).
  final bool isFeature;

  const ChangelogItem({
    this.scope,
    required this.message,
    this.commitHash,
    this.commitUrl,
    required this.isFeature,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangelogItem &&
          runtimeType == other.runtimeType &&
          scope == other.scope &&
          message == other.message &&
          commitHash == other.commitHash &&
          commitUrl == other.commitUrl &&
          isFeature == other.isFeature;

  @override
  int get hashCode => Object.hash(scope, message, commitHash, commitUrl, isFeature);
}

/// Release entry containing features and bug fixes.
@immutable
class ChangelogRelease {
  final String version;
  final String? date;
  final List<ChangelogItem> features;
  final List<ChangelogItem> fixes;

  const ChangelogRelease({
    required this.version,
    this.date,
    this.features = const [],
    this.fixes = const [],
  });

  bool get isEmpty => features.isEmpty && fixes.isEmpty;
  bool get isNotEmpty => !isEmpty;

  int get totalCount => features.length + fixes.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangelogRelease &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          date == other.date &&
          listEquals(features, other.features) &&
          listEquals(fixes, other.fixes);

  @override
  int get hashCode =>
      Object.hash(version, date, Object.hashAll(features), Object.hashAll(fixes));
}

enum _SectionType { none, feature, fix, other }

/// Parser that extracts feat and fix items from standard release-please changelogs
/// and GitHub release markdown bodies.
class ChangelogParser {
  const ChangelogParser();

  static final _versionHeaderRegex = RegExp(
    r'^##\s+\[?v?(\d+\.\d+\.\d+)\]?(?:\([^)]+\))?(?:\s*\(([^)]+)\))?',
  );

  static final _sectionHeaderRegex = RegExp(r'^###\s+(.*)$');

  static final _bulletItemRegex = RegExp(r'^\s*[\*\-]\s+(.*)$');

  static final _commitLinkRegex = RegExp(
    r'\(\[([a-f0-9]{7,})\]\((https?://[^)]+)\)\)',
  );

  static final _commitHashOnlyRegex = RegExp(
    r'\(\[([a-f0-9]{7,})\]\)',
  );

  static final _scopedMessageRegex = RegExp(
    r'^\*\*\(?([a-zA-Z0-9_\-]+)\)?\:\*\*\s*(.*)$',
  );

  static final _plainScopedRegex = RegExp(
    r'^([a-zA-Z0-9_\-]+)\:\s*(.*)$',
  );

  static const _ignoredScopes = {
    'ci',
    'test',
    'tests',
    'chore',
    'chores',
    'docs',
    'doc',
    'build',
    'style',
    'styles',
    'refactor',
    'perf',
  };

  /// Parses an entire CHANGELOG.md file into a list of [ChangelogRelease]s.
  List<ChangelogRelease> parseChangelog(String markdown) {
    final lines = markdown.split('\n');
    final releases = <ChangelogRelease>[];

    String? currentVersion;
    String? currentDate;
    _SectionType currentSection = _SectionType.none;
    final currentFeatures = <ChangelogItem>[];
    final currentFixes = <ChangelogItem>[];

    void commitRelease() {
      if (currentVersion != null) {
        releases.add(
          ChangelogRelease(
            version: currentVersion!,
            date: currentDate,
            features: List.unmodifiable(currentFeatures),
            fixes: List.unmodifiable(currentFixes),
          ),
        );
      }
      currentVersion = null;
      currentDate = null;
      currentSection = _SectionType.none;
      currentFeatures.clear();
      currentFixes.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();

      // Check version header: ## [1.4.1] (2026-11-08)
      final vMatch = _versionHeaderRegex.firstMatch(trimmed);
      if (vMatch != null) {
        commitRelease();
        currentVersion = vMatch.group(1);
        currentDate = vMatch.group(2);
        continue;
      }

      // Check section header: ### Bug Fixes or ### Features
      final sMatch = _sectionHeaderRegex.firstMatch(trimmed);
      if (sMatch != null) {
        final secTitle = sMatch.group(1)?.toLowerCase() ?? '';
        if (secTitle.contains('feat')) {
          currentSection = _SectionType.feature;
        } else if (secTitle.contains('fix') || secTitle.contains('bug')) {
          currentSection = _SectionType.fix;
        } else {
          currentSection = _SectionType.other;
        }
        continue;
      }

      // Check bullet items under feat/fix section
      if (currentSection == _SectionType.feature ||
          currentSection == _SectionType.fix) {
        final bMatch = _bulletItemRegex.firstMatch(trimmed);
        if (bMatch != null) {
          final item = _parseItem(
            bMatch.group(1)!,
            isFeature: currentSection == _SectionType.feature,
          );
          if (item != null) {
            if (item.isFeature) {
              currentFeatures.add(item);
            } else {
              currentFixes.add(item);
            }
          }
        }
      }
    }

    commitRelease();
    return releases;
  }

  /// Parses a GitHub release body markdown into a [ChangelogRelease] for [version].
  ChangelogRelease parseReleaseBody(String version, String body, {String? date}) {
    final lines = body.split('\n');
    _SectionType currentSection = _SectionType.none;
    final features = <ChangelogItem>[];
    final fixes = <ChangelogItem>[];

    for (final line in lines) {
      final trimmed = line.trim();

      final sMatch = _sectionHeaderRegex.firstMatch(trimmed);
      if (sMatch != null) {
        final secTitle = sMatch.group(1)?.toLowerCase() ?? '';
        if (secTitle.contains('feat')) {
          currentSection = _SectionType.feature;
        } else if (secTitle.contains('fix') || secTitle.contains('bug')) {
          currentSection = _SectionType.fix;
        } else {
          currentSection = _SectionType.other;
        }
        continue;
      }

      if (currentSection == _SectionType.feature ||
          currentSection == _SectionType.fix) {
        final bMatch = _bulletItemRegex.firstMatch(trimmed);
        if (bMatch != null) {
          final item = _parseItem(
            bMatch.group(1)!,
            isFeature: currentSection == _SectionType.feature,
          );
          if (item != null) {
            if (item.isFeature) {
              features.add(item);
            } else {
              fixes.add(item);
            }
          }
        }
      }
    }

    return ChangelogRelease(
      version: version,
      date: date,
      features: List.unmodifiable(features),
      fixes: List.unmodifiable(fixes),
    );
  }

  ChangelogItem? _parseItem(String rawText, {required bool isFeature}) {
    var text = rawText.trim();
    String? commitHash;
    String? commitUrl;

    // Extract and strip commit link
    final linkMatch = _commitLinkRegex.firstMatch(text);
    if (linkMatch != null) {
      commitHash = linkMatch.group(1);
      commitUrl = linkMatch.group(2);
      text = text.replaceRange(linkMatch.start, linkMatch.end, '').trim();
    } else {
      final hashMatch = _commitHashOnlyRegex.firstMatch(text);
      if (hashMatch != null) {
        commitHash = hashMatch.group(1);
        text = text.replaceRange(hashMatch.start, hashMatch.end, '').trim();
      }
    }

    String? scope;
    String message = text;

    // Check for bold scope e.g. **agentd:** message
    final scopedMatch = _scopedMessageRegex.firstMatch(text);
    if (scopedMatch != null) {
      scope = scopedMatch.group(1)?.trim();
      message = scopedMatch.group(2)?.trim() ?? '';
    } else {
      // Check for plain scope e.g. agentd: message
      final plainMatch = _plainScopedRegex.firstMatch(text);
      if (plainMatch != null) {
        final candScope = plainMatch.group(1)?.trim().toLowerCase() ?? '';
        if (_ignoredScopes.contains(candScope) || candScope.length <= 15) {
          scope = plainMatch.group(1)?.trim();
          message = plainMatch.group(2)?.trim() ?? '';
        }
      }
    }

    // Filter out ignored scopes (ci, test, chore, docs, build, etc.)
    if (scope != null && _ignoredScopes.contains(scope.toLowerCase())) {
      return null;
    }

    if (message.isEmpty) return null;

    return ChangelogItem(
      scope: scope,
      message: message,
      commitHash: commitHash,
      commitUrl: commitUrl,
      isFeature: isFeature,
    );
  }
}
