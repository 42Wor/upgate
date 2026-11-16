import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgate/upgate.dart';

class _StubProvider implements ManifestProvider {
  _StubProvider(this.manifest);
  final UpdateManifest manifest;

  @override
  Future<UpdateManifest> checkForUpdate({
    required UpgateConfig config,
    required String currentVersion,
    int? buildNumber,
    bool bypassCache = false,
  }) async =>
      manifest;

  @override
  Future<UpdateManifest?> fetchFullManifest({
    required UpgateConfig config,
  }) async =>
      manifest;
}

class _NoopInstaller implements UpgateInstaller {
  @override
  bool get supportsDirectInstall => true;

  @override
  Future<String?> getPreStagedFilePath({
    required String version,
    String? fileName,
    String? packageFormat,
    String? url,
    String? expectedSha256,
    String cacheKey = 'upgate',
  }) async =>
      null;

  @override
  Future<String?> downloadAndVerify({
    required String url,
    List<String> fallbackUrls = const [],
    required String version,
    String? expectedSha256,
    String? fileName,
    String? packageFormat,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  }) async =>
      null;

  @override
  Future<void> installFromUrl({
    required String url,
    List<String> fallbackUrls = const [],
    required String version,
    String? expectedSha256,
    String? fileName,
    String? packageFormat,
    String? installStrategy,
    String? installerArgs,
    bool requireChecksum = false,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  }) async {}

  @override
  Future<void> installArtifact(
    UpdateArtifact artifact, {
    required String version,
    bool requireChecksum = false,
    String cacheKey = 'upgate',
    DownloadProgressCallback? onProgress,
    InstallerStatusCallback? onStatus,
  }) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('UpgateDialog displays version, release notes, and actions',
      (tester) async {
    final manifest = UpdateManifest.fromJson({
      'status': 'UPDATE_AVAILABLE',
      'latest_version': '2.1.0',
      'notes': 'Includes critical sync improvements.',
      'policy': {'priority': 3},
      'artifact': {'download_url': 'https://cdn.example.com/app.apk'},
    }, '1.0.0');

    final controller = UpgateController(
      config: const UpgateConfig(appCode: 'APP_WIDGET_01'),
      provider: _StubProvider(manifest),
      installer: _NoopInstaller(),
      versionResolver: () async => '1.0.0',
    );
    await controller.checkForUpdate();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpgateDialog(controller: controller),
        ),
      ),
    );

    expect(find.textContaining('2.1.0'), findsOneWidget);
    expect(find.text('Includes critical sync improvements.'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
  });

  testWidgets('UpgateBlockScreen displays required update message and CTA',
      (tester) async {
    final manifest = UpdateManifest.fromJson({
      'status': 'UPDATE_MANDATORY',
      'latest_version': '3.0.0',
      'policy': {'priority': 4, 'message': 'Minimum version required.'},
      'artifact': {'download_url': 'https://cdn.example.com/app.apk'},
    }, '1.0.0');

    final controller = UpgateController(
      config: const UpgateConfig(appCode: 'APP_WIDGET_02'),
      provider: _StubProvider(manifest),
      installer: _NoopInstaller(),
      versionResolver: () async => '1.0.0',
    );
    await controller.checkForUpdate();

    await tester.pumpWidget(
      MaterialApp(
        home: UpgateBlockScreen(controller: controller),
      ),
    );

    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('Minimum version required.'), findsOneWidget);
    expect(find.text('Download & Install'), findsOneWidget);
  });

  testWidgets('UpgateBadge renders only when update is available',
      (tester) async {
    final manifest = UpdateManifest.fromJson({
      'status': 'UPDATE_AVAILABLE',
      'latest_version': '1.9.0',
      'policy': {'priority': 1},
    }, '1.0.0');

    final controller = UpgateController(
      config: const UpgateConfig(appCode: 'APP_WIDGET_03'),
      provider: _StubProvider(manifest),
      installer: _NoopInstaller(),
      versionResolver: () async => '1.0.0',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpgateBadge(controller: controller),
        ),
      ),
    );
    expect(find.textContaining('Update'), findsNothing);

    await controller.checkForUpdate();
    await tester.pump();
    expect(find.text('Update v1.9.0'), findsOneWidget);
  });

  testWidgets('UpgateSettingsSection shows artifact metadata and check button',
      (tester) async {
    final manifest = UpdateManifest.fromJson({
      'status': 'UP_TO_DATE',
      'latest_version': '1.3.1',
      'policy': {'priority': 0},
      'artifact': {
        'filename': 'app-1.3.1.apk',
        'file_size_bytes': 2097152,
        'sha256_checksum': '0123456789abcdef0123456789abcdef',
      },
    }, '1.3.1+13');

    final controller = UpgateController(
      config: const UpgateConfig(
        appCode: 'APP_WIDGET_04',
        platform: 'android',
        architecture: 'arm64-v8a',
      ),
      provider: _StubProvider(manifest),
      installer: _NoopInstaller(),
      versionResolver: () async => '1.3.1+13',
    );
    await controller.checkForUpdate();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpgateSettingsSection(controller: controller),
        ),
      ),
    );

    expect(find.text('Software Updates'), findsOneWidget);
    expect(find.textContaining('app-1.3.1.apk'), findsOneWidget);
    expect(find.textContaining('2.0 MB'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
  });
}
