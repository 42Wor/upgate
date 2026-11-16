import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/upgate_config.dart';
import '../domain/manifest_provider.dart';
import '../domain/update_manifest.dart';

/// [ManifestProvider] backed by the MBK Core Software Registry (`/api/v2/registry`).
///
/// Supports `ETag` / `304 Not Modified` caching, `426` / `404` policy responses,
/// persistent anonymous `device_id` bucketing, `evaluated_for_version` offline
/// cache invalidation, transient `MAINTENANCE` non-persistence, and automatic
/// `UP_TO_DATE` artifact metadata enrichment via `/manifest`.
class MbkRegistryProvider implements ManifestProvider {
  /// Creates an [MbkRegistryProvider].
  MbkRegistryProvider({
    http.Client? httpClient,
  })  : _httpClientOverride = httpClient,
        _ownsClient = httpClient == null;

  final http.Client? _httpClientOverride;
  final bool _ownsClient;
  http.Client? _internalClient;

  http.Client get _client =>
      _httpClientOverride ?? (_internalClient ??= http.Client());

  String _etagKey(UpgateConfig config, String platform, String version) =>
      '${config.localStoragePrefix}_etag_${config.appCode}_${platform}_$version';

  String _manifestKey(UpgateConfig config, String platform, String version) =>
      '${config.localStoragePrefix}_manifest_${config.appCode}_${platform}_$version';

  String _lastManifestKey(UpgateConfig config) =>
      '${config.localStoragePrefix}_last_manifest_${config.appCode}';

  String _lastManifestVersionKey(UpgateConfig config) =>
      '${config.localStoragePrefix}_evaluated_for_version_${config.appCode}';

  String _deviceIdKey(UpgateConfig config) =>
      '${config.localStoragePrefix}_device_id';

  /// Returns a persistent anonymous installation ID for deterministic rollout bucketing.
  Future<String> getOrCreateDeviceId(UpgateConfig config) async {
    if (config.deviceId != null && config.deviceId!.trim().isNotEmpty) {
      return config.deviceId!.trim();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _deviceIdKey(config);
      final existing = prefs.getString(key);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing.trim();
      }
      final rng = Random.secure();
      final hex = List<String>.generate(
        16,
        (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final created = 'upgate_$hex';
      await prefs.setString(key, created);
      return created;
    } catch (_) {
      return 'upgate_ephemeral';
    }
  }

  /// Fast, offline-first resolution of the last cached [UpdateManifest].
  ///
  /// Automatically invalidates stale caches when [currentVersion] differs from
  /// `evaluated_for_version` and never returns persisted `MAINTENANCE` or
  /// `UNREGISTERED` blocks.
  Future<UpdateManifest?> getCachedManifest(
    UpgateConfig config,
    String currentVersion,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastManifestKey(config));
      if (raw == null || raw.isEmpty) return null;

      final evaluatedFor = prefs.getString(_lastManifestVersionKey(config));
      if (evaluatedFor == null || evaluatedFor != currentVersion) {
        await prefs.remove(_lastManifestKey(config));
        await prefs.remove(_lastManifestVersionKey(config));
        return null;
      }

      final data = jsonDecode(raw) as Map<String, dynamic>;
      final manifest = UpdateManifest.fromJson(
        data,
        currentVersion,
        platform: config.resolvedPlatform,
      );

      if (manifest.status == 'MAINTENANCE' ||
          manifest.status == 'UNREGISTERED' ||
          manifest.priority == 5) {
        return null;
      }
      return manifest;
    } catch (_) {
      return null;
    }
  }

  List<String> _resolveCandidateBaseUrls(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return const [];
    final list = <String>[trimmed];
    if (kIsWeb) {
      final currentHost = Uri.base.host.toLowerCase();
      if (currentHost == 'localhost' || currentHost == '127.0.0.1') {
        try {
          final uri = Uri.parse(trimmed);
          if (uri.host != 'localhost' && uri.host != '127.0.0.1') {
            final port = uri.hasPort ? uri.port : 5001;
            final localUrl = '${uri.scheme}://localhost:$port';
            if (!list.contains(localUrl)) {
              list.add(localUrl);
            }
          }
        } catch (_) {}
      }
    }
    return list;
  }

  @override
  Future<UpdateManifest> checkForUpdate({
    required UpgateConfig config,
    required String currentVersion,
    int? buildNumber,
    bool bypassCache = false,
  }) async {
    final sw = Stopwatch()..start();
    final platform = config.resolvedPlatform;
    final arch = config.resolvedArchitecture;
    final candidateUrls = _resolveCandidateBaseUrls(config.baseUrl);
    if (candidateUrls.isEmpty) {
      return UpdateManifest.offline(currentVersion: currentVersion, latencyMs: 0);
    }

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    final etagKey = _etagKey(config, platform, currentVersion);
    final manifestKey = _manifestKey(config, platform, currentVersion);
    final cachedEtag = bypassCache ? null : prefs?.getString(etagKey);
    final effectiveDeviceId = await getOrCreateDeviceId(config);

    final queryParams = <String, String>{
      'app_code': config.appCode,
      'platform': platform,
      'arch': arch,
      'version': currentVersion,
      'channel': config.channel,
      'device_id': effectiveDeviceId,
      if (buildNumber != null) 'build_number': '$buildNumber',
    };

    final headers = <String, String>{
      'Accept': 'application/json',
      'X-App-Code': config.appCode,
      'X-Platform': platform,
      'X-App-Arch': arch,
      'X-App-Version': currentVersion,
      'X-Device-Id': effectiveDeviceId,
      ...config.customHeaders,
    };
    if (cachedEtag != null && cachedEtag.isNotEmpty) {
      headers['If-None-Match'] = cachedEtag;
    }

    for (var i = 0; i < candidateUrls.length; i++) {
      final base = candidateUrls[i];
      try {
        final uri = Uri.parse('$base/api/v2/registry/check')
            .replace(queryParameters: queryParams);
        final res = await _client
            .get(uri, headers: headers)
            .timeout(config.checkTimeout);

        sw.stop();
        final latency = sw.elapsedMilliseconds;

        if (res.statusCode == 304) {
          final cachedRaw = prefs?.getString(manifestKey) ??
              prefs?.getString(_lastManifestKey(config));
          if (cachedRaw != null && cachedRaw.isNotEmpty) {
            try {
              final data = jsonDecode(cachedRaw) as Map<String, dynamic>;
              final cachedManifest = UpdateManifest.fromJson(
                data,
                currentVersion,
                platform: platform,
                latencyMs: latency,
                checkedAt: DateTime.now(),
              );
              return await _maybeEnrichUpToDate(config, cachedManifest, currentVersion);
            } catch (_) {}
          }
          final upToDate = UpdateManifest.upToDate(
            currentVersion,
            channel: config.channel,
            latencyMs: latency,
          );
          return await _maybeEnrichUpToDate(config, upToDate, currentVersion);
        }

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          var manifest = UpdateManifest.fromJson(
            data,
            currentVersion,
            platform: platform,
            latencyMs: latency,
            checkedAt: DateTime.now(),
          );

          final isTransientBlock = manifest.status == 'MAINTENANCE' ||
              manifest.status == 'UNREGISTERED' ||
              manifest.priority == 5;

          if (!isTransientBlock && prefs != null) {
            final newEtag = res.headers['etag'];
            if (newEtag != null && newEtag.isNotEmpty) {
              await prefs.setString(etagKey, newEtag);
            }
            await prefs.setString(manifestKey, res.body);
            await prefs.setString(_lastManifestKey(config), res.body);
            await prefs.setString(
              _lastManifestVersionKey(config),
              currentVersion,
            );
          }

          manifest = await _maybeEnrichUpToDate(config, manifest, currentVersion);
          return manifest;
        }

        if (res.statusCode == 426 || res.statusCode == 404) {
          try {
            final decoded = jsonDecode(res.body);
            if (decoded is Map<String, dynamic> &&
                (decoded.containsKey('status') || decoded.containsKey('policy'))) {
              return UpdateManifest.fromJson(
                decoded,
                currentVersion,
                platform: platform,
                latencyMs: latency,
                checkedAt: DateTime.now(),
              );
            }
          } catch (_) {}
        }

        final cached = await getCachedManifest(config, currentVersion);
        if (cached != null) {
          return cached.copyWith(latencyMs: latency, checkedAt: DateTime.now());
        }
        return UpdateManifest.offline(
          currentVersion: currentVersion,
          latencyMs: latency,
        );
      } catch (_) {
        if (i < candidateUrls.length - 1) continue;
      }
    }

    sw.stop();
    final cached = await getCachedManifest(config, currentVersion);
    if (cached != null) {
      return cached.copyWith(
        latencyMs: sw.elapsedMilliseconds,
        checkedAt: DateTime.now(),
      );
    }
    return UpdateManifest.offline(
      currentVersion: currentVersion,
      latencyMs: sw.elapsedMilliseconds,
    );
  }

  Future<UpdateManifest> _maybeEnrichUpToDate(
    UpgateConfig config,
    UpdateManifest manifest,
    String currentVersion,
  ) async {
    if (!config.enrichUpToDateFromManifest) return manifest;
    if (manifest.status != 'UP_TO_DATE') return manifest;

    final existing = manifest.primaryArtifact;
    final needsEnrichment = existing == null ||
        (existing.fileName == null || existing.fileName!.isEmpty) ||
        (existing.sha256 == null || existing.sha256!.isEmpty);
    if (!needsEnrichment) return manifest;

    try {
      final full = await fetchFullManifest(config: config);
      final enrichedArt = full?.primaryArtifact;
      if (enrichedArt == null) return manifest;

      return manifest.copyWith(
        primaryArtifact: UpdateArtifact(
          platform: enrichedArt.platform,
          architecture: enrichedArt.architecture,
          downloadUrl: (existing?.downloadUrl.isNotEmpty ?? false)
              ? existing!.downloadUrl
              : enrichedArt.downloadUrl,
          fallbackUrls: (existing?.fallbackUrls.isNotEmpty ?? false)
              ? existing!.fallbackUrls
              : enrichedArt.fallbackUrls,
          sha256: existing?.sha256 ?? enrichedArt.sha256,
          sizeBytes: (existing?.sizeBytes ?? 0) > 0
              ? existing!.sizeBytes
              : enrichedArt.sizeBytes,
          sizeHuman: existing?.sizeHuman ?? enrichedArt.sizeHuman,
          fileName: existing?.fileName ?? enrichedArt.fileName,
          packageFormat: existing?.packageFormat ?? enrichedArt.packageFormat,
          installStrategy:
              existing?.installStrategy ?? enrichedArt.installStrategy,
          installerArgs: existing?.installerArgs ?? enrichedArt.installerArgs,
        ),
        releaseNotes: manifest.releaseNotes ?? full?.releaseNotes,
      );
    } catch (_) {
      return manifest;
    }
  }

  @override
  Future<UpdateManifest?> fetchFullManifest({
    required UpgateConfig config,
  }) async {
    final targetPlatform = config.resolvedPlatform;
    final targetArch = config.resolvedArchitecture;
    final candidateUrls = _resolveCandidateBaseUrls(config.baseUrl);
    if (candidateUrls.isEmpty) return null;

    for (var i = 0; i < candidateUrls.length; i++) {
      final base = candidateUrls[i];
      try {
        final uri = Uri.parse(
          '$base/api/v2/registry/apps/${config.appCode}/manifest',
        ).replace(queryParameters: {'channel': config.channel});

        final res = await _client.get(
          uri,
          headers: {
            'Accept': 'application/json',
            ...config.customHeaders,
          },
        ).timeout(config.checkTimeout);

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final rawArtifacts = data['artifacts'];
          Map<String, dynamic>? matchedArtifact;

          if (rawArtifacts is List) {
            for (final art in rawArtifacts) {
              if (art is Map<String, dynamic>) {
                final p = art['platform']?.toString().toLowerCase();
                final a = art['architecture']?.toString().toLowerCase();
                if (p == targetPlatform &&
                    (a == targetArch || a == 'universal' || a == null)) {
                  matchedArtifact = art;
                  break;
                }
              }
            }
          }

          final rawRelease = data['latest_release'] ?? data['release'];
          final release = (rawRelease is Map<String, dynamic>)
              ? rawRelease
              : <String, dynamic>{};

          return UpdateManifest.fromJson(
            {
              'status': 'UPDATE_AVAILABLE',
              'latest_version': release['version'] ?? config.fallbackVersion,
              'priority': 2,
              'artifact': matchedArtifact ?? <String, dynamic>{},
              'notes': release['changelog'] ?? release['release_notes'],
              'policy': {
                'priority': 2,
                'ui_mode': 'BANNER_PREFETCH',
                'channel': config.channel,
              },
            },
            config.fallbackVersion,
            platform: targetPlatform,
          );
        }
      } catch (_) {
        if (i < candidateUrls.length - 1) continue;
      }
    }
    return null;
  }

  /// Releases underlying network resources if owned by this provider.
  void dispose() {
    if (_ownsClient) {
      _internalClient?.close();
    }
  }
}
