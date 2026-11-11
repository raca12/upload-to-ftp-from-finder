cask "upload-to-ftp-from-finder" do
  version "0.2.0"
  sha256 "b9f28e552f9fcc5cd38f99cb71c9ddb0784ab7b381dcb4ed01312be63a4cfcc3"

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
