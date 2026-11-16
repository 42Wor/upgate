import 'package:package_info_plus/package_info_plus.dart';

import 'platform_info_stub.dart'
    if (dart.library.io) 'platform_info_io.dart'
    if (dart.library.js_interop) 'platform_info_web.dart' as impl;

/// Cross-platform runtime metadata helpers (safe on Web and IO).
class PlatformInfo {
  PlatformInfo._();

  /// Returns the normalized platform name:
  /// `android`, `ios`, `windows`, `macos`, `linux`, or `web`.
  static String detectPlatformName() => impl.detectPlatformName();

  /// Returns the normalized CPU architecture (e.g. `arm64-v8a`, `x64`,
  /// `universal`, or `cloud_edge` on Web).
  static String detectArchitecture() => impl.detectArchitecture();

  /// Resolves `<version>+<buildNumber>` from `PackageInfo.fromPlatform()`,
  /// falling back to [fallbackVersion] if unavailable.
  static Future<String> resolveInstalledVersion(String fallbackVersion) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isNotEmpty) {
        return build.isNotEmpty ? '$version+$build' : version;
      }
    } catch (_) {
      // Tests or unsupported targets fall back cleanly.
    }
    return fallbackVersion;
  }
}
