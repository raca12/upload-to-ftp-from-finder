cask "upload-to-ftp-from-finder" do
  version "0.2.1"
  sha256 "4e8d51e0777eea3a9bb012e31526a42220699c794616bd500ad98a20debb8b51"

  url "https://github.com/raca12/upload-to-ftp-from-finder/releases/download/v#{version}/UploadToFTP-#{version}.dmg",
      verified: "github.com/raca12/upload-to-ftp-from-finder/"
  name "Upload to FTP from Finder"
  desc "Right-click files in Finder to upload them to FTP/FTPS/SFTP with clipboard links"
  homepage "https://github.com/raca12/upload-to-ftp-from-finder"

  app "Upload to FTP from Finder.app"

  caveats <<~EOS
    The Finder extension must be enabled once:
      pluginkit -e use -i com.mcb.upload.FinderSync
      killall Finder

    Builds are ad-hoc signed, so the first launch needs:
      right click the app in /Applications → Open
  EOS
end
