import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/upgate_config.dart';
import '../domain/manifest_provider.dart';
import '../domain/update_manifest.dart';
import '../installer/installer_interface.dart';
import '../providers/mbk_registry_provider.dart';
import '../utils/platform_info.dart';

/// Lifecycle states of the `upgate` update controller.
enum UpdateState {
  /// No update check has been performed yet.
  idle,

  /// Currently querying the [ManifestProvider] for a newer release.
  checking,

  /// Current build is up to date.
  upToDate,

  /// An update is available and ready for user action.
  updateAvailable,

  /// Silently pre-downloading the update artifact in the background.
  preDownloading,

  /// Verified update package is pre-staged on disk and ready for instant install.
  readyToInstall,

  /// Downloading the update artifact to local storage.
  downloading,

  /// Verifying SHA-256 checksum integrity.
  verifying,

  /// Handing off the verified artifact to the OS installer.
  installing,

  /// An error occurred during check, download, verification, or install.
  error,
}

/// Top-level entry point for configuring and accessing `upgate`.
class Upgate {
  Upgate._();

  static UpgateController? _controller;

  /// Whether [Upgate.initialize] has been called.
  static bool get isInitialized => _controller != null;

  /// Initializes the global [UpgateController] singleton.
  ///
  /// Defaults [provider] to [MbkRegistryProvider] and [installer] to the
  /// current platform's [UpgateInstaller].
  static UpgateController initialize({
    required UpgateConfig config,
    ManifestProvider? provider,
    UpgateInstaller? installer,
    Future<String> Function()? versionResolver,
  }) {
    final controller = UpgateController(
      config: config,
      provider: provider ?? MbkRegistryProvider(),
      installer: installer ?? createDefaultInstaller(),
      versionResolver: versionResolver,
    );
    _controller = controller;
    return controller;
  }

  /// Zero-boilerplate initializer for MBK Registry V2 using only your
  /// Registration Key (`appCode`, e.g. `REG_4829105736`).
  ///
  /// Platform and CPU architecture are detected automatically on all 6 Flutter
  /// targets (Android, iOS, Windows, macOS, Linux, and Web).
  static UpgateController initializeRegistry({
    required String appCode,
    String baseUrl = 'https://core.mbktech.org',
    List<String> fallbackBaseUrls = const [],
    String channel = 'production',
    String fallbackVersion = '1.0.0+1',
    Future<String?> Function()? authTokenProvider,
    Map<String, String> customHeaders = const {},
    ManifestProvider? provider,
    UpgateInstaller? installer,
    Future<String> Function()? versionResolver,
  }) {
    return initialize(
      config: UpgateConfig(
        appCode: appCode.trim(),
        baseUrl: baseUrl,
        fallbackBaseUrls: fallbackBaseUrls,
        channel: channel,
        fallbackVersion: fallbackVersion,
        authTokenProvider: authTokenProvider,
        customHeaders: customHeaders,
      ),
      provider: provider ?? MbkRegistryProvider(),
      installer: installer,
      versionResolver: versionResolver,
    );
  }

  /// Returns the initialized [UpgateController] singleton.
  ///
  /// Throws a [StateError] if [initialize] has not been called.
  static UpgateController get instance {
    final controller = _controller;
    if (controller == null) {
      throw StateError(
        'Upgate has not been initialized. Call Upgate.initialize(...) first.',
      );
    }
    return controller;
  }

  /// Alias for [instance] for ergonomic widget tree access.
  static UpgateController get controller => instance;

  /// Returns the active [UpgateInstaller] (or a standalone default instance
  /// if [initialize] has not been called).
  static UpgateInstaller get installer =>
      _controller?.installer ?? createDefaultInstaller();

  /// Resets the global singleton (intended for unit tests).
  @visibleForTesting
  static void resetForTesting() {
    _controller = null;
  }
}

/// Reactive state manager coordinating update checks, background pre-staging,
/// `remindIntervalHours` throttling, SHA-256 verification, and OS installs.
class UpgateController extends ChangeNotifier {
  /// Creates an [UpgateController].
  UpgateController({
    required this.config,
    required this.provider,
    UpgateInstaller? installer,
    Future<String> Function()? versionResolver,
  })  : _installer = installer ?? createDefaultInstaller(),
        _versionResolver = versionResolver;

  /// Active update configuration.
  final UpgateConfig config;

  /// Backend provider used to check for updates and fetch manifests.
  final ManifestProvider provider;

  final UpgateInstaller _installer;
  final Future<String> Function()? _versionResolver;

  UpdateState _state = UpdateState.idle;
  UpdateManifest? _manifest;
  double _downloadProgress = 0.0;
  String _progressText = '';
  String _statusMessage = '';
  Object? _lastError;
  DateTime? _lastCheckedAt;
  String? _installedVersion;
  bool _isChecking = false;
  bool _isDismissed = false;
  Future<UpdateManifest?>? _inFlightCheck;

  /// Current [UpdateState].
  UpdateState get state => _state;

  /// Latest [UpdateManifest] returned by [provider], if any.
  UpdateManifest? get manifest => _manifest;

  /// Normalized download progress in `0.0..1.0`.
  double get downloadProgress => _downloadProgress;

  /// Formatted download progress text (e.g. `12.4 / 24.0 MB (51%)`).
  String get progressText => _progressText;

  /// Human-readable status message for the active operation.
  String get statusMessage => _statusMessage;

  /// Most recent error captured by the controller, if [state] is [UpdateState.error].
  Object? get lastError => _lastError;

  /// Timestamp of the last completed update check.
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// Resolved `version+build` of the running application.
  String get installedVersion => _installedVersion ?? config.fallbackVersion;

  /// Whether an update check request is currently in flight.
  bool get isChecking => _isChecking;

  /// Whether a verified update package is pre-staged on disk.
  bool get isReadyToInstall => _state == UpdateState.readyToInstall;

  /// Whether a background pre-download is currently running.
  bool get isPreDownloading => _state == UpdateState.preDownloading;

  /// Whether an active foreground download, verification, or install is running.
  bool get isBusy =>
      _state == UpdateState.downloading ||
      _state == UpdateState.verifying ||
      _state == UpdateState.installing;

  /// Whether an update is currently available according to [manifest].
  bool get hasUpdate => _manifest?.hasUpdate ?? false;

  /// Whether the available update is mandatory and blocks app usage.
  bool get isForcedUpdate => _manifest?.isBlocking ?? false;

  /// Whether the user dismissed the current non-forced banner/prompt for this session.
  bool get isDismissed => _isDismissed;

  /// Exposes the configured [UpgateInstaller].
  UpgateInstaller get installer => _installer;

  Future<String> _resolveVersion() async {
    if (_installedVersion != null && _installedVersion!.isNotEmpty) {
      return _installedVersion!;
    }
    final resolved = _versionResolver != null
        ? await _versionResolver()
        : await PlatformInfo.resolveInstalledVersion(config.fallbackVersion);
    _installedVersion = resolved;
    return resolved;
  }

  /// Loads cached manifest state on cold start without blocking network calls.
  Future<void> initFromCache() async {
    if (_manifest != null) return;
    if (provider case final MbkRegistryProvider mbkProvider) {
      final version = await _resolveVersion();
      final cached = await mbkProvider.getCachedManifest(config, version);
      if (cached != null && _manifest == null) {
        _manifest = cached;
        notifyListeners();
      }
    }
  }

  /// Triggers an update check against [provider] with single in-flight deduplication.
  Future<UpdateManifest?> checkForUpdate({bool force = false}) {
    if (_inFlightCheck != null && !force) {
      return _inFlightCheck!;
    }
    final future = _executeCheckForUpdate(force: force);
    _inFlightCheck = future;
    return future.whenComplete(() {
      if (identical(_inFlightCheck, future)) {
        _inFlightCheck = null;
      }
    });
  }

  Future<UpdateManifest?> _executeCheckForUpdate({required bool force}) async {
    _isChecking = true;
    _lastError = null;
    if (_state == UpdateState.idle) {
      _state = UpdateState.checking;
    }
    notifyListeners();

    try {
      final currentVersion = await _resolveVersion();
      final res = await provider.checkForUpdate(
        config: config,
        currentVersion: currentVersion,
        bypassCache: force,
      );
      _manifest = res;
      _lastCheckedAt = res.checkedAt ?? DateTime.now();
      _isDismissed = false;

      if (res.hasUpdate) {
        final art = res.primaryArtifact;
        if (art != null && art.downloadUrl.isNotEmpty) {
          final stagedPath = await _installer.getPreStagedFilePath(
            version: res.latestVersion,
            fileName: art.fileName,
            packageFormat: art.packageFormat,
            url: art.downloadUrl,
            expectedSha256: art.sha256,
            cacheKey: config.appCode,
          );
          if (stagedPath != null) {
            _state = UpdateState.readyToInstall;
            _statusMessage = 'Update v${res.latestVersion} ready to install';
            _isChecking = false;
            notifyListeners();
            return res;
          }
          if (res.shouldPreDownload &&
              _state != UpdateState.preDownloading &&
              _state != UpdateState.downloading) {
            _runSilentPreDownload(res, art);
            _isChecking = false;
            notifyListeners();
            return res;
          }
        }
        _state = UpdateState.updateAvailable;
      } else {
        _state = UpdateState.upToDate;
      }

      _isChecking = false;
      notifyListeners();
      return res;
    } catch (e) {
      _isChecking = false;
      _lastError = e;
      _state = UpdateState.error;
      notifyListeners();
      return _manifest;
    }
  }

  /// Updates manifest directly (e.g. from 426 Upgrade Required body)
  void setManifest(UpdateManifest manifest) {
    _manifest = manifest;
    _lastCheckedAt = manifest.checkedAt ?? DateTime.now();
    _isDismissed = false;
    if (manifest.hasUpdate) {
      _state = UpdateState.updateAvailable;
      _statusMessage = 'Update v${manifest.latestVersion} available';
    } else {
      _state = UpdateState.upToDate;
      _statusMessage = '';
    }
    notifyListeners();
  }

  Future<String?>? _inFlightDownload;

  void _runSilentPreDownload(UpdateManifest manifest, UpdateArtifact artifact) {
    _state = UpdateState.preDownloading;
    _downloadProgress = 0.0;
    _statusMessage = 'Pre-downloading update in background...';
    notifyListeners();

    final task = _installer.downloadAndVerify(
      url: artifact.downloadUrl,
      fallbackUrls: artifact.fallbackUrls,
      version: manifest.latestVersion,
      expectedSha256: artifact.sha256,
      fileName: artifact.fileName,
      packageFormat: artifact.packageFormat,
      cacheKey: config.appCode,
      onProgress: (p) {
        if (_state == UpdateState.preDownloading) {
          _downloadProgress = p.progress;
          _progressText = '${p.receivedMb} / ${p.totalMb} MB (${p.percentage}%)';
          notifyListeners();
        }
      },
      onStatus: (msg) {
        if (_state == UpdateState.preDownloading) {
          _statusMessage = msg;
          notifyListeners();
        }
      },
    );
    _inFlightDownload = task;

    unawaited(
      task.then((path) {
        if (identical(_inFlightDownload, task)) {
          _inFlightDownload = null;
        }
        if (_state == UpdateState.downloading ||
            _state == UpdateState.verifying ||
            _state == UpdateState.installing) {
          return;
        }
        if (path != null) {
          _state = UpdateState.readyToInstall;
          _statusMessage = 'Update v${manifest.latestVersion} ready to install.';
        } else {
          _state = UpdateState.updateAvailable;
          _statusMessage = '';
        }
        notifyListeners();
      }).catchError((_) {
        if (identical(_inFlightDownload, task)) {
          _inFlightDownload = null;
        }
        if (_state == UpdateState.downloading ||
            _state == UpdateState.verifying ||
            _state == UpdateState.installing) {
          return;
        }
        _state = UpdateState.updateAvailable;
        _statusMessage = '';
        notifyListeners();
      }),
    );
  }

  /// Ensures [manifest] has a downloadable artifact, fetching `/manifest` if needed.
  Future<bool> prepareArtifact() async {
    if (_manifest?.primaryArtifact?.downloadUrl.isNotEmpty ?? false) {
      return true;
    }
    _isChecking = true;
    _statusMessage = 'Resolving release artifact...';
    notifyListeners();

    try {
      final full = await provider.fetchFullManifest(config: config);
      if (full?.primaryArtifact != null &&
          full!.primaryArtifact!.downloadUrl.isNotEmpty) {
        _manifest = _manifest != null
            ? _manifest!.copyWith(
                primaryArtifact: full.primaryArtifact,
                releaseNotes: _manifest!.releaseNotes ?? full.releaseNotes,
              )
            : full;
        _isChecking = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _lastError = e;
    }

    _isChecking = false;
    notifyListeners();
    return false;
  }

  /// Downloads, verifies, and launches installation for [artifact] (or the
  /// primary artifact in [manifest]).
  Future<void> downloadAndInstall({UpdateArtifact? artifact}) async {
    var targetArtifact = artifact ?? _manifest?.primaryArtifact;
    if (targetArtifact == null || targetArtifact.downloadUrl.isEmpty) {
      final prepared = await prepareArtifact();
      if (!prepared) {
        _lastError = Exception('No valid download link found for this platform.');
        _state = UpdateState.error;
        _statusMessage = 'No valid download link found for this platform.';
        notifyListeners();
        return;
      }
      targetArtifact = _manifest?.primaryArtifact;
    }

    if (targetArtifact == null || targetArtifact.downloadUrl.isEmpty) {
      _lastError = Exception('No download artifact available.');
      _state = UpdateState.error;
      notifyListeners();
      return;
    }

    // Await silent pre-download if already running to avoid concurrent file collision
    if (_inFlightDownload != null) {
      try {
        await _inFlightDownload;
      } catch (_) {}
    }

    _lastError = null;
    _downloadProgress = 0.0;
    _state = UpdateState.downloading;
    _statusMessage = 'Preparing update...';
    notifyListeners();

    try {
      await _installer.installArtifact(
        targetArtifact,
        version: _manifest?.latestVersion ?? config.fallbackVersion,
        requireChecksum: _manifest?.isBlocking ?? false,
        cacheKey: config.appCode,
        onProgress: (p) {
          _downloadProgress = p.progress;
          _progressText = '${p.receivedMb} / ${p.totalMb} MB (${p.percentage}%)';
          notifyListeners();
        },
        onStatus: (msg) {
          _statusMessage = msg;
          if (msg.toLowerCase().contains('verif')) {
            _state = UpdateState.verifying;
          } else if (msg.toLowerCase().contains('opening') ||
              msg.toLowerCase().contains('starting') ||
              msg.toLowerCase().contains('launching') ||
              msg.toLowerCase().contains('reloading')) {
            _state = UpdateState.installing;
          }
          notifyListeners();
        },
      );
      _state = UpdateState.readyToInstall;
      notifyListeners();
    } catch (e) {
      _lastError = e;
      _state = UpdateState.error;
      _statusMessage = e.toString();
      notifyListeners();
    }
  }

  /// Standalone convenience helper to download, verify, and install directly
  /// from a URL without requiring a server manifest.
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
  }) {
    return _installer.installFromUrl(
      url: url,
      fallbackUrls: fallbackUrls,
      version: version,
      expectedSha256: expectedSha256,
      fileName: fileName,
      packageFormat: packageFormat,
      installStrategy: installStrategy,
      installerArgs: installerArgs,
      requireChecksum: requireChecksum,
      cacheKey: config.appCode,
      onProgress: (p) {
        _downloadProgress = p.progress;
        _progressText = '${p.receivedMb} / ${p.totalMb} MB (${p.percentage}%)';
        notifyListeners();
      },
      onStatus: (msg) {
        _statusMessage = msg;
        notifyListeners();
      },
    );
  }

  String get _modalLastPromptKey =>
      '${config.localStoragePrefix}_modal_last_prompt_${config.appCode}';

  String get _modalLastVersionKey =>
      '${config.localStoragePrefix}_modal_last_version_${config.appCode}';

  /// Returns `true` if a Tier 3 modal reminder should be shown according to
  /// `manifest.policy.remindIntervalHours`.
  Future<bool> shouldShowModalReminder(UpdateManifest manifest) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastVersion = prefs.getString(_modalLastVersionKey);
      if (lastVersion != manifest.latestVersion) {
        return true;
      }
      final lastPromptMs = prefs.getInt(_modalLastPromptKey);
      if (lastPromptMs == null) return true;
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastPromptMs),
      );
      return elapsed.inHours >= manifest.policy.remindIntervalHours;
    } catch (_) {
      return true;
    }
  }

  /// Records that the Tier 3 modal reminder was shown for [version].
  Future<void> markModalPrompted(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modalLastVersionKey, version);
      await prefs.setInt(
        _modalLastPromptKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Dismisses a non-forced update prompt for the current session.
  void dismissUpdate() {
    _isDismissed = true;
    notifyListeners();
  }

  @protected
  void setStateForTesting(UpdateState newState) {
    _state = newState;
    notifyListeners();
  }
}
