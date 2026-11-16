import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/upgate_controller.dart';

/// Drop-in Material 3 settings section displaying:
/// 1. **OTA Distribution** card: status pill (`UP TO DATE`, `UPDATE AVAILABLE`,
///    `DEV BUILD (AHEAD)`, `UPDATE REQUIRED`, `CHECKING`, `OFFLINE`), installed
///    version, last checked timestamp & latency, check/download/install actions,
///    and live download progress.
/// 2. **Registry & Artifact Metadata** card: clean key-value rows for
///    `Installed Version`, `Latest Server Version`, `Platform / Arch`,
///    `Registry App Key` (with copy), `Registry Server`, `Channel / Policy`,
///    `Matched Artifact`, `Package Size`, and `SHA-256 Checksum` (with copy).
class UpgateSettingsSection extends StatelessWidget {
  /// Creates an [UpgateSettingsSection].
  const UpgateSettingsSection({
    super.key,
    required this.controller,
    this.showRegistryCard = true,
  });

  /// Update controller driving version status and manual checks/installs.
  final UpgateController controller;

  /// Whether to show the detailed **Registry & Artifact Metadata** card below
  /// the primary **OTA Distribution** card.
  final bool showRegistryCard;

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'Not checked yet';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 15) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _truncateHash(String? hash) {
    if (hash == null || hash.isEmpty) return 'Not specified';
    if (hash.length <= 20) return hash;
    return '${hash.substring(0, 10)}...${hash.substring(hash.length - 10)}';
  }

  void _copyValue(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final manifest = controller.manifest;
        final artifact = manifest?.primaryArtifact;
        final installed = controller.installedVersion;
        final busy = controller.isBusy || controller.isChecking;
        final isOffline = manifest == null || manifest.isOffline;
        final isAhead =
            !isOffline && manifest.isAheadOfServer(installed);
        final hasUpdate = !isOffline && !isAhead && manifest.hasUpdate;

        final String pillLabel;
        final Color pillColor;
        if (controller.isChecking) {
          pillLabel = 'CHECKING';
          pillColor = colorScheme.primary;
        } else if (manifest == null) {
          pillLabel = 'NOT CHECKED';
          pillColor = colorScheme.onSurfaceVariant;
        } else if (manifest.isOffline) {
          pillLabel = 'OFFLINE';
          pillColor = colorScheme.onSurfaceVariant;
        } else if (manifest.status == 'MAINTENANCE' ||
            manifest.status == 'UNREGISTERED') {
          pillLabel = 'MAINTENANCE';
          pillColor = colorScheme.error;
        } else if (manifest.isBlocking) {
          pillLabel = 'MANDATORY';
          pillColor = colorScheme.error;
        } else if (isAhead) {
          pillLabel = 'DEV BUILD (AHEAD)';
          pillColor = colorScheme.tertiary;
        } else if (hasUpdate) {
          pillLabel = 'UPDATE AVAILABLE';
          pillColor = colorScheme.primary;
        } else {
          pillLabel = 'UP TO DATE';
          pillColor = const Color(0xFF10B981);
        }

        final String headlineText;
        final String subtitleText;
        if (controller.isChecking) {
          headlineText = 'Checking for updates...';
          subtitleText = 'Installed: v$installed';
        } else if (manifest == null) {
          headlineText = 'Installed Client: v$installed';
          subtitleText = 'Tap Check for Updates to query the registry';
        } else if (manifest.isOffline) {
          headlineText = 'Registry Unreachable';
          subtitleText = 'Installed: v$installed • Offline mode';
        } else if (isAhead) {
          headlineText = 'Ahead of Server (Dev Build)';
          subtitleText =
              'Local: v$installed • Server: v${manifest.latestVersion}';
        } else if (hasUpdate) {
          headlineText = 'Update Available: v${manifest.latestVersion}';
          subtitleText = 'Installed: v$installed';
        } else {
          headlineText = 'Up to date (v$installed)';
          subtitleText =
              'Latest published: v${manifest.latestVersion}';
        }

        final latencyPart = manifest?.latencyMs != null
            ? ' • ${manifest!.latencyMs} ms'
            : '';
        final checkedPart =
            'Last checked: ${_formatTimestamp(controller.lastCheckedAt)}$latencyPart';

        final hasDownloadableArtifact =
            artifact != null && artifact.downloadUrl.trim().isNotEmpty;

        final String actionLabel;
        if (hasUpdate) {
          actionLabel = controller.isReadyToInstall
              ? 'Install v${manifest.latestVersion}'
              : 'Update to v${manifest.latestVersion}';
        } else {
          actionLabel = 'Download v${manifest?.latestVersion ?? installed}';
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.system_update_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'OTA Distribution',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: pillColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: pillColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (controller.isChecking)
                                SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: pillColor,
                                  ),
                                )
                              else
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: pillColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                pillLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: pillColor,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      headlineText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      checkedPart,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (controller.isBusy || controller.isPreDownloading) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: controller.downloadProgress > 0
                            ? controller.downloadProgress
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        controller.progressText.isNotEmpty
                            ? '${controller.statusMessage} (${controller.progressText})'
                            : controller.statusMessage,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (controller.state == UpdateState.error &&
                        controller.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        controller.lastError.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: busy
                              ? null
                              : () => controller.checkForUpdate(force: true),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            controller.isChecking
                                ? 'Checking...'
                                : 'Check for Updates',
                          ),
                        ),
                        if (hasUpdate || hasDownloadableArtifact)
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.downloadAndInstall(),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(actionLabel),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (showRegistryCard) ...[
              const SizedBox(height: 14),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registry & Artifact Metadata',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _KeyValueRow(
                        label: 'Installed Version',
                        value: 'v$installed',
                      ),
                      _KeyValueRow(
                        label: 'Latest Server Version',
                        value: isOffline
                            ? 'Unavailable'
                            : 'v${manifest.latestVersion}',
                      ),
                      _KeyValueRow(
                        label: 'Platform / Arch',
                        value:
                            '${controller.config.resolvedPlatform} (${controller.config.resolvedArchitecture})',
                      ),
                      _KeyValueRow(
                        label: 'Registry App Key',
                        value: controller.config.appCode,
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          tooltip: 'Copy App Key',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _copyValue(
                            context,
                            'Registry App Key',
                            controller.config.appCode,
                          ),
                        ),
                      ),
                      if (controller.config.baseUrl.trim().isNotEmpty)
                        _KeyValueRow(
                          label: 'Registry Server',
                          value: controller.config.baseUrl.trim(),
                        ),
                      _KeyValueRow(
                        label: 'Channel / Policy',
                        value:
                            '${manifest?.channel ?? controller.config.channel} • Tier ${manifest?.priority ?? 0} (${manifest?.policy.uiMode ?? 'NONE'})',
                      ),
                      _KeyValueRow(
                        label: 'Matched Artifact',
                        value: artifact?.fileName ??
                            (hasDownloadableArtifact
                                ? artifact.downloadUrl.split('/').last
                                : 'Not specified'),
                      ),
                      _KeyValueRow(
                        label: 'Package Size',
                        value: manifest?.humanSize ?? 'Pending',
                      ),
                      _KeyValueRow(
                        label: 'SHA-256 Checksum',
                        value: _truncateHash(artifact?.sha256),
                        trailing: (artifact?.sha256 != null &&
                                artifact!.sha256!.isNotEmpty)
                            ? IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                tooltip: 'Copy SHA-256',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _copyValue(
                                  context,
                                  'SHA-256 Checksum',
                                  artifact.sha256!,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 152,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
