import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/semver.dart';

/// Policy severity levels returned by an update server.
enum UpdateTier {
  /// Running version matches or exceeds the latest available release (level 0).
  upToDate(0),

  /// Non-intrusive indicator badge only (level 1).
  silentBadge(1),

  /// Dismissible floating banner or in-app prompt (level 2).
  floatingBanner(2),

  /// Modal dialog with optional grace period before enforcement (level 3).
  gracePeriodPrompt(3),

  /// Hard blocking screen requiring immediate update (level 4).
  criticalBlock(4),

  /// Emergency kill switch or maintenance lock disabling the current build (level 5).
  killSwitch(5);

  const UpdateTier(this.level);

  /// Numeric severity level (`0` through `5`).
  final int level;

  /// Resolves an [UpdateTier] from a numeric [level], defaulting to [upToDate].
  static UpdateTier fromLevel(int level) {
    return UpdateTier.values.firstWhere(
      (tier) => tier.level == level,
      orElse: () => UpdateTier.upToDate,
    );
  }
}

/// Update enforcement policy returned alongside a release check.
class UpdatePolicy {
  /// Creates an [UpdatePolicy].
  const UpdatePolicy({
    required this.tier,
    this.isUpdateAvailable = false,
    this.isForced = false,
    this.uiMode = 'NONE',
    this.preDownload = false,
    this.remindIntervalHours = 24,
    this.graceDeadline,
    this.graceRemainingSeconds,
    this.message,
    this.channel = 'production',
  });

  /// Enforcement tier controlling how the UI presents the update.
  final UpdateTier tier;

  /// Whether a newer release is available for the current client.
  final bool isUpdateAvailable;

  /// Whether the update blocks normal app usage until installed.
  final bool isForced;

  /// Server UI mode (`NONE`, `SILENT_BADGE`, `BANNER_PREFETCH`, `MODAL_REMINDER`, `HARD_BLOCK`).
  final String uiMode;

  /// Whether the client should pre-download the binary silently in the background.
  final bool preDownload;

  /// Minimum hours between modal reminder prompts for Tier 3 updates.
  final int remindIntervalHours;

  /// Optional deadline after which a grace-period update becomes mandatory.
  final DateTime? graceDeadline;

  /// Optional remaining seconds before [graceDeadline].
  final int? graceRemainingSeconds;

  /// Optional human-readable policy or maintenance message from the server.
  final String? message;

  /// Release channel associated with this policy.
  final String channel;
}

/// Downloadable binary or storefront artifact for a specific platform/architecture.
class UpdateArtifact {
  /// Creates an [UpdateArtifact].
  const UpdateArtifact({
    required this.platform,
    required this.downloadUrl,
    this.architecture = 'universal',
    this.fallbackUrls = const [],
    this.sha256,
    this.sizeBytes,
    this.sizeHuman,
    this.fileName,
    this.packageFormat,
    this.installStrategy,
    this.installerArgs,
  });

  /// Target platform (e.g. `android`, `windows`, `linux`, `macos`, `ios`, `web`).
  final String platform;

  /// Target CPU architecture (e.g. `universal`, `arm64-v8a`, `x64`).
  final String architecture;

  /// Primary download URL or storefront/web URL for this artifact.
  final String downloadUrl;

  /// Optional ordered failover mirror URLs.
  final List<String> fallbackUrls;

  /// Expected lowercase SHA-256 hex digest for integrity verification.
  final String? sha256;

  /// Optional file size in bytes.
  final int? sizeBytes;

  /// Optional human-readable file size (e.g. `24.5 MB`).
  final String? sizeHuman;

  /// Suggested local filename when downloading to disk.
  final String? fileName;

  /// Optional package format (e.g. `apk`, `exe`, `msi`, `deb`, `appimage`, `dmg`, `web_url`).
  final String? packageFormat;

  /// Optional installer strategy hint (e.g. `direct_install`, `store_redirect`, `web_reload`).
  final String? installStrategy;

  /// Optional CLI arguments passed to native desktop installers (e.g. `/SILENT`).
  final String? installerArgs;
}

/// Complete update check response and release metadata.
class UpdateManifest {
  /// Creates an [UpdateManifest].
  const UpdateManifest({
    required this.latestVersion,
    required this.policy,
    this.status = 'UP_TO_DATE',
    this.minVersion,
    this.buildNumber,
    this.channel = 'production',
    this.releaseNotes,
    this.publishedAt,
    this.primaryArtifact,
    this.artifacts = const [],
    this.latencyMs,
    this.checkedAt,
  });

  /// Raw registry/provider status (`UP_TO_DATE`, `UPDATE_AVAILABLE`,
  /// `UPDATE_MANDATORY`, `MAINTENANCE`, `UNREGISTERED`, `OFFLINE`).
  final String status;

  /// Semantic version string of the latest eligible release (e.g. `1.4.0`).
  final String latestVersion;

  /// Optional minimum supported version enforced by the server.
  final String? minVersion;

  /// Optional monotonic build number of the latest release.
  final int? buildNumber;

  /// Release channel this manifest belongs to.
  final String channel;

  /// Markdown or plain-text release notes.
  final String? releaseNotes;

  /// Timestamp when this release was published.
  final DateTime? publishedAt;

  /// Enforcement policy evaluated for the requesting client.
  final UpdatePolicy policy;

  /// Preferred artifact selected for the current platform and architecture.
  final UpdateArtifact? primaryArtifact;

  /// All artifacts attached to the release.
  final List<UpdateArtifact> artifacts;

  /// Measured round-trip network latency in milliseconds, if applicable.
  final int? latencyMs;

  /// Local timestamp when this manifest was evaluated.
  final DateTime? checkedAt;

  /// Parses an MBK Registry V2 or generic JSON check response.
  factory UpdateManifest.fromJson(
    Map<String, dynamic> json,
    String currentVersion, {
    String? platform,
    int? latencyMs,
    DateTime? checkedAt,
  }) {
    final statusStr = (json['status'] ?? 'UP_TO_DATE').toString().toUpperCase();
    final policyMap = (json['policy'] is Map<String, dynamic>)
        ? json['policy'] as Map<String, dynamic>
        : <String, dynamic>{};
    final artifactMap = (json['artifact'] is Map<String, dynamic>)
        ? json['artifact'] as Map<String, dynamic>
        : <String, dynamic>{};

    var priorityVal = 0;
    if (policyMap['priority'] is num) {
      priorityVal = (policyMap['priority'] as num).toInt();
    } else if (json['priority'] is num) {
      priorityVal = (json['priority'] as num).toInt();
    } else if (policyMap['priority_level'] is num) {
      priorityVal = (policyMap['priority_level'] as num).toInt();
    } else {
      switch (statusStr) {
        case 'UPDATE_MANDATORY':
          priorityVal = 4;
          break;
        case 'UPDATE_AVAILABLE':
          priorityVal = 2;
          break;
        case 'MAINTENANCE':
        case 'UNREGISTERED':
          priorityVal = 5;
          break;
        case 'UP_TO_DATE':
        default:
          priorityVal = 0;
          break;
      }
    }

    final clampedPriority = priorityVal.clamp(0, 5);
    final tier = (statusStr == 'MAINTENANCE' || statusStr == 'UNREGISTERED')
        ? UpdateTier.killSwitch
        : UpdateTier.fromLevel(clampedPriority);

    final defaultUiMode = switch (clampedPriority) {
      1 => 'SILENT_BADGE',
      2 => 'BANNER_PREFETCH',
      3 => 'MODAL_REMINDER',
      >= 4 => 'HARD_BLOCK',
      _ => 'NONE',
    };
    final uiModeStr =
        (policyMap['ui_mode'] ?? json['ui_mode'] ?? defaultUiMode)
            .toString()
            .toUpperCase();

    final rawFallbacks = json['fallback_urls'] ?? artifactMap['fallback_urls'];
    final fallbackList = <String>[];
    if (rawFallbacks is List) {
      for (final item in rawFallbacks) {
        if (item != null && item.toString().trim().isNotEmpty) {
          fallbackList.add(item.toString().trim());
        }
      }
    }

    DateTime? parsedGraceDeadline;
    final rawDeadline = policyMap['grace_deadline'] ?? json['grace_deadline'];
    if (rawDeadline != null) {
      parsedGraceDeadline = DateTime.tryParse(rawDeadline.toString());
    }

    final rawSize = json['size_bytes'] ??
        json['file_size_bytes'] ??
        artifactMap['file_size_bytes'] ??
        artifactMap['size_bytes'];
    int? parsedSizeBytes;
    if (rawSize is num) {
      parsedSizeBytes = rawSize.toInt();
    } else if (rawSize != null) {
      parsedSizeBytes = int.tryParse(rawSize.toString());
    }

    final downloadUrl = (json['download_url'] ??
            json['downloadUrl'] ??
            artifactMap['download_url'] ??
            artifactMap['url'])
        ?.toString();
    final sha256 = (json['sha256'] ??
            json['sha256_checksum'] ??
            artifactMap['sha256_checksum'] ??
            artifactMap['sha256'])
        ?.toString();
    final sizeHuman = (json['size_human'] ??
            json['file_size_human'] ??
            artifactMap['file_size_human'] ??
            artifactMap['size_human'])
        ?.toString();
    final fileName = (json['filename'] ??
            json['file_name'] ??
            artifactMap['filename'] ??
            artifactMap['file_name'])
        ?.toString();
    final packageFormat =
        (json['package_format'] ?? artifactMap['package_format'])?.toString();
    final installStrategy =
        (json['install_strategy'] ?? artifactMap['install_strategy'])
            ?.toString();
    final installerArgs =
        (json['installer_args'] ?? artifactMap['installer_args'])?.toString();
    final architecture = (json['architecture'] ??
            json['arch'] ??
            artifactMap['architecture'] ??
            'universal')
        .toString();
    final artifactPlatform =
        (artifactMap['platform'] ?? json['platform'] ?? platform ?? 'unknown')
            .toString();

    final hasArtifactData = (downloadUrl != null && downloadUrl.isNotEmpty) ||
        (fileName != null && fileName.isNotEmpty) ||
        (sha256 != null && sha256.isNotEmpty) ||
        (parsedSizeBytes != null && parsedSizeBytes > 0);

    final primaryArtifact = hasArtifactData
        ? UpdateArtifact(
            platform: artifactPlatform,
            architecture: architecture,
            downloadUrl: downloadUrl ?? '',
            fallbackUrls: fallbackList,
            sha256: sha256,
            sizeBytes: parsedSizeBytes,
            sizeHuman: sizeHuman,
            fileName: fileName,
            packageFormat: packageFormat,
            installStrategy: installStrategy,
            installerArgs: installerArgs,
          )
        : null;

    final channelStr =
        (json['channel'] ?? policyMap['channel'] ?? 'production').toString();
    final isBlocked = clampedPriority >= 4 ||
        statusStr == 'UPDATE_MANDATORY' ||
        statusStr == 'MAINTENANCE' ||
        statusStr == 'UNREGISTERED';
    final isAvailable = !isBlocked &&
            (clampedPriority >= 1 || statusStr == 'UPDATE_AVAILABLE') ||
        (isBlocked &&
            statusStr != 'MAINTENANCE' &&
            statusStr != 'UNREGISTERED');

    final policy = UpdatePolicy(
      tier: tier,
      isUpdateAvailable: isAvailable,
      isForced: isBlocked,
      uiMode: uiModeStr,
      preDownload:
          policyMap['pre_download'] == true || json['pre_download'] == true,
      remindIntervalHours:
          (policyMap['remind_interval_hours'] as num?)?.toInt() ??
              (json['remind_interval_hours'] as num?)?.toInt() ??
              24,
      graceDeadline: parsedGraceDeadline,
      graceRemainingSeconds:
          (policyMap['grace_remaining_seconds'] as num?)?.toInt() ??
              (json['grace_remaining_seconds'] as num?)?.toInt(),
      message: (policyMap['message'] ?? json['message'])?.toString(),
      channel: channelStr,
    );

    final rawBuild = json['build_number'] ?? json['buildNumber'];
    final buildNumber =
        rawBuild is num ? rawBuild.toInt() : int.tryParse('$rawBuild');

    return UpdateManifest(
      status: statusStr,
      latestVersion: json['latest_version']?.toString() ??
          json['latestVersion']?.toString() ??
          currentVersion,
      minVersion: json['min_version']?.toString() ??
          json['minRequiredVersion']?.toString(),
      buildNumber: buildNumber,
      channel: channelStr,
      releaseNotes: (json['notes'] ??
              json['release_notes'] ??
              json['releaseNotes'] ??
              json['changelog'])
          ?.toString(),
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      policy: policy,
      primaryArtifact: primaryArtifact,
      artifacts: primaryArtifact != null ? [primaryArtifact] : const [],
      latencyMs: latencyMs,
      checkedAt: checkedAt ?? DateTime.now(),
    );
  }

  /// Creates an `UP_TO_DATE` manifest for [currentVersion].
  factory UpdateManifest.upToDate(
    String currentVersion, {
    String channel = 'production',
    int? latencyMs,
  }) {
    return UpdateManifest(
      status: 'UP_TO_DATE',
      latestVersion: currentVersion,
      channel: channel,
      policy: UpdatePolicy(
        tier: UpdateTier.upToDate,
        channel: channel,
      ),
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
    );
  }

  /// Creates an offline fallback manifest when neither network nor cache is available.
  factory UpdateManifest.offline({
    String currentVersion = '',
    int? latencyMs,
  }) {
    return UpdateManifest(
      status: 'OFFLINE',
      latestVersion: currentVersion,
      policy: const UpdatePolicy(tier: UpdateTier.upToDate),
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
    );
  }

  /// Returns a copy of this manifest with selectively replaced fields.
  UpdateManifest copyWith({
    String? status,
    String? latestVersion,
    String? minVersion,
    int? buildNumber,
    String? channel,
    String? releaseNotes,
    DateTime? publishedAt,
    UpdatePolicy? policy,
    UpdateArtifact? primaryArtifact,
    List<UpdateArtifact>? artifacts,
    int? latencyMs,
    DateTime? checkedAt,
  }) {
    return UpdateManifest(
      status: status ?? this.status,
      latestVersion: latestVersion ?? this.latestVersion,
      minVersion: minVersion ?? this.minVersion,
      buildNumber: buildNumber ?? this.buildNumber,
      channel: channel ?? this.channel,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      publishedAt: publishedAt ?? this.publishedAt,
      policy: policy ?? this.policy,
      primaryArtifact: primaryArtifact ?? this.primaryArtifact,
      artifacts: artifacts ?? this.artifacts,
      latencyMs: latencyMs ?? this.latencyMs,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }

  /// Numeric enforcement priority (`0..5`).
  int get priority => policy.tier.level;

  /// True if update blocks execution (Priority 4 Critical Block or Priority 5 Kill-Switch / Maintenance).
  bool get isBlocking =>
      policy.isForced ||
      priority >= 4 ||
      status == 'UPDATE_MANDATORY' ||
      status == 'MAINTENANCE' ||
      status == 'UNREGISTERED';

  /// True if client is in offline fallback mode.
  bool get isOffline => status == 'OFFLINE';

  /// True if an update is available (Priorities 1 to 4, excluding maintenance/unregistered).
  bool get hasUpdate =>
      status != 'MAINTENANCE' &&
      status != 'UNREGISTERED' &&
      status != 'OFFLINE' &&
      (policy.isUpdateAvailable ||
          (priority >= 1 && priority <= 4) ||
          status == 'UPDATE_AVAILABLE' ||
          status == 'UPDATE_MANDATORY');

  /// True if client should stream and verify the package silently in background before prompting.
  bool get shouldPreDownload {
    final strategy = primaryArtifact?.installStrategy?.toLowerCase().trim();
    final format = primaryArtifact?.packageFormat?.toLowerCase().trim();
    return hasUpdate &&
        !isBlocking &&
        policy.preDownload &&
        !kIsWeb &&
        strategy != 'web_reload' &&
        strategy != 'store_redirect' &&
        format != 'web_url';
  }

  /// Priority 2 Banner mode (non-intrusive floating banner).
  bool get isBannerMode =>
      hasUpdate && !isBlocking && (priority == 2 || policy.uiMode == 'BANNER_PREFETCH');

  /// Priority 3 Modal reminder mode (grace period dialog).
  bool get isModalReminderMode =>
      hasUpdate && !isBlocking && (priority == 3 || policy.uiMode == 'MODAL_REMINDER');

  /// Priority 1 Silent badge mode (settings / badge indicator only).
  bool get isSilentBadgeMode =>
      hasUpdate && !isBlocking && (priority == 1 || policy.uiMode == 'SILENT_BADGE');

  /// True if the running [installedVersion] is strictly ahead of [latestVersion]
  /// (e.g. a local development build `1.4.0+14` vs published `1.3.0`).
  bool isAheadOfServer(String installedVersion) {
    if (isOffline ||
        status == 'MAINTENANCE' ||
        status == 'UNREGISTERED' ||
        latestVersion.trim().isEmpty ||
        installedVersion.trim().isEmpty) {
      return false;
    }
    return Semver.compare(installedVersion, latestVersion) > 0;
  }

  /// Returns a non-gating `UP_TO_DATE` copy when [installedVersion] is ahead
  /// of [latestVersion], preserving server metadata (`latestVersion`,
  /// `primaryArtifact`, `releaseNotes`) for display in Settings.
  UpdateManifest normalizedForInstalledVersion(String installedVersion) {
    if (!isAheadOfServer(installedVersion)) return this;
    return copyWith(
      status: 'UP_TO_DATE',
      policy: UpdatePolicy(
        tier: UpdateTier.upToDate,
        isUpdateAvailable: false,
        isForced: false,
        uiMode: 'NONE',
        preDownload: false,
        remindIntervalHours: policy.remindIntervalHours,
        channel: policy.channel,
      ),
    );
  }

  /// Formatted human-readable artifact size (e.g. `24.5 MB` or `Pending`).
  String get humanSize {
    final sizeHuman = primaryArtifact?.sizeHuman;
    if (sizeHuman != null && sizeHuman.trim().isNotEmpty) {
      return sizeHuman;
    }
    final sizeBytes = primaryArtifact?.sizeBytes;
    if (sizeBytes == null || sizeBytes <= 0) return 'Pending';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
