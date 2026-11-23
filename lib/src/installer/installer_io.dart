import 'dart:async' show TimeoutException;
import 'dart:io' show File, Platform, Process, ProcessStartMode, exit;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/update_manifest.dart';
import 'installer_interface.dart';

class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// Native `dart:io` [UpgateInstaller] for Android, iOS, Windows, macOS, and Linux.
class IoUpgateInstaller implements UpgateInstaller {
  /// Creates an [IoUpgateInstaller].
  IoUpgateInstaller({
    http.Client? httpClient,
    this.exitOnWindowsLaunch = true,
  }) : _httpClientOverride = httpClient;

  final http.Client? _httpClientOverride;

  /// Whether Windows installer launch calls `exit(0)` after spawning the
  /// detached installer process so file locks are released.
  final bool exitOnWindowsLaunch;

  @override
  bool get supportsDirectInstall => !Platform.isIOS;

  /// Resolves a clean file extension from [packageFormat], [fileName], or [url].
  static String determineExtension(
    String? packageFormat,
    String? url, {
    String? fileName,
  }) {
    if (packageFormat != null && packageFormat.trim().isNotEmpty) {
      final clean = packageFormat.replaceAll('.', '').toLowerCase().trim();
      if (clean == 'web' || clean == 'web_url') return 'web';
      return clean;
    }
    for (final candidate in [fileName, url]) {
      if (candidate != null && candidate.isNotEmpty) {
        final path = Uri.tryParse(candidate)?.path ?? candidate;
        final lastDot = path.lastIndexOf('.');
        if (lastDot != -1 && lastDot < path.length - 1) {
          final ext = path.substring(lastDot + 1).toLowerCase();
          if (ext.length <= 8) return ext;
        }
      }
    }
    if (Platform.isWindows) return 'exe';
    if (Platform.isAndroid) return 'apk';
    if (Platform.isLinux) return 'deb';
    if (Platform.isMacOS) return 'dmg';
    return 'bin';
  }

  static bool _isBinaryInstall(String? installStrategy, String? packageFormat) {
    final strategy = installStrategy?.toLowerCase().trim() ?? '';
    final format = packageFormat?.toLowerCase().trim() ?? '';
    if (strategy == 'store_redirect' ||
        strategy == 'web_reload' ||
        format == 'web_url') {
      return false;
    }
    return true;
  }

  Future<File> _resolveTargetFile({
    required String version,
    required String ext,
    required String cacheKey,
    String? fileName,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeKey =
        cacheKey.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    final safeVer = version.replaceAll(RegExp(r'[^a-zA-Z0-9._+-]'), '_');
    if (fileName != null && fileName.trim().isNotEmpty) {
      final base = fileName.trim().replaceAll(RegExp(r'[/\\]'), '_');
      return File('${tempDir.path}/$safeKey-$safeVer-$base');
    }
    return File('${tempDir.path}/update_${safeKey}_v$safeVer.$ext');
  }

  @override
  Future<String?> getPreStagedFilePath({
    required String version,
    String? fileName,
    String? packageFormat,
    String? url,
    String? expectedSha256,
    String cacheKey = 'upgate',
  }) async {
    try {
      final ext = determineExtension(packageFormat, url, fileName: fileName);
      final targetFile = await _resolveTargetFile(
        version: version,
        ext: ext,
        cacheKey: cacheKey,
        fileName: fileName,
      );
      if (!await targetFile.exists()) return null;

      final length = await targetFile.length();
      if (length <= 0) {
        await targetFile.delete();
        return null;
      }

      if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
        final collector = _DigestCollector();
        final shaSink = sha256.startChunkedConversion(collector);
        await for (final chunk in targetFile.openRead()) {
          shaSink.add(chunk);
        }
        shaSink.close();
        final actualHash = collector.digest?.toString() ?? '';
        if (actualHash.toLowerCase() == expectedSha256.trim().toLowerCase()) {
          return targetFile.path;
        }
        await targetFile.delete();
        return null;
      }

      return targetFile.path;
    } catch (_) {
      return null;
    }
  }

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
    final ext = determineExtension(packageFormat, url, fileName: fileName);
    final targetFile = await _resolveTargetFile(
      version: version,
      ext: ext,
      cacheKey: cacheKey,
      fileName: fileName,
    );
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final urls = [url, ...fallbackUrls]
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      throw Exception('No download URLs or fallback mirrors available.');
    }

    Exception? lastError;

    for (var i = 0; i < urls.length; i++) {
      final currentUrl = urls[i];
      final mirrorNotice = i > 0 ? ' (Failover Mirror #${i + 1})' : '';
      onStatus?.call('Connecting to distribution server$mirrorNotice...');

      final client = _httpClientOverride ?? http.Client();
      try {
        final request = http.Request('GET', Uri.parse(currentUrl));
        request.headers['Accept'] = '*/*';

        final streamedResponse = await client.send(request);
        if (streamedResponse.statusCode < 200 ||
            streamedResponse.statusCode >= 300) {
          throw Exception('Server returned HTTP ${streamedResponse.statusCode}');
        }

        final totalBytes = streamedResponse.contentLength ?? 0;
        var receivedBytes = 0;

        onStatus?.call('Downloading update package$mirrorNotice...');
        final fileSink = targetFile.openWrite();
        final collector = _DigestCollector();
        final shaSink = sha256.startChunkedConversion(collector);

        try {
          await for (final chunk in streamedResponse.stream.timeout(
            const Duration(seconds: 30),
            onTimeout: (sink) => sink.addError(
              TimeoutException('Stream inactivity timeout of 30 seconds exceeded.'),
            ),
          )) {
            fileSink.add(chunk);
            shaSink.add(chunk);
            receivedBytes += chunk.length;

            final progress =
                totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
            onProgress?.call(
              DownloadProgress(
                progress: progress,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
              ),
            );
          }
          await fileSink.flush();
          await fileSink.close();
          shaSink.close();

          if (totalBytes > 0 && receivedBytes != totalBytes) {
            throw Exception(
              'Truncated payload: received $receivedBytes bytes out of $totalBytes expected.',
            );
          }
        } catch (e) {
          await fileSink.close();
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          throw Exception('Stream interrupted on mirror: $e');
        } finally {
          if (_httpClientOverride == null) {
            client.close();
          }
        }

        if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
          onStatus?.call('Verifying package SHA-256 integrity...');
          final computedHash = collector.digest?.toString() ?? '';
          if (computedHash.toLowerCase() != expectedSha256.trim().toLowerCase()) {
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            throw Exception(
              'Security alert: SHA-256 checksum mismatch for downloaded binary.',
            );
          }
        }

        return targetFile.path;
      } catch (err) {
        if (_httpClientOverride == null) {
          client.close();
        }
        lastError = Exception('Mirror $currentUrl failed: $err');
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }
      }
    }

    throw lastError ?? Exception('All distribution mirrors failed.');
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
    final strategy = installStrategy?.toLowerCase().trim() ?? '';
    final format = packageFormat?.toLowerCase().trim() ?? '';

    if (strategy == 'store_redirect' || format == 'web_url' || Platform.isIOS) {
      onStatus?.call('Opening external store / download page...');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      throw Exception('Cannot launch external URL: $url');
    }

    if (requireChecksum &&
        _isBinaryInstall(installStrategy, packageFormat) &&
        (expectedSha256 == null || expectedSha256.trim().isEmpty)) {
      throw Exception(
        'Security alert: SHA-256 checksum is required for mandatory binary updates.',
      );
    }

    var localPath = await getPreStagedFilePath(
      version: version,
      fileName: fileName,
      packageFormat: packageFormat,
      url: url,
      expectedSha256: expectedSha256,
      cacheKey: cacheKey,
    );

    if (localPath != null) {
      onStatus?.call('Package verified on disk. Launching installer...');
    } else {
      localPath = await downloadAndVerify(
        url: url,
        fallbackUrls: fallbackUrls,
        version: version,
        expectedSha256: expectedSha256,
        fileName: fileName,
        packageFormat: packageFormat,
        cacheKey: cacheKey,
        onProgress: onProgress,
        onStatus: onStatus,
      );
    }

    if (localPath == null || localPath.isEmpty) {
      throw Exception('Failed to stage installer file.');
    }

    await _launchNativeInstaller(
      filePath: localPath,
      installerArgs: installerArgs,
      downloadUrl: url,
      onStatus: onStatus,
    );
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

  Future<void> _launchNativeInstaller({
    required String filePath,
    String? installerArgs,
    required String downloadUrl,
    InstallerStatusCallback? onStatus,
  }) async {
    if (Platform.isWindows) {
      onStatus?.call('Starting Windows installer process...');
      final argsList = <String>[];
      if (installerArgs != null && installerArgs.trim().isNotEmpty) {
        final reg = RegExp(r'[^\s"]+|"([^"]*)"');
        for (final match in reg.allMatches(installerArgs.trim())) {
          final group1 = match.group(1);
          argsList.add(group1 ?? match.group(0)!);
        }
      }
      final isExe = filePath.toLowerCase().endsWith('.exe');
      final process = await Process.start(
        filePath,
        argsList,
        runInShell: !isExe,
        mode: ProcessStartMode.detached,
      );
      if (process.pid <= 0) {
        throw Exception('Failed to spawn Windows installer process.');
      }
      if (exitOnWindowsLaunch) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        exit(0);
      }
      return;
    }

    if (Platform.isAndroid) {
      onStatus?.call('Opening Android package installer...');
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type == ResultType.permissionDenied) {
        throw Exception(
          'Install permission denied. Enable "Install unknown apps" for this app in Android Settings and try again. (${result.message})',
        );
      }
      if (result.type != ResultType.done) {
        throw Exception('Installer launch failed: ${result.message}');
      }
      return;
    }

    if (Platform.isMacOS || Platform.isLinux) {
      if (await File(filePath).exists()) {
        onStatus?.call('Launching local package installer...');
        final cmd = Platform.isMacOS ? 'open' : 'xdg-open';
        final proc = await Process.start(
          cmd,
          [filePath],
          mode: ProcessStartMode.detached,
        );
        if (proc.pid > 0) return;
      }
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      throw Exception('Failed to launch local or external installer.');
    }
  }
}

/// Creates the native IO [UpgateInstaller].
UpgateInstaller createPlatformInstaller() => IoUpgateInstaller();
