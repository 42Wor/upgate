import 'package:flutter/material.dart';

import '../controller/upgate_controller.dart';

/// Full-screen non-dismissible blocking UI displayed for
/// [UpdateTier.criticalBlock] (Tier 4) and [UpdateTier.killSwitch] /
/// `MAINTENANCE` (Tier 5) policies.
class UpgateBlockScreen extends StatelessWidget {
  /// Creates an [UpgateBlockScreen].
  const UpgateBlockScreen({
    super.key,
    required this.controller,
  });

  /// Update controller supplying the active policy and install action.
  final UpgateController controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final manifest = controller.manifest;
          final isMaintenance = manifest?.status == 'MAINTENANCE' ||
              manifest?.status == 'UNREGISTERED';
          final hasDownload =
              manifest?.primaryArtifact?.downloadUrl.isNotEmpty ?? false;
          final busy = controller.isBusy;

          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMaintenance
                              ? Icons.engineering_rounded
                              : Icons.system_update_alt_rounded,
                          size: 60,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isMaintenance
                              ? 'Service Maintenance'
                              : 'Update Required',
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          manifest?.policy.message?.trim().isNotEmpty == true
                              ? manifest!.policy.message!
                              : 'Please update to the latest version to continue using this application.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (manifest != null && !isMaintenance) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Required: v${manifest.latestVersion}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        if (busy) ...[
                          const SizedBox(height: 20),
                          LinearProgressIndicator(
                            value: controller.downloadProgress > 0
                                ? controller.downloadProgress
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            controller.progressText.isNotEmpty
                                ? '${controller.statusMessage} (${controller.progressText})'
                                : controller.statusMessage,
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (controller.state == UpdateState.error &&
                            controller.lastError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            controller.lastError.toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (!isMaintenance || hasDownload)
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.downloadAndInstall(),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              busy ? 'Updating...' : 'Download & Install',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
