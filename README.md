# upgate

Multi-platform OTA update gating, 5-level policy enforcement, streaming SHA-256 verified installer staging, and adaptive Material 3 update UI for Flutter apps — across **Android, iOS, Windows, macOS, Linux, and Web**.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Features

- **3 Modular Usage Modes**:
  1. **Full OTA & Governance (`MbkRegistryProvider`)** — Server-driven 5-level policy tiers, `ETag`/`304` caching, `426` enforcement, deterministic `device_id` staged rollouts, `evaluated_for_version` offline cache invalidation, and automatic `UP_TO_DATE` artifact metadata enrichment.
  2. **No-Backend Static JSON (`JsonManifestProvider`)** — Host a single `version.json` on GitHub Pages, S3, or Cloudflare R2 with built-in client-side SemVer 2.0.0 comparison (including pre-release tags and `+build` numbers).
  3. **Standalone Installer-Only (`UpgateInstaller`)** — Download, stream-verify SHA-256 checksums, fail over across mirror URLs, and launch native OS installers with a single function call (`installFromUrl`).
- **Streaming Chunked SHA-256 Verification** — Never buffers large installers in RAM (`openRead()`). Corrupt or mismatched files are deleted automatically.
- **Zero `dart:io` on Web** — Conditional imports guarantee clean compilation on all 6 Flutter targets.
- **Theme-Native Material 3 Widgets** — `UpgateGuard`, `UpgateDialog`, `UpgateBlockScreen`, `UpgateBadge`, and `UpgateSettingsSection` inherit `Theme.of(context)` and `ColorScheme` automatically, with optional custom builders.
- **HTTP `426` Version Gate Client** — `VersionGateHttpClient` awaits and caches installed `version+build` before the first request, injects `X-App-*` headers, and reacts to HTTP `426 Upgrade Required`.

---

## Architecture

```text
+-------------------------------------------------------------------+
|                        Flutter Application                        |
|  UpgateGuard  |  UpgateDialog  |  UpgateBadge  |  SettingsSection |
+-------------------------------------------------------------------+
                                 |
                                 v
+-------------------------------------------------------------------+
|                         UpgateController                          |
|  - In-flight check deduplication & 15m resume throttle            |
|  - remindIntervalHours persistence & silent background pre-stage  |
+-------------------------------------------------------------------+
             |                                      |
             v                                      v
+-------------------------+          +------------------------------+
|    ManifestProvider     |          |       UpgateInstaller        |
| - MbkRegistryProvider   |          | - Streaming SHA-256 verify   |
| - JsonManifestProvider  |          | - Mirror failover            |
| - Custom implementations|          | - Android/Win/Mac/Linux/Web  |
+-------------------------+          +------------------------------+
```

---

## Quick Start

Add `upgate` to your `pubspec.yaml`:

```yaml
dependencies:
  upgate: ^1.0.0
```

### Mode 1: Full OTA & Governance (`MbkRegistryProvider`)

```dart
import 'package:flutter/material.dart';
import 'package:upgate/upgate.dart';

void main() {
  final controller = Upgate.initialize(
    config: const UpgateConfig(
      appCode: 'APP_MYAPP_ANDR_001',
      baseUrl: 'https://core.example.com',
      channel: 'production',
    ),
    provider: MbkRegistryProvider(),
  );

  runApp(
    MaterialApp(
      home: UpgateGuard(
        controller: controller,
        child: const HomeScreen(),
      ),
    ),
  );
}
```

### Mode 2: No-Backend Static JSON (`JsonManifestProvider`)

Host a `version.json` file on GitHub Pages, S3, or any static CDN:

```json
{
  "latest_version": "1.4.0+15",
  "min_version": "1.2.0",
  "channel": "stable",
  "release_notes": "Improved performance and fixed offline sync.",
  "remind_interval_hours": 24,
  "artifacts": {
    "android": {
      "url": "https://cdn.example.com/myapp-1.4.0.apk",
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "format": "apk"
    },
    "windows": {
      "url": "https://cdn.example.com/myapp-1.4.0-setup.exe",
      "sha256": "...",
      "format": "exe",
      "installer_args": "/SILENT"
    },
    "ios": {
      "url": "https://apps.apple.com/app/id123456789",
      "install_strategy": "store_redirect"
    }
  }
}
```

Initialize `Upgate` with `JsonManifestProvider`:

```dart
final controller = Upgate.initialize(
  config: const UpgateConfig(channel: 'stable'),
  provider: JsonManifestProvider(
    manifestUrl: Uri.parse('https://cdn.example.com/version.json'),
  ),
);
```

### Mode 3: Standalone Installer-Only (`UpgateInstaller`)

If you only need cross-platform downloading, streaming SHA-256 verification, and OS-native installer launching without `UpgateGuard` or a manifest server:

```dart
final installer = UpgateInstaller(); // or Upgate.installer

await installer.installFromUrl(
  url: 'https://cdn.example.com/releases/app-1.4.0.apk',
  fallbackUrls: ['https://mirror.example.com/app-1.4.0.apk'],
  version: '1.4.0',
  expectedSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  onProgress: (p) => debugPrint('${p.percentage}% (${p.receivedMb}/${p.totalMb} MB)'),
  onStatus: (msg) => debugPrint(msg),
);
```

---

## 6-Platform Setup Guide

### Android (`apk` sideloading)

1. Add `REQUEST_INSTALL_PACKAGES` to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

2. Configure a `FileProvider` inside `<application>` in `AndroidManifest.xml`:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileProvider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

3. Create `android/app/src/main/res/xml/file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
    <external-cache-path name="external_cache" path="." />
    <files-path name="files" path="." />
</paths>
```

### iOS (`store_redirect`)

Direct binary sideloading is restricted on iOS. Set `install_strategy: "store_redirect"` with your App Store URL (`https://apps.apple.com/app/id...`). `upgate` launches it via `LaunchMode.externalApplication`.

### Windows (`exe` / `msi`)

`upgate` verifies SHA-256, spawns the installer with `ProcessStartMode.detached`, verifies `pid > 0`, and exits cleanly so the installer can overwrite locked binaries. Pass silent flags via `installer_args` (e.g. `"/SILENT"`).

### macOS (`dmg` / `pkg`) & Linux (`deb` / `AppImage`)

`upgate` downloads and verifies the package locally, launches it via `open` (macOS) or `xdg-open` (Linux), and falls back to `url_launcher` if needed.

### Web (`web_reload`)

`upgate` avoids `dart:io` entirely on Web and triggers a cache-busting reload or navigation via `url_launcher` (`webOnlyWindowName: '_self'`).

---

## HTTP Version Gate & Custom UI

Wrap your `http.Client` with `VersionGateHttpClient` to attach `X-App-Version`, `X-Platform`, `X-App-Arch`, and `X-App-Code` to every API request and react to HTTP `426 Upgrade Required`:

```dart
final client = VersionGateHttpClient(
  controller: controller,
  onUpgradeRequired: () => debugPrint('Server requested mandatory upgrade!'),
);
```

Customize `UpgateGuard` banners or blocking screens while keeping default Material 3 theme inheritance everywhere else:

```dart
UpgateGuard(
  controller: controller,
  bannerBuilder: (context, manifest, ctrl, onDismiss) => MyCustomBanner(...),
  blockScreenBuilder: (context) => MyCustomBlockScreen(...),
  child: const MyAppHome(),
)
```

Embed `UpgateSettingsSection(controller: controller)` in your Settings screen and `UpgateBadge(controller: controller)` in your `AppBar`.

---

## Author & License

Created and maintained by **Maaz Waheed**.

Released under the [MIT License](LICENSE).
