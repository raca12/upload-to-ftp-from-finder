# Support

## Something doesn't work

1. **Right-click menu missing?**
   ```sh
   pluginkit -m -i com.mcb.upload.FinderSync     # satır "+" ile başlamalı
   pluginkit -e use -i com.mcb.upload.FinderSync && killall Finder
   ```
   Or open the app → menu bar **▲** → *Finders integration…* and press **Enable Finder extension**.

2. **"App can't be opened" on first launch** — builds are ad-hoc signed:
   right-click the app → **Open**, or
   `xattr -dr com.apple.quarantine "/Applications/Upload to FTP from Finder.app"`

3. **Upload fails** — open the server in the app (**⋯**) and press **Test Connection**; the error line shows the FTP/SSH message.

## Logs

```sh
log show --last 5m --style compact --predicate 'subsystem == "com.mcb.upload"'   # extension
log show --last 5m --style compact --predicate 'process == "UploadToFTP"'        # app
```

SFTP debug dump (shows the exact command and server stderr):

```sh
MCB_SFTP_DEBUG=1 mcb test "My server"   # writes /tmp/mcb-sftp-debug.log
```

## Reporting a bug

Open an issue: https://github.com/raca12/upload-to-ftp-from-finder/issues

Please include:
- macOS version (`sw_vers`)
- app version (menu → *Security & Language…* or `mdls -name kMDItemVersion "/Applications/Upload to FTP from Finder.app"`)
- the protocol you used (FTP / FTPS / SFTP / HTTP)
- the error text (never paste your password)
