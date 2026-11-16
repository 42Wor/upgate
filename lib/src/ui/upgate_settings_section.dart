import 'package:flutter/material.dart';

import '../controller/upgate_controller.dart';

/// Drop-in Material settings card displaying current version, platform/arch,
/// artifact metadata (filename, size, SHA-256), and manual check/install actions.
class UpgateSettingsSection extends StatelessWidget {
  /// Creates an [UpgateSettingsSection].
  const UpgateSettingsSection({
    super.key,
    required this.controller,
  });

  /// Update controller driving version status and manual checks/installs.
  final UpgateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final manifest = controller.manifest;
        final artifact = manifest?.primaryArtifact;
        final busy = controller.isBusy || controller.isChecking;

        final statusLabel = controller.isChecking
            ? 'Checking for updates...'
            : (manifest == null
                ? 'Not checked yet'
                : (manifest.hasUpdate
                    ? 'Update available: v${manifest.latestVersion}'
                    : (manifest.isOffline
                        ? 'Offline / unreachable'
                        : 'Up to date (v${manifest.latestVersion})')));

        final shaPreview = artifact?.sha256 != null &&
                artifact!.sha256!.length >= 12
            ? '${artifact.sha256!.substring(0, 12)}...'
            : (artifact?.sha256 ?? 'Not specified');

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Software Updates',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            statusLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: busy
                          ? null
                          : () => controller.checkForUpdate(force: true),
                      child: Text(
                        controller.isChecking ? 'Checking...' : 'Check',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _MetaItem(
                      label: 'Installed',
                      value: controller.installedVersion,
                    ),
                    _MetaItem(
                      label: 'Platform',
                      value:
                          '${controller.config.resolvedPlatform} (${controller.config.resolvedArchitecture})',
                    ),
                    _MetaItem(
                      label: 'Channel',
                      value: controller.config.channel,
                    ),
                    if (artifact != null) ...[
                      _MetaItem(
                        label: 'Artifact',
                        value: artifact.fileName ?? 'Not specified',
                      ),
                      _MetaItem(
                        label: 'Size',
                        value: manifest?.humanSize ?? 'Pending',
                      ),
                      _MetaItem(
                        label: 'SHA-256',
                        value: shaPreview,
                      ),
                    ],
                  ],
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
                if (manifest != null && manifest.hasUpdate) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : () => controller.downloadAndInstall(),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      controller.isReadyToInstall
                          ? 'Install v${manifest.latestVersion}'
                          : 'Download & Install v${manifest.latestVersion}',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$label: $value',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
