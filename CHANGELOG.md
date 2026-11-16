# Changelog

All notable changes to `upgate` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-11-17

### Added
- **Zero-Boilerplate Registration Key Initializer (`Upgate.initializeRegistry`)**: Initialize MBK Registry V2 with just your `appCode` (`REG_...`), automatic platform & CPU architecture detection, `fallbackBaseUrls`, and optional `authTokenProvider`.
- **Dev Build (Ahead-of-Server) Detection**: `UpdateManifest.isAheadOfServer` and `normalizedForInstalledVersion` prevent local development builds (`installedVersion > serverVersion`) from triggering update banners, modals, or blocking screens.
- **`UP_TO_DATE` Artifact Enrichment & Two-Card Settings UI**: `UpgateSettingsSection` now renders structured **OTA Distribution** (`DEV BUILD (AHEAD)`, `UP TO DATE`, `UPDATE AVAILABLE`, `UPDATE REQUIRED`) and **Registry & Artifact Metadata** cards with copyable App Key and SHA-256 checksum.

## [1.0.0] - 2026-11-17

### Added
- **Three Public Usage Modes:**
  - **Full OTA & Governance (`MbkRegistryProvider`)**: MBK Registry V2 `/api/v2/registry/check` & `/manifest` integration with `ETag` / `304`, `426` / `404` policy parsing, persistent anonymous `device_id` bucketing, `evaluated_for_version` offline cache invalidation, transient `MAINTENANCE` non-persistence, and automatic `UP_TO_DATE` artifact enrichment.
  - **No-Backend Static JSON (`JsonManifestProvider`)**: Client-side SemVer 2.0.0 comparator (supporting `major.minor.patch`, pre-release precedence, and `+build` numbers) for static `version.json` files hosted on GitHub Pages, S3, or any CDN.
  - **Standalone Installer-Only (`UpgateInstaller`)**: Direct cross-platform download, streaming chunked SHA-256 verification (`openRead()`), multi-mirror failover, and OS-native installation via `installFromUrl(...)` without adopting `UpgateGuard`.
- **Cross-Platform Support (All 6 Platforms):**
  - Conditional `dart:io` vs Web (`dart:js_interop`) platform/architecture detection with zero `dart:io` imports on Web.
  - Native launch support for Android (`open_filex`), Windows (`ProcessStartMode.detached` + clean exit), macOS/Linux (`open`/`xdg-open` + `url_launcher` fallback), iOS (`store_redirect`), and Web (`web_reload` cache-busting).
- **HTTP Version Gate & Adaptive Material 3 UI:**
  - `VersionGateHttpClient` (`http.BaseClient` wrapper) awaiting cached `version+build` on the first request, injecting `X-App-*` headers, and intercepting HTTP `426 Upgrade Required`.
  - `UpgateGuard` (15-minute resume throttle, `remindIntervalHours` enforcement, floating banner, hard block screen), `UpgateDialog`, `UpgateBlockScreen`, `UpgateBadge`, and `UpgateSettingsSection` inheriting `Theme.of(context)` / `ColorScheme`.
