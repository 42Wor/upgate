import '../config/upgate_config.dart';
import 'update_manifest.dart';

/// Abstraction for fetching release metadata and update policies from any backend.
///
/// Implement this interface to connect `upgate` to a custom API, Firebase Remote
/// Config, GitHub Releases, or an internal enterprise registry.
abstract interface class ManifestProvider {
  /// Evaluates whether an update is available for [currentVersion].
  Future<UpdateManifest> checkForUpdate({
    required UpgateConfig config,
    required String currentVersion,
    int? buildNumber,
    bool bypassCache = false,
  });

  /// Optionally fetches the full multi-platform release manifest for display
  /// in a software center or release notes view.
  Future<UpdateManifest?> fetchFullManifest({
    required UpgateConfig config,
  });
}
