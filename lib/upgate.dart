/// Standalone multi-platform OTA update gating, SHA-256 verified installer
/// staging, and adaptive Material 3 update UI for Flutter apps.
library;

export 'src/config/upgate_config.dart';
export 'src/controller/upgate_controller.dart';
export 'src/domain/manifest_provider.dart';
export 'src/domain/update_manifest.dart';
export 'src/installer/installer_interface.dart';
export 'src/network/version_gate_client.dart';
export 'src/providers/json_manifest_provider.dart';
export 'src/providers/mbk_registry_provider.dart';
export 'src/ui/upgate_badge.dart';
export 'src/ui/upgate_block_screen.dart';
export 'src/ui/upgate_dialog.dart';
export 'src/ui/upgate_guard.dart';
export 'src/ui/upgate_settings_section.dart';
export 'src/utils/platform_info.dart';
export 'src/utils/semver.dart';
