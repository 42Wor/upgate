import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/upgate_config.dart';
import '../domain/manifest_provider.dart';
import '../domain/update_manifest.dart';
import '../utils/semver.dart';

/// [ManifestProvider] that reads a static JSON manifest hosted on GitHub Pages,
/// S3, Cloudflare R2, or any HTTP(S) CDN without requiring a dedicated backend.
///
/// Uses built-in client-side [Semver] comparison (`major.minor.patch`,
/// `-prerelease`, and `+build`) against `latest_version` and `min_version`.
class JsonManifestProvider implements ManifestProvider {
  /// Creates a [JsonManifestProvider].
  JsonManifestProvider({
    required this.manifestUrl,
    http.Client? httpClient,
  })  : _httpClientOverride = httpClient,
        _ownsClient = httpClient == null;

  /// Absolute URL pointing to the static JSON update manifest.
  final Uri manifestUrl;

  final http.Client? _httpClientOverride;
  final bool _ownsClient;
  http.Client? _internalClient;

  http.Client get _client =>
      _httpClientOverride ?? (_internalClient ??= http.Client());

  @override
  Future<UpdateManifest> checkForUpdate({
    required UpgateConfig config,
    required String currentVersion,
    int? buildNumber,
    bool bypassCache = false,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _client.get(
        manifestUrl,
        headers: {
          'Accept': 'application/json',
          if (bypassCache) 'Cache-Control': 'no-cache',
          ...config.customHeaders,
        },
      ).timeout(config.checkTimeout);

      sw.stop();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return UpdateManifest.offline(
          currentVersion: currentVersion,
          latencyMs: sw.elapsedMilliseconds,
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _evaluateStaticJson(
        data,
        config: config,
        currentVersion: currentVersion,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      sw.stop();
      return UpdateManifest.offline(
        currentVersion: currentVersion,
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }

  @override
  Future<UpdateManifest?> fetchFullManifest({
    required UpgateConfig config,
  }) async {
    try {
      final res = await _client.get(
        manifestUrl,
        headers: {'Accept': 'application/json', ...config.customHeaders},
      ).timeout(config.checkTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _evaluateStaticJson(
        data,
        config: config,
        currentVersion: config.fallbackVersion,
      );
    } catch (_) {
      return null;
    }
  }

  UpdateManifest _evaluateStaticJson(
    Map<String, dynamic> data, {
    required UpgateConfig config,
    required String currentVersion,
    int? latencyMs,
  }) {
    final platform = config.resolvedPlatform;
    final arch = config.resolvedArchitecture;

    final latestVersion =
        (data['latest_version'] ?? data['version'] ?? currentVersion)
            .toString()
            .trim();
    final minVersion = data['min_version']?.toString().trim();
    final channel = (data['channel'] ?? config.channel).toString();
    final releaseNotes =
        (data['release_notes'] ?? data['notes'] ?? data['changelog'])
            ?.toString();
    final remindHours = (data['remind_interval_hours'] as num?)?.toInt() ?? 24;
    final preDownload = data['pre_download'] == true;
    final explicitMandatory = data['mandatory'] == true;

    final artifact = _matchArtifact(data['artifacts'], platform, arch);

    final belowMin = minVersion != null &&
        minVersion.isNotEmpty &&
        Semver.isBelowMinimum(currentVersion, minVersion);
    final newerAvailable = Semver.isNewer(latestVersion, currentVersion);

    final UpdateTier tier;
    final String status;
    final String uiMode;
    final bool isForced;

    if (belowMin || (newerAvailable && explicitMandatory)) {
      tier = UpdateTier.criticalBlock;
      status = 'UPDATE_MANDATORY';
      uiMode = 'HARD_BLOCK';
      isForced = true;
    } else if (newerAvailable) {
      final requestedPriority = (data['priority'] as num?)?.toInt() ?? 2;
      tier = UpdateTier.fromLevel(requestedPriority.clamp(1, 3));
      status = 'UPDATE_AVAILABLE';
      uiMode = tier == UpdateTier.gracePeriodPrompt
          ? 'MODAL_REMINDER'
          : (tier == UpdateTier.silentBadge
              ? 'SILENT_BADGE'
              : 'BANNER_PREFETCH');
      isForced = false;
    } else {
      tier = UpdateTier.upToDate;
      status = 'UP_TO_DATE';
      uiMode = 'NONE';
      isForced = false;
    }

    return UpdateManifest(
      status: status,
      latestVersion: latestVersion,
      minVersion: minVersion,
      channel: channel,
      releaseNotes: releaseNotes,
      policy: UpdatePolicy(
        tier: tier,
        isUpdateAvailable: newerAvailable || belowMin,
        isForced: isForced,
        uiMode: uiMode,
        preDownload: preDownload,
        remindIntervalHours: remindHours,
        message: data['message']?.toString(),
        channel: channel,
      ),
      primaryArtifact: artifact,
      artifacts: artifact != null ? [artifact] : const [],
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
    );
  }

  UpdateArtifact? _matchArtifact(
    dynamic rawArtifacts,
    String platform,
    String arch,
  ) {
    if (rawArtifacts is Map<String, dynamic>) {
      final entry = rawArtifacts[platform] ?? rawArtifacts['default'];
      if (entry is Map<String, dynamic>) {
        return _parseArtifactMap(entry, platform, arch);
      }
    } else if (rawArtifacts is List) {
      Map<String, dynamic>? fallbackMatch;
      for (final item in rawArtifacts) {
        if (item is Map<String, dynamic>) {
          final p = item['platform']?.toString().toLowerCase();
          final a = item['architecture']?.toString().toLowerCase();
          if (p == platform && a == arch) {
            return _parseArtifactMap(item, platform, arch);
          }
          if (p == platform && (a == 'universal' || a == null)) {
            fallbackMatch ??= item;
          }
        }
      }
      if (fallbackMatch != null) {
        return _parseArtifactMap(fallbackMatch, platform, arch);
      }
    }
    return null;
  }

  UpdateArtifact _parseArtifactMap(
    Map<String, dynamic> map,
    String platform,
    String arch,
  ) {
    final rawFallbacks = map['fallback_urls'];
    final fallbacks = <String>[];
    if (rawFallbacks is List) {
      for (final u in rawFallbacks) {
        if (u != null && u.toString().trim().isNotEmpty) {
          fallbacks.add(u.toString().trim());
        }
      }
    }
    final rawSize = map['size_bytes'] ?? map['file_size_bytes'];
    final sizeBytes = rawSize is num ? rawSize.toInt() : int.tryParse('$rawSize');

    return UpdateArtifact(
      platform: (map['platform'] ?? platform).toString(),
      architecture: (map['architecture'] ?? arch).toString(),
      downloadUrl: (map['url'] ?? map['download_url'] ?? '').toString(),
      fallbackUrls: fallbacks,
      sha256: (map['sha256'] ?? map['sha256_checksum'])?.toString(),
      sizeBytes: sizeBytes,
      sizeHuman: (map['size_human'] ?? map['file_size_human'])?.toString(),
      fileName: (map['file_name'] ?? map['filename'])?.toString(),
      packageFormat: (map['format'] ?? map['package_format'])?.toString(),
      installStrategy: map['install_strategy']?.toString(),
      installerArgs: map['installer_args']?.toString(),
    );
  }

  /// Releases underlying network resources if owned by this provider.
  void dispose() {
    if (_ownsClient) {
      _internalClient?.close();
    }
  }
}
