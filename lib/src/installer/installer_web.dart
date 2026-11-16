import 'package:url_launcher/url_launcher.dart';

import '../domain/update_manifest.dart';
import 'installer_interface.dart';

/// Web [UpgateInstaller] implementation using browser navigation & cache-busting reload.
class WebUpgateInstaller implements UpgateInstaller {
  /// Creates a [WebUpgateInstaller].
  const WebUpgateInstaller();

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
  }) async {
    // Web browsers manage asset caching natively.
    return null;
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
  }) async {
    onStatus?.call('Reloading web application...');
    final baseUri = url.trim().isNotEmpty ? Uri.parse(url.trim()) : Uri.base;
    final targetUri = installStrategy == 'web_reload'
        ? baseUri.replace(
            queryParameters: {
              ...baseUri.queryParameters,
              '_upgate_v': version,
              '_t': '${DateTime.now().millisecondsSinceEpoch}',
            },
          )
        : baseUri;

    await launchUrl(targetUri, webOnlyWindowName: '_self');
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
    return installFromUrl(
      url: artifact.downloadUrl,
      fallbackUrls: artifact.fallbackUrls,
      version: version,
      expectedSha256: artifact.sha256,
      fileName: artifact.fileName,
      packageFormat: artifact.packageFormat,
      installStrategy: artifact.installStrategy,
      installerArgs: artifact.installerArgs,
      requireChecksum: requireChecksum,
      cacheKey: cacheKey,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }
}

/// Creates the Web [UpgateInstaller].
UpgateInstaller createPlatformInstaller() => const WebUpgateInstaller();
