import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgate/upgate.dart';

class _FakeInstaller implements UpgateInstaller {
  String? lastInstalledUrl;
  String? lastInstalledVersion;
  String? preStagedPath;
  int installCalls = 0;

  @override
  bool get supportsDirectInstall => true;

  @override
  Future<String?> getPreStagedFilePath({
    required String version,
    String? fileName,
    String? packageFormat,
    String? url,
    String? expectedSha256,
    String cacheKey = 'upgate',
  }) async =>
      preStagedPath;

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
    onProgress?.call(
      const DownloadProgress(
        progress: 1.0,
        receivedBytes: 1024,
        totalBytes: 1024,
      ),
    );
    return '/tmp/staged-$version.apk';
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
    installCalls++;
    lastInstalledUrl = url;
    lastInstalledVersion = version;
    onStatus?.call('Launching installer...');
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

class _CountingProvider implements ManifestProvider {
  int checkCalls = 0;
  UpdateManifest? nextManifest;

  @override
  Future<UpdateManifest> checkForUpdate({
    required UpgateConfig config,
    required String currentVersion,
    int? buildNumber,
    bool bypassCache = false,
  }) async {
    checkCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return nextManifest ?? UpdateManifest.upToDate(currentVersion);
  }

  @override
  Future<UpdateManifest?> fetchFullManifest({required UpgateConfig config}) async =>
      nextManifest;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Upgate.resetForTesting();
  });

  group('UpdateManifest.fromJson', () {
    test('parses tiers 0-5 and MAINTENANCE/UNREGISTERED', () {
      for (var level = 0; level <= 5; level++) {
        final m = UpdateManifest.fromJson({
          'status': level >= 4 ? 'UPDATE_MANDATORY' : 'UPDATE_AVAILABLE',
          'latest_version': '2.0.0',
          'policy': {'priority': level},
        }, '1.0.0');
        expect(m.priority, level);
        expect(m.policy.tier, UpdateTier.fromLevel(level));
        expect(m.isBlocking, level >= 4);
      }

      final maintenance = UpdateManifest.fromJson({
        'status': 'MAINTENANCE',
        'policy': {'message': 'Scheduled maintenance'},
      }, '1.0.0');
      expect(maintenance.policy.tier, UpdateTier.killSwitch);
      expect(maintenance.isBlocking, isTrue);
      expect(maintenance.hasUpdate, isFalse);

      final unregistered = UpdateManifest.fromJson({
        'status': 'UNREGISTERED',
      }, '1.0.0');
      expect(unregistered.policy.tier, UpdateTier.killSwitch);
      expect(unregistered.isBlocking, isTrue);
    });

    test('computes shouldPreDownload accurately for binary vs web/store', () {
      final binaryPrefetch = UpdateManifest.fromJson({
        'status': 'UPDATE_AVAILABLE',
        'latest_version': '1.4.0',
        'policy': {'priority': 2, 'pre_download': true},
        'artifact': {
          'download_url': 'https://cdn.example.com/app.apk',
          'package_format': 'apk',
          'install_strategy': 'direct_install',
        },
      }, '1.0.0');
      expect(binaryPrefetch.shouldPreDownload, isTrue);

      final storeRedirect = UpdateManifest.fromJson({
        'status': 'UPDATE_AVAILABLE',
        'latest_version': '1.4.0',
        'policy': {'priority': 2, 'pre_download': true},
        'artifact': {
          'download_url': 'https://apps.apple.com/app/id123',
          'install_strategy': 'store_redirect',
        },
      }, '1.0.0');
      expect(storeRedirect.shouldPreDownload, isFalse);
    });
  });

  group('MbkRegistryProvider', () {
    const config = UpgateConfig(
      appCode: 'APP_TEST_001',
      baseUrl: 'https://core.example.com',
      platform: 'android',
      architecture: 'arm64-v8a',
      channel: 'production',
    );

    test('handles 200, persists device_id, and handles 304 ETag cache', () async {
      var requestCount = 0;
      String? seenIfNoneMatch;
      String? seenDeviceId;

      final mockClient = MockClient((req) async {
        requestCount++;
        if (req.url.path.endsWith('/check')) {
          seenDeviceId = req.url.queryParameters['device_id'];
          seenIfNoneMatch = req.headers['If-None-Match'];
          if (requestCount == 1) {
            return http.Response(
              jsonEncode({
                'status': 'UPDATE_AVAILABLE',
                'latest_version': '1.5.0',
                'policy': {'priority': 2, 'ui_mode': 'BANNER_PREFETCH'},
                'artifact': {
                  'download_url': 'https://cdn.example.com/app-1.5.0.apk',
                  'filename': 'app-1.5.0.apk',
                  'sha256_checksum': 'abc123',
                  'file_size_bytes': 1048576,
                },
              }),
              200,
              headers: {'etag': '"v1.5.0-etag"'},
            );
          }
          return http.Response('', 304);
        }
        return http.Response('Not found', 404);
      });

      final provider = MbkRegistryProvider(httpClient: mockClient);
      final first = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.0.0+1',
      );
      expect(first.status, 'UPDATE_AVAILABLE');
      expect(first.latestVersion, '1.5.0');
      expect(seenDeviceId, isNotNull);
      expect(seenDeviceId, startsWith('upgate_'));

      final second = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.0.0+1',
      );
      expect(seenIfNoneMatch, '"v1.5.0-etag"');
      expect(second.latestVersion, '1.5.0');
    });

    test('parses 426 and 404 policy payloads', () async {
      final mock426 = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'UPDATE_MANDATORY',
            'latest_version': '2.0.0',
            'policy': {'priority': 4, 'message': 'Upgrade required'},
          }),
          426,
        );
      });

      final provider = MbkRegistryProvider(httpClient: mock426);
      final res426 = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.0.0',
      );
      expect(res426.isBlocking, isTrue);
      expect(res426.priority, 4);

      final mock404 = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'UNREGISTERED',
            'policy': {'priority': 5, 'message': 'Unknown app'},
          }),
          404,
        );
      });
      final provider404 = MbkRegistryProvider(httpClient: mock404);
      final res404 = await provider404.checkForUpdate(
        config: config,
        currentVersion: '1.0.0',
      );
      expect(res404.status, 'UNREGISTERED');
      expect(res404.isBlocking, isTrue);
    });

    test('enriches UP_TO_DATE from /manifest and invalidates stale version cache',
        () async {
      final mockClient = MockClient((req) async {
        if (req.url.path.endsWith('/check')) {
          return http.Response(
            jsonEncode({
              'status': 'UP_TO_DATE',
              'latest_version': '1.3.1',
              'policy': {'priority': 0},
            }),
            200,
          );
        }
        if (req.url.path.endsWith('/manifest')) {
          return http.Response(
            jsonEncode({
              'latest_release': {'version': '1.3.1', 'changelog': 'Stable'},
              'artifacts': [
                {
                  'platform': 'android',
                  'architecture': 'arm64-v8a',
                  'filename': 'app-1.3.1-arm64.apk',
                  'file_size_bytes': 5242880,
                  'sha256_checksum': 'deadbeef123456',
                  'download_url': 'https://cdn.example.com/app-1.3.1.apk',
                }
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final provider = MbkRegistryProvider(httpClient: mockClient);
      final res = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.3.1+13',
      );
      expect(res.status, 'UP_TO_DATE');
      expect(res.primaryArtifact?.fileName, 'app-1.3.1-arm64.apk');
      expect(res.primaryArtifact?.sha256, 'deadbeef123456');
      expect(res.humanSize, '5.0 MB');

      // Cache exists for 1.3.1+13, but must invalidate for 1.3.2+14
      expect(await provider.getCachedManifest(config, '1.3.1+13'), isNotNull);
      expect(await provider.getCachedManifest(config, '1.3.2+14'), isNull);
    });

    test('normalizes ahead-of-server local dev build to non-gating UP_TO_DATE',
        () async {
      final mockClient = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'status': 'UPDATE_MANDATORY',
            'latest_version': '1.3.0',
            'policy': {'priority': 4},
          }),
          200,
        );
      });

      final provider = MbkRegistryProvider(httpClient: mockClient);
      final res = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.4.0+14',
      );
      expect(res.status, 'UP_TO_DATE');
      expect(res.isBlocking, isFalse);
      expect(res.hasUpdate, isFalse);
      expect(res.isAheadOfServer('1.4.0+14'), isTrue);
    });
  });

  group('JsonManifestProvider & Semver', () {
    test('compares pre-release tags and build numbers accurately', () {
      expect(Semver.compare('1.3.0-beta.1', '1.3.0-beta.2'), lessThan(0));
      expect(Semver.compare('1.3.0-beta.2', '1.3.0-rc.1'), lessThan(0));
      expect(Semver.compare('1.3.0-rc.1', '1.3.0'), lessThan(0));
      expect(Semver.compare('1.3.0+12', '1.3.0+13'), lessThan(0));
      expect(Semver.isNewer('1.4.0+1', '1.3.9+99'), isTrue);
    });

    test('detects optional and mandatory updates from static JSON', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'latest_version': '1.5.0+20',
            'min_version': '1.2.0',
            'release_notes': 'Static CDN release',
            'artifacts': {
              'windows': {
                'url': 'https://cdn.example.com/setup.exe',
                'sha256': 'fff000',
                'format': 'exe',
              },
            },
          }),
          200,
        );
      });

      final provider = JsonManifestProvider(
        manifestUrl: Uri.parse('https://cdn.example.com/version.json'),
        httpClient: mockClient,
      );
      const config = UpgateConfig(platform: 'windows', architecture: 'x64');

      final optional = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.3.0+10',
      );
      expect(optional.hasUpdate, isTrue);
      expect(optional.isBlocking, isFalse);
      expect(optional.primaryArtifact?.downloadUrl, 'https://cdn.example.com/setup.exe');

      final mandatory = await provider.checkForUpdate(
        config: config,
        currentVersion: '1.1.0+5',
      );
      expect(mandatory.isBlocking, isTrue);
      expect(mandatory.policy.tier, UpdateTier.criticalBlock);
    });
  });

  group('VersionGateHttpClient', () {
    test('awaits version on first request, injects headers, and intercepts 426',
        () async {
      String? sentVersion;
      String? sentPlatform;
      var gateTriggered = false;

      final inner = MockClient((req) async {
        sentVersion = req.headers['X-App-Version'];
        sentPlatform = req.headers['X-Platform'];
        return http.Response('Upgrade required', 426);
      });

      final client = VersionGateHttpClient(
        inner: inner,
        appCode: 'APP_GATE_01',
        platform: 'linux',
        architecture: 'x64',
        versionResolver: () async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          return '1.2.3+45';
        },
        onUpgradeRequired: () => gateTriggered = true,
      );

      final res = await client.get(Uri.parse('https://api.example.com/ping'));
      expect(res.statusCode, 426);
      expect(sentVersion, '1.2.3+45');
      expect(sentPlatform, 'linux');
      expect(gateTriggered, isTrue);
    });
  });

  group('UpgateController', () {
    test('deduplicates concurrent checks, enforces remindIntervalHours, and supports standalone installFromUrl',
        () async {
      final provider = _CountingProvider();
      final installer = _FakeInstaller();
      final controller = UpgateController(
        config: const UpgateConfig(appCode: 'APP_CTRL_01'),
        provider: provider,
        installer: installer,
        versionResolver: () async => '1.0.0+1',
      );

      // In-flight deduplication
      await Future.wait([
        controller.checkForUpdate(),
        controller.checkForUpdate(),
      ]);
      expect(provider.checkCalls, 1);

      // remindIntervalHours throttling
      final modalManifest = UpdateManifest.fromJson({
        'status': 'UPDATE_AVAILABLE',
        'latest_version': '1.2.0',
        'policy': {'priority': 3, 'remind_interval_hours': 12},
      }, '1.0.0+1');
      expect(await controller.shouldShowModalReminder(modalManifest), isTrue);
      await controller.markModalPrompted('1.2.0');
      expect(await controller.shouldShowModalReminder(modalManifest), isFalse);

      // Standalone installFromUrl
      await controller.installFromUrl(
        url: 'https://cdn.example.com/app-1.2.0.apk',
        version: '1.2.0',
      );
      expect(installer.installCalls, 1);
      expect(installer.lastInstalledUrl, 'https://cdn.example.com/app-1.2.0.apk');
      expect(installer.lastInstalledVersion, '1.2.0');
    });
  });

  group('Upgate.initializeRegistry', () {
    test('configures MbkRegistryProvider with auto-detected platform, fallback URLs, and authTokenProvider',
        () async {
      String? authHeader;
      final attemptedHosts = <String>[];

      final mockClient = MockClient((req) async {
        if (req.url.path.endsWith('/check')) {
          attemptedHosts.add(req.url.host);
          authHeader = req.headers['Authorization'];
        }
        if (req.url.host == 'primary.example.com') {
          return http.Response('Bad Gateway', 502);
        }
        return http.Response(
          jsonEncode({
            'status': 'UP_TO_DATE',
            'latest_version': '1.0.0',
            'policy': {'priority': 0},
          }),
          200,
        );
      });

      final controller = Upgate.initializeRegistry(
        appCode: 'REG_4829105736',
        baseUrl: 'https://primary.example.com',
        fallbackBaseUrls: const ['https://backup.example.com'],
        authTokenProvider: () async => 'secret-token',
        provider: MbkRegistryProvider(httpClient: mockClient),
        versionResolver: () async => '1.0.0+1',
      );

      final manifest = await controller.checkForUpdate();
      expect(controller.config.appCode, 'REG_4829105736');
      expect(controller.config.resolvedPlatform, isNotEmpty);
      expect(controller.config.resolvedArchitecture, isNotEmpty);
      expect(attemptedHosts, ['primary.example.com', 'backup.example.com']);
      expect(authHeader, 'Bearer secret-token');
      expect(manifest?.status, 'UP_TO_DATE');
    });
  });
}
