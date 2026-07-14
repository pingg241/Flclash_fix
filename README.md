<div>

[**简体中文**](README_zh_CN.md)

</div>

# FlClash Fix

[![Android](https://github.com/pingg241/Flclash_fix/actions/workflows/build-android.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-android.yml)
[![Windows](https://github.com/pingg241/Flclash_fix/actions/workflows/build-windows.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-windows.yml)
[![Linux](https://github.com/pingg241/Flclash_fix/actions/workflows/build-linux.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-linux.yml)
[![macOS](https://github.com/pingg241/Flclash_fix/actions/workflows/build-macos.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-macos.yml)
[![License](https://img.shields.io/github/license/pingg241/Flclash_fix?style=flat-square)](LICENSE)

FlClash Fix is a community-maintained, reliability-focused modification of
[FlClash](https://github.com/chen08209/FlClash). It is a multi-platform proxy
client for Android, Windows, Linux, and macOS, powered by a customized
[Meta core](https://github.com/pingg241/Clash.Meta).

This repository is not an official FlClash or MetaCubeX release. Original
copyright, attribution, and GPL-3.0 license files are retained.

## What This Fork Improves

- Authenticated and bounded desktop IPC with timeouts, backpressure, reconnect
  handling, and explicit error propagation.
- Transactional core configuration, runtime startup, rollback, listener, DNS,
  NTP, Geo updater, TUN, and route lifecycle handling.
- Removal of false-success paths when core commands, proxy selection, profile
  switching, shutdown, connection close, or platform operations fail.
- Android VPN/TUN operation generations, bounded cancellation, JNI exception
  safety, secure shortcuts/deep links, and atomic icon caching.
- Hardened Windows helper authentication, caller validation, process lifecycle,
  build-mode isolation, and secure-storage native code.
- Minimal-privilege Linux/macOS TUN helpers, authenticated control messages,
  file-descriptor ownership checks, and safer token files.
- Durable backup, restore, clear, preference, and WebDAV credential transactions
  with crash recovery and ZIP traversal/bomb protection.
- Bounded downloads, API request bodies, queues, caches, and concurrent update
  work to reduce memory usage and blocking.
- Faster proxy-delay sorting, lazy log/request rendering, provider single-flight,
  and reduced repeated or quadratic work.
- Reproducible Android, Windows, Linux, and macOS GitHub Actions builds with
  automatic tagged releases and checksums.

## Screenshots

Desktop:

<p align="center">
  <img alt="FlClash desktop" src="snapshots/desktop.gif">
</p>

Mobile:

<p align="center">
  <img alt="FlClash mobile" src="snapshots/mobile.gif">
</p>

## Features

- Android, Windows, Linux, and macOS support
- Material You interface with adaptive layouts and themes
- Subscription import, proxy groups, rules, TUN mode, and system proxy support
- WebDAV synchronization and local backup/restore
- Dark mode, traffic/log views, connection management, and tray integration

## Downloads

Build artifacts and tagged releases are published at:

<https://github.com/pingg241/Flclash_fix/releases>

Android CI releases use the repository's public signing key when private
signing secrets are not configured. The public keystore is intentionally not a
secret and is suitable only for builds distributed by this fork.

## Build

Initialize the customized core:

```bash
git submodule update --init --recursive
```

Install Flutter, Go, Rust, and the platform SDK, then run:

```bash
dart setup.dart android
dart setup.dart windows
dart setup.dart linux
dart setup.dart macos
```

For CI parity:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

Pushing to `main` runs the independent platform workflows. Pushing a `v*` tag
builds every supported platform and publishes a GitHub Release only after all
build jobs succeed.

## Upstream

- FlClash: <https://github.com/chen08209/FlClash>
- Mihomo: <https://github.com/MetaCubeX/mihomo>
- Customized Meta core: <https://github.com/pingg241/Clash.Meta>

## License

GPL-3.0. See [LICENSE](LICENSE). Source for modified application and core
components is published in the repositories linked above.
