import '../utils/platform_info.dart';

/// Configuration for initializing and running the `upgate` update engine.
class UpgateConfig {
  /// Creates an immutable [UpgateConfig].
  const UpgateConfig({
    this.appCode = 'UPGATE_APP',
    this.baseUrl = '',
    this.channel = 'production',
    this.fallbackVersion = '1.0.0+1',
    this.platform,
    this.architecture,
    this.deviceId,
    this.checkTimeout = const Duration(seconds: 10),
    this.resumeThrottle = const Duration(minutes: 15),
    this.customHeaders = const {},
    this.localStoragePrefix = 'upgate',
    this.enrichUpToDateFromManifest = true,
  });

  /// Unique application identifier in the update registry (e.g. `APP_BEYV_ANDR_D352`).
  final String appCode;

  /// Base URL of the update server (required for `MbkRegistryProvider`).
  final String baseUrl;

  /// Release channel to track (e.g. `production`, `stable`, `beta`, `alpha`).
  final String channel;

  /// Fallback semantic version used when runtime package info cannot be read.
  final String fallbackVersion;

  /// Optional platform override (`android`, `windows`, `linux`, `macos`, `ios`, `web`).
  ///
  /// When `null`, `upgate` detects the current runtime platform automatically.
  final String? platform;

  /// Optional CPU architecture override (e.g. `arm64-v8a`, `x64`, `universal`).
  ///
  /// When `null`, `upgate` detects the host architecture automatically.
  final String? architecture;

  /// Optional stable device identifier used for staged percentage rollouts.
  final String? deviceId;

  /// Network timeout applied to update check and manifest fetch requests.
  final Duration checkTimeout;

  /// Minimum interval between automatic update checks triggered on app resume.
  final Duration resumeThrottle;

  /// Optional additional HTTP headers included on update requests.
  final Map<String, String> customHeaders;

  /// Key prefix used in `SharedPreferences` for caches, ETag, and `device_id`.
  final String localStoragePrefix;

  /// Whether `MbkRegistryProvider` should enrich `UP_TO_DATE` responses with
  /// artifact metadata from `/api/v2/registry/apps/:appCode/manifest`.
  final bool enrichUpToDateFromManifest;

  /// Effective normalized platform name.
  String get resolvedPlatform =>
      (platform != null && platform!.trim().isNotEmpty)
          ? platform!.trim().toLowerCase()
          : PlatformInfo.detectPlatformName();

  /// Effective normalized CPU architecture.
  String get resolvedArchitecture =>
      (architecture != null && architecture!.trim().isNotEmpty)
          ? architecture!.trim().toLowerCase()
          : PlatformInfo.detectArchitecture();
}
