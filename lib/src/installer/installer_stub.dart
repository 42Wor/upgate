import '../domain/update_manifest.dart';
import 'installer_interface.dart';

/// Fallback [UpgateInstaller] used when neither `dart:io` nor `dart:js_interop`
/// is available.
class StubUpgateInstaller implements UpgateInstaller {
  /// Creates a [StubUpgateInstaller].
  const StubUpgateInstaller();

  @override
  bool get supportsDirectInstall => false;

  @override
  Future<String?> getPreStagedFilePath({
    required String version,
    String? fileName,
    String? packageFormat,
    String? url,
    String? expectedSha256,
    String cacheKey = 'upgate',
  }) async =>
      null;

  @override
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
  }) {
    throw UnsupportedError('UpgateInstaller is not supported on this platform.');
  }

  @override
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
  }) {
    throw UnsupportedError('UpgateInstaller is not supported on this platform.');
  }

  @override
  Future<void> installArtifact(
    UpdateArtifact artifact, {
    required String version,
    bool requireChecksum = false,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  }) {
    throw UnsupportedError('UpgateInstaller is not supported on this platform.');
  }
}

/// Platform factory stub.
UpgateInstaller createPlatformInstaller() => const StubUpgateInstaller();
