import '../domain/update_manifest.dart';
import 'installer_stub.dart'
    if (dart.library.io) 'installer_io.dart'
    if (dart.library.js_interop) 'installer_web.dart' as platform_impl;

/// Progress snapshot emitted while streaming an update binary.
class DownloadProgress {
  /// Creates a [DownloadProgress].
  const DownloadProgress({
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// Normalized progress (`0.0..1.0`), or `0.0` if total size is unknown.
  final double progress;

  /// Total bytes written so far.
  final int receivedBytes;

  /// Expected total bytes from `Content-Length`, or `0` if unknown.
  final int totalBytes;

  /// Formatted megabytes received (e.g. `12.4`).
  String get receivedMb => (receivedBytes / (1024 * 1024)).toStringAsFixed(1);

  /// Formatted total megabytes (e.g. `25.0`).
  String get totalMb => (totalBytes / (1024 * 1024)).toStringAsFixed(1);

  /// Whole percentage (`0..100`).
  int get percentage => (progress.clamp(0.0, 1.0) * 100).toInt();
}

/// Progress callback emitted during binary download and verification.
typedef DownloadProgressCallback = void Function(DownloadProgress progress);

/// Human-readable status callback emitted across download/verify/install steps.
typedef InstallerStatusCallback = void Function(String statusMessage);

/// Platform-specific abstraction for downloading, SHA-256 verifying, and
/// launching native or web updates.
///
/// Can be used standalone without `UpgateGuard` or a version-check server:
/// ```dart
/// final installer = UpgateInstaller();
/// await installer.installFromUrl(
///   url: 'https://example.com/releases/app-1.4.0.apk',
///   version: '1.4.0',
///   expectedSha256: '...',
/// );
/// ```
abstract interface class UpgateInstaller {
  /// Creates the default [UpgateInstaller] for the current runtime platform.
  factory UpgateInstaller() => platform_impl.createPlatformInstaller();

  /// Returns whether this platform supports direct in-app binary installation.
  bool get supportsDirectInstall;

  /// Returns a pre-staged local file path if it exists and passes [expectedSha256],
  /// or `null` otherwise. Always returns `null` on Web.
  Future<String?> getPreStagedFilePath({
    required String version,
    String? fileName,
    String? packageFormat,
    String? url,
    String? expectedSha256,
    String cacheKey = 'upgate',
  });

  /// Streams [url] (or [fallbackUrls]) to temporary storage and verifies
  /// [expectedSha256] using chunked hashing without buffering the binary in RAM.
  ///
  /// Returns the verified local file path on native platforms, or `null` on Web.
  Future<String?> downloadAndVerify({
    required String url,
    List<String> fallbackUrls = const [],
    required String version,
    String? expectedSha256,
    String? fileName,
    String? packageFormat,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  });

  /// Downloads, verifies, and launches installation for a standalone URL.
  Future<void> installFromUrl({
    required String url,
    List<String> fallbackUrls = const [],
    required String version,
    String? expectedSha256,
    String? fileName,
    String? packageFormat,
    String? installStrategy,
    String? installerArgs,
    bool requireChecksum = false,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  });

  /// Downloads, verifies, and launches installation for an [UpdateArtifact].
  Future<void> installArtifact(
    UpdateArtifact artifact, {
    required String version,
    bool requireChecksum = false,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  });
}

/// Creates the default [UpgateInstaller] for the current runtime platform.
UpgateInstaller createDefaultInstaller() => platform_impl.createPlatformInstaller();
