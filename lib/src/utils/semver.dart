/// Parsed Semantic Version (`major.minor.patch-preRelease+build`).
class Semver implements Comparable<Semver> {
  /// Creates a [Semver].
  const Semver({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const [],
    this.buildNumber,
  });

  /// Major version component.
  final int major;

  /// Minor version component.
  final int minor;

  /// Patch version component.
  final int patch;

  /// Dot-separated pre-release identifiers (empty for stable releases).
  final List<String> preRelease;

  /// Optional integer build number extracted from `+build`.
  final int? buildNumber;

  /// Parses a version string such as `1.3.1+13`, `v2.0.0-beta.2`, or `1.4`.
  static Semver parse(String raw) {
    var input = raw.trim();
    if (input.startsWith('v') || input.startsWith('V')) {
      input = input.substring(1);
    }

    int? build;
    final plusIndex = input.indexOf('+');
    if (plusIndex != -1) {
      final buildStr = input.substring(plusIndex + 1).trim();
      build = int.tryParse(buildStr.split('.').first);
      input = input.substring(0, plusIndex);
    }

    var pre = const <String>[];
    final dashIndex = input.indexOf('-');
    if (dashIndex != -1) {
      final preStr = input.substring(dashIndex + 1).trim();
      if (preStr.isNotEmpty) {
        pre = preStr.split('.');
      }
      input = input.substring(0, dashIndex);
    }

    final parts = input.split('.');
    final major = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final patch = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

    return Semver(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: pre,
      buildNumber: build,
    );
  }

  /// Compares two version strings according to SemVer 2.0.0 precedence,
  /// using `+build` as a tie-breaker when both versions specify a build number
  /// and `major.minor.patch-preRelease` are equal.
  ///
  /// Returns `< 0` if `a < b`, `0` if equal, and `> 0` if `a > b`.
  static int compare(String a, String b) => parse(a).compareTo(parse(b));

  /// Returns `true` if [candidate] is strictly newer than [current].
  static bool isNewer(String candidate, String current) =>
      compare(candidate, current) > 0;

  /// Returns `true` if [current] is strictly older than [minimum].
  static bool isBelowMinimum(String current, String minimum) =>
      compare(current, minimum) < 0;

  @override
  int compareTo(Semver other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Pre-release versions have lower precedence than a normal version.
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;

    final maxLen = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < maxLen; i++) {
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;

      final a = preRelease[i];
      final b = other.preRelease[i];
      if (a == b) continue;

      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }
      // Numeric identifiers always have lower precedence than non-numeric.
      if (aNum != null && bNum == null) return -1;
      if (aNum == null && bNum != null) return 1;
      return a.compareTo(b);
    }

    // Build number tie-breaker when both specify a numeric +build.
    if (buildNumber != null && other.buildNumber != null) {
      return buildNumber!.compareTo(other.buildNumber!);
    }

    return 0;
  }
}
