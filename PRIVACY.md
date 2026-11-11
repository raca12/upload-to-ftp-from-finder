# Privacy

**Upload to FTP from Finder collects nothing.**

- No analytics, crash reporting, telemetry or accounts.
- The only network connections are the uploads you start (your FTP/FTPS/SFTP/HTTP servers) — plus an optional version check against GitHub Releases if enabled.
- Your servers, preferences and password hash stay on your Mac:
  - `~/Library/Application Support/MCBUpload/servers.json` (permissions `0600`)
  - `~/Library/Application Support/MCBUpload/security.json` (PBKDF2 hash only, `0600`)
  - FTP/SFTP passwords: macOS Keychain (`com.mcb.upload.ftp`)
- The Finder extension only reads the server **names** to build its menu; it never reads your files unless you pick them.
- Uninstalling: delete the app, then
  `rm -rf ~/Library/Application Support/MCBUpload` and remove the keychain items
  (`security delete-generic-password -s com.mcb.upload.ftp`).
