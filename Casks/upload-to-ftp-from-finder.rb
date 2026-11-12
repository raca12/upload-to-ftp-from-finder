cask "upload-to-ftp-from-finder" do
  version "0.2.3"
  sha256 "9af48e0e41ef82fd706add8bbfda8c9f315a468780aff87c8e2c7d81cdee1a9c"

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
