# Changelog

All notable changes to **Upload to FTP from Finder** are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [SemVer](https://semver.org/).

## [0.2.4] — 2026-11-12

### Fixed
- FTP "Test Connection" / uploads could fail with **exit code 28 (timeout)** on servers behind NAT
  or restrictive firewalls. curl now ignores the PASV host, retries once with EPSV disabled, and the
  timeout was raised to 45s.
- Error messages now explain common curl codes (28 timeout, 7 connect, 67 login).

## [0.2.3] — 2026-11-12

### Added
- **Ctrl+V** (and Ctrl+C/X/A/Z) now works in text fields, in addition to ⌘V — for users switching from Windows

## [0.2.2] — 2026-11-12

### Fixed
- Editing shortcuts (⌘V/⌘C/⌘X/⌘A/⌘Z) are now also captured by a local key monitor,
  so paste works even if the hidden Edit menu is not reached (e.g. inside sheets)

## [0.2.1] — 2026-11-12

### Fixed
- **⌘V / ⌘C / ⌘A did not work** in the server editor and other text fields:
  the menu-bar-only app had no Edit menu, so standard editing shortcuts were never dispatched

## [0.2.0] — 2026-11-11

### Added
- First-run onboarding window that enables the Finder extension from inside the app (no terminal needed)
- GitHub Actions CI: build + 65 self-tests + bundle/signature checks on every push
- **Developer ID signing + Apple notarization** for release builds
- `PRIVACY.md`, `SUPPORT.md`

### Changed
- The app no longer touches the Keychain when building menus or the server list;
  passwords are read only when an upload or connection test needs them

## [0.1.1] — 2026-11-11

### Added
- **SFTP support** (password or SSH key auth, host key pinned in `~/.ssh/known_hosts`)
- **Keychain storage** for FTP/SFTP passwords, with automatic migration from older plain-text settings
- `tools/notarize.sh` (Developer ID signing + `notarytool` + stapling) and `tools/setup-signing.sh`
- Homebrew cask (`raca12/tap`) and a Turkish section in the README

### Fixed
- Finder menu "Quick upload" item was not localized
- English connection-test message had swapped format placeholders
- Passwords could be dropped from settings when a Keychain write failed (now only cleared after success)
- `sftp -b` disabled password authentication (commands are now fed via stdin)

## [0.1.0] — 2026-11-11

### Added
- First public build: Finder right-click upload, folder picker, thumbnails, link templates,
  password lock, TR/EN UI, CLI (`mcb`), FileZilla import, DMG/ZIP packaging
