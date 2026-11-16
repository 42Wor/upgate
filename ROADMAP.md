# upgate Roadmap

This roadmap outlines upcoming milestones for [`upgate`](https://github.com/42Wor/upgate). Priorities may evolve based on community feedback and platform requirements.

---

## v1.2.0 — Native OS Download Notifications & Resumable Transfers

- **OS System Download Notifications**
  - Native operating-system notifications on **Android, Windows, macOS, and Linux** displaying a live download progress bar (`%` downloaded and MB transferred).
  - Completion notification (`"Update ready to install"`) that launches or focuses the installer when tapped.
  - Controlled via `UpgateConfig`:
    - `enableDownloadNotifications` (`bool`, default `false` / opt-in)
    - `notificationChannelId`, `notificationChannelName`, and `notificationTitle` customization options.
- **Resumable & Background Downloads**
  - HTTP `Range` header resume support for large desktop and mobile installers across network drops or app backgrounding.
  - Partial `.part` staging with automatic SHA-256 verification once the final byte range completes.

---

## v1.3.0 — UI Theme Presets & Slot Builders

- **Built-in UI Presets**
  - Ready-to-use `compact`, `glass`, and `enterprise` visual presets for `UpgateDialog`, `UpgateBlockScreen`, `UpgateGuard` banners, and `UpgateSettingsSection`.
- **Richer Slot & Component Builders**
  - Granular header, release-notes markdown, progress-indicator, and action-bar builders so teams can customize individual regions without rebuilding entire screens.

---

## Future — Channel Switching, Delta Updates & Cryptographic Signatures

- **In-App Release Channel Switcher**
  - Optional drop-in widget allowing testers/admins to switch between `production`, `beta`, and `canary` channels at runtime.
- **Binary Delta / Patch Updates**
  - Support for compact binary diff patches on desktop and mobile to minimize bandwidth for incremental releases.
- **Ed25519 / GPG Signature Verification**
  - Optional asymmetric public-key signature verification alongside SHA-256 checksums for high-assurance distribution pipelines.
