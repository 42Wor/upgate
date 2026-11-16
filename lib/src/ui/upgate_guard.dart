import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/upgate_controller.dart';
import '../domain/update_manifest.dart';
import 'upgate_block_screen.dart';
import 'upgate_dialog.dart';

/// Builder signature for custom floating update banners inside [UpgateGuard].
typedef UpgateBannerBuilder = Widget Function(
  BuildContext context,
  UpdateManifest manifest,
  UpgateController controller,
  VoidCallback onDismiss,
);

/// Root wrapper widget that observes app lifecycle events, enforces forced
/// updates via [UpgateBlockScreen], presents Tier 3 modal reminders respecting
/// `remindIntervalHours`, and displays Tier 2 floating banners.
class UpgateGuard extends StatefulWidget {
  /// Creates an [UpgateGuard].
  const UpgateGuard({
    super.key,
    required this.child,
    this.controller,
    this.checkOnStart = true,
    this.checkOnResume = true,
    this.blockScreenBuilder,
    this.bannerBuilder,
  });

  /// Protected application subtree.
  final Widget child;

  /// Optional controller override. Defaults to [Upgate.instance].
  final UpgateController? controller;

  /// Whether to trigger an update check when this widget initializes.
  final bool checkOnStart;

  /// Whether to trigger a throttled update check when the app resumes.
  final bool checkOnResume;

  /// Optional custom builder for the forced-update blocking screen.
  final WidgetBuilder? blockScreenBuilder;

  /// Optional custom builder for Tier 2 floating banners.
  final UpgateBannerBuilder? bannerBuilder;

  @override
  State<UpgateGuard> createState() => _UpgateGuardState();
}

class _UpgateGuardState extends State<UpgateGuard> with WidgetsBindingObserver {
  UpgateController? _controller;
  bool _promptedModalThisSession = false;
  bool _bannerDismissed = false;
  DateTime? _lastResumeCheck;

  UpgateController? get _effectiveController {
    if (_controller != null) return _controller;
    if (widget.controller != null) return widget.controller;
    return Upgate.isInitialized ? Upgate.instance : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _effectiveController;
    _controller?.addListener(_onControllerUpdated);

    if (widget.checkOnStart && _controller != null) {
      unawaited(_controller!.initFromCache());
      unawaited(_controller!.checkForUpdate());
    }
  }

  @override
  void didUpdateWidget(covariant UpgateGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller ??
        (Upgate.isInitialized ? Upgate.instance : null);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_onControllerUpdated);
      _controller = next;
      _controller?.addListener(_onControllerUpdated);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerUpdated);
    super.dispose();
  }

  void _onControllerUpdated() {
    if (!mounted) return;
    setState(() {});

    final controller = _controller;
    final manifest = controller?.manifest;
    if (controller != null &&
        manifest != null &&
        manifest.isModalReminderMode &&
        !_promptedModalThisSession) {
      _promptedModalThisSession = true;
      unawaited(_maybeShowModalReminder(controller, manifest));
    }
  }

  Future<void> _maybeShowModalReminder(
    UpgateController controller,
    UpdateManifest manifest,
  ) async {
    final allowed = await controller.shouldShowModalReminder(manifest);
    if (!allowed || !mounted) return;
    await controller.markModalPrompted(manifest.latestVersion);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpgateDialog.show(
          context,
          controller: controller,
          manifest: manifest,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.checkOnResume || state != AppLifecycleState.resumed) return;
    final controller = _effectiveController;
    if (controller == null) return;

    final now = DateTime.now();
    if (_lastResumeCheck == null ||
        now.difference(_lastResumeCheck!) >= controller.config.resumeThrottle) {
      _lastResumeCheck = now;
      unawaited(controller.checkForUpdate());
    }
  }

  Widget _buildDefaultBanner(
    BuildContext context,
    UpdateManifest manifest,
    UpgateController controller,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isReady = controller.isReadyToInstall;
    final isPreDownloading = controller.isPreDownloading;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Material(
          elevation: 6,
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isReady
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isReady
                      ? Icons.check_circle_rounded
                      : (isPreDownloading
                          ? Icons.cloud_download_rounded
                          : Icons.system_update_rounded),
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReady
                            ? 'Update v${manifest.latestVersion} Ready'
                            : (isPreDownloading
                                ? 'Downloading update (${controller.progressText.isNotEmpty ? controller.progressText : "in background"})...'
                                : 'Update Available (v${manifest.latestVersion})'),
                        style: theme.textTheme.labelLarge,
                      ),
                      if (isPreDownloading && controller.downloadProgress > 0) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: controller.downloadProgress,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () {
                    if (isReady) {
                      controller.downloadAndInstall();
                    } else {
                      UpgateDialog.show(
                        context,
                        controller: controller,
                        manifest: manifest,
                      );
                    }
                  },
                  child: Text(isReady ? 'Install' : 'Update'),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Dismiss',
                  onPressed: () {
                    setState(() => _bannerDismissed = true);
                    controller.dismissUpdate();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _effectiveController;
    final manifest = controller?.manifest;

    if (controller != null && manifest != null && manifest.isBlocking) {
      return widget.blockScreenBuilder?.call(context) ??
          UpgateBlockScreen(controller: controller);
    }

    final showBanner = controller != null &&
        manifest != null &&
        manifest.isBannerMode &&
        !_bannerDismissed &&
        !controller.isDismissed;

    if (!showBanner) {
      return widget.child;
    }

    final banner = widget.bannerBuilder?.call(
          context,
          manifest,
          controller,
          () {
            setState(() => _bannerDismissed = true);
            controller.dismissUpdate();
          },
        ) ??
        _buildDefaultBanner(context, manifest, controller);

    return Stack(
      children: [
        widget.child,
        Align(
          alignment: Alignment.topCenter,
          child: banner,
        ),
      ],
    );
  }
}
