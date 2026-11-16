import 'package:flutter/material.dart';
import 'package:upgate/upgate.dart';

void main() {
  // Mode 2 (No-Backend Static JSON): host a version.json on GitHub Pages, S3, or any CDN.
  final controller = Upgate.initialize(
    config: const UpgateConfig(
      appCode: 'APP_EXAMPLE_0001',
      channel: 'stable',
      fallbackVersion: '1.0.0+1',
    ),
    provider: JsonManifestProvider(
      manifestUrl: Uri.parse('https://updates.example.com/version.json'),
    ),
  );

  runApp(ExampleApp(controller: controller));
}

/// Minimal example app demonstrating [UpgateGuard], [UpgateSettingsSection],
/// [UpgateBadge], and standalone [UpgateInstaller].
class ExampleApp extends StatelessWidget {
  /// Creates an [ExampleApp].
  const ExampleApp({super.key, required this.controller});

  /// Initialized update controller.
  final UpgateController controller;

  Future<void> _runStandaloneInstall() async {
    // Mode 3 (Standalone Installer-Only): download, verify SHA-256, and install
    // directly from any URL without UpgateGuard or a version-check server.
    final installer = UpgateInstaller();
    await installer.installFromUrl(
      url: 'https://updates.example.com/releases/app-1.4.0.apk',
      version: '1.4.0',
      expectedSha256:
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Upgate Example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: UpgateGuard(
        controller: controller,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Upgate Example'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: UpgateBadge(controller: controller),
              ),
            ],
          ),
          body: ListView(
            children: [
              UpgateSettingsSection(controller: controller),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: _runStandaloneInstall,
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('Standalone Installer Demo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
