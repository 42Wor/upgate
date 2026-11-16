# upgate

Multi-platform OTA update gating, 5-level policy enforcement, streaming SHA-256 verified installer staging, and adaptive Material 3 update UI for Flutter apps — across **Android, iOS, Windows, macOS, Linux, and Web**.

[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.4.0-0175C2?logo=dart)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.22.0-02569B?logo=flutter)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-008069)](#6-platform-setup-guide)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Feature Matrix

| Capability | Details |
|:---|:---|
| **3 Modular Usage Modes** | Full Registry V2 (`Upgate.initializeRegistry`), Static JSON (`JsonManifestProvider`), or Standalone Installer (`UpgateInstaller`) |
| **Zero-Boilerplate Auto-Detection** | Automatically detects OS (`android`, `ios`, `windows`, `macos`, `linux`, `web`) and CPU architecture (`arm64-v8a`, `x64`, `cloud_edge`, etc.) |
| **5-Level Policy Engine** | `0` Up to Date, `1` Silent Badge, `2` Floating Banner + Prefetch, `3` Modal Reminder (`remindIntervalHours`), `4` Hard Block, `5` Kill Switch / Maintenance |
| **Dev Build Safety** | SemVer comparison automatically detects when local build `> server` (`DEV BUILD (AHEAD)`) and suppresses false update prompts |
| **Streaming SHA-256 Integrity** | Chunked `openRead()` verification with zero RAM buffering and automatic mirror failover |
| **HTTP `426` Version Gate** | `VersionGateHttpClient` awaits & caches `version+build` on the first request, injects `X-App-*` headers, and triggers enforcement on `426` |
| **Theme-Native Material 3 UI** | `UpgateGuard`, `UpgateDialog`, `UpgateBlockScreen`, `UpgateBadge`, and `UpgateSettingsSection` inherit `Theme.of(context)` / `ColorScheme` |

---

## How & Where It Works in Your App

```text
+----------------------------------------------------------------------+
|  1. main() / Bootstrap                                               |
|     Upgate.initializeRegistry(appCode: 'REG_4829105736')             |
+----------------------------------------------------------------------+
         |                        |                        |
         v                        v                        v
+------------------+   +--------------------+   +----------------------+
| 2. Root Widget   |   | 3. API HTTP Layer  |   | 4. Navigation & UI   |
| UpgateGuard(     |   | VersionGateHttp    |   | - UpgateBadge()      |
|   child: Home()  |   |   Client(          |   |   (AppBar / Drawer)  |
| )                |   |   controller: ...  |   | - UpgateSettings     |
| - 15m resume chk |   | )                  |   |   Section()          |
| - Banner / Modal |   | - X-App-* headers  |   |   (Settings Screen)  |
| - Hard Block UI  |   | - 426 interception |   |                      |
+------------------+   +--------------------+   +----------------------+
```

---

## The App Registration Key (`REG_...`) System

When using **MBK Registry V2** (or any compatible registry), your application is identified by a single unified Registration Key (`appCode`, e.g. `REG_4829105736`).

* **One Key, All Platforms**: You pass only `appCode: 'REG_...'`. `upgate` automatically detects the running OS and CPU architecture, matches the right binary artifact on the server, and persists an anonymous `device_id` for deterministic percentage rollouts.
* **Customizing Server, Failover, Channel & Auth**:
  ```dart
  final controller = Upgate.initializeRegistry(
    appCode: 'REG_4829105736',
    baseUrl: 'https://core.mbktech.org',
    fallbackBaseUrls: ['https://backup.mbktech.org'],
    channel: 'production', // or 'beta', 'alpha'
    authTokenProvider: () async => await secureStorage.read(key: 'token'),
  );
  ```

---

## Quick Start (All 3 Usage Modes)

Add `upgate` to your `pubspec.yaml`:

```yaml
dependencies:
  upgate: ^1.1.0
```

### Mode 1: MBK Registry V2 (Registration Key Only)

```dart
import 'package:flutter/material.dart';
import 'package:upgate/upgate.dart';

void main() {
  final controller = Upgate.initializeRegistry(
    appCode: 'REG_4829105736',
    baseUrl: 'https://core.mbktech.org',
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

### Mode 2: Static JSON / No-Backend (`JsonManifestProvider`)

Host a `version.json` file on GitHub Pages, S3, Cloudflare R2, or any static CDN:

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

```dart
final controller = Upgate.initialize(
  config: const UpgateConfig(channel: 'stable'),
  provider: JsonManifestProvider(
    manifestUrl: Uri.parse('https://cdn.example.com/version.json'),
  ),
);
```

### Mode 3: Standalone Installer-Only (`UpgateInstaller`)

Download, stream-verify SHA-256, fail over across mirrors, and launch the OS installer directly without `UpgateGuard` or a version-check server:

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
2. Add `FileProvider` inside `<application>`:
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
Set `install_strategy: "store_redirect"` with your App Store URL (`https://apps.apple.com/app/id...`).

### Windows (`exe` / `msi`)
Verifies SHA-256, spawns the installer via `ProcessStartMode.detached`, verifies `pid > 0`, and exits cleanly so locked binaries can be overwritten.

### macOS (`dmg` / `pkg`) & Linux (`deb` / `AppImage`)
Downloads & verifies locally, launches via `open` (macOS) or `xdg-open` (Linux), with `url_launcher` fallback.

### Web (`web_reload`)
Zero `dart:io` imports; reloads or navigates cleanly via `url_launcher` (`webOnlyWindowName: '_self'`).

---

## Author & License

Created and maintained by **Maaz Waheed**.

See [ROADMAP.md](ROADMAP.md) for upcoming features (OS download notifications, HTTP `Range` resume, theme presets, and Ed25519 signatures).

Released under the [MIT License](LICENSE).
