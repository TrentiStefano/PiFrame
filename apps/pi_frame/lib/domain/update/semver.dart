class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final String? build;
  final String raw;

  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease,
    this.build,
    required this.raw,
  });

  static final RegExp _semVerRegex = RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$',
  );

  static SemVer? tryParse(String? versionString) {
    if (versionString == null) return null;
    final trimmed = versionString.trim();
    if (trimmed.isEmpty) return null;

    final match = _semVerRegex.firstMatch(trimmed);
    if (match == null) return null;

    final major = int.tryParse(match.group(1) ?? '');
    final minor = int.tryParse(match.group(2) ?? '');
    final patch = int.tryParse(match.group(3) ?? '');

    if (major == null || minor == null || patch == null) return null;

    return SemVer(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: match.group(4),
      build: match.group(5),
      raw: trimmed,
    );
  }

  static SemVer parse(String versionString) {
    final parsed = tryParse(versionString);
    if (parsed == null) {
      throw FormatException('Invalid SemVer format: "$versionString"');
    }
    return parsed;
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // When major, minor, patch match:
    // A version with pre-release has lower precedence than a version without.
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease != null && other.preRelease != null) {
      return preRelease!.compareTo(other.preRelease!);
    }

    return 0;
  }

  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SemVer &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          preRelease == other.preRelease);

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() => raw;
}
