import 'package:flutter/material.dart';

import '../controller/upgate_controller.dart';
import 'upgate_dialog.dart';

/// Compact indicator badge shown when a non-intrusive update is available.
class UpgateBadge extends StatelessWidget {
  /// Creates an [UpgateBadge].
  const UpgateBadge({
    super.key,
    required this.controller,
    this.onTap,
  });

  /// Update controller observed for update availability.
  final UpgateController controller;

  /// Optional tap callback; defaults to opening [UpgateDialog.show].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasUpdate) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        return ActionChip(
          avatar: Icon(
            Icons.arrow_circle_up_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          label: Text('Update v${controller.manifest?.latestVersion ?? ''}'),
          onPressed: onTap ??
              () => UpgateDialog.show(context, controller: controller),
        );
      },
    );
  }
}
