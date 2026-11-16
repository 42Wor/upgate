import 'package:flutter/material.dart';

import '../controller/upgate_controller.dart';
import '../domain/update_manifest.dart';

/// Material dialog presenting available release notes, download progress,
/// error feedback, and update actions using the host app's [ThemeData].
class UpgateDialog extends StatelessWidget {
  /// Creates an [UpgateDialog].
  const UpgateDialog({
    super.key,
    required this.controller,
    this.manifest,
  });

  /// Update controller driving download & install actions.
  final UpgateController controller;

  /// Optional manifest override; falls back to [UpgateController.manifest].
  final UpdateManifest? manifest;

  /// Convenience helper to display [UpgateDialog].
  static Future<void> show(
    BuildContext context, {
    required UpgateController controller,
    UpdateManifest? manifest,
    bool barrierDismissible = true,
  }) {
    final active = manifest ?? controller.manifest;
    final forced = active?.isBlocking ?? false;
    return showDialog<void>(
      context: context,
      barrierDismissible: forced ? false : barrierDismissible,
      builder: (_) => UpgateDialog(
        controller: controller,
        manifest: manifest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final activeManifest = manifest ?? controller.manifest;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final forced = activeManifest?.isBlocking ?? false;
        final busy = controller.isBusy;
        final ready = controller.isReadyToInstall;
        final hasError = controller.state == UpdateState.error;

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_rounded
                    : Icons.system_update_rounded,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  activeManifest != null
                      ? 'Update Available (v${activeManifest.latestVersion})'
                      : 'Update Available',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeManifest?.primaryArtifact != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Size: ${activeManifest!.humanSize} • Channel: ${activeManifest.channel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Text(
                  activeManifest?.releaseNotes?.trim().isNotEmpty == true
                      ? activeManifest!.releaseNotes!
                      : 'A new version is ready to install.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (busy || controller.isPreDownloading) ...[
                  const SizedBox(height: 16),
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
                  ),
                ],
                if (hasError && controller.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.lastError.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!forced && !busy)
              TextButton(
                onPressed: () {
                  controller.dismissUpdate();
                  Navigator.of(context).pop();
                },
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: busy ? null : () => controller.downloadAndInstall(),
              child: Text(
                busy
                    ? 'Installing...'
                    : (ready
                        ? 'Install Ready'
                        : (hasError ? 'Retry' : 'Update Now')),
              ),
            ),
          ],
        );
      },
    );
  }
}
