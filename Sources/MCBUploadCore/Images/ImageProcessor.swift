import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Görsel işleme (thumbnail + resize)
// MCB Upload'un "Automatic thumbnail creation" ve "Automatic image resizing" özellikleri.

public struct ImageProcessor {
    public init() {}

    public func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Görseli en-boy oranını koruyarak büyük kenardan küçültür. Gerek yoksa nil döner.
    public func resized(_ url: URL,
                        maxWidth: Int,
                        maxHeight: Int,
                        quality: Double) throws -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let (width, height) = (CGFloat(image.width), CGFloat(image.height))
        let scale = min(1, min(CGFloat(maxWidth) / width, CGFloat(maxHeight) / height))
        guard scale < 0.999 else { return nil }

        let newWidth = max(1, Int((width * scale).rounded()))
        let newHeight = max(1, Int((height * scale).rounded()))
        guard let context = CGContext(data: nil,
                                      width: newWidth,
                                      height: newHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let scaledImage = context.makeImage() else { return nil }

        let ext = self.formatExtension(for: url)
        let destination = try TempFiles.url(named: url.deletingPathExtension().lastPathComponent, extension: ext)
        try write(scaledImage, to: destination, isPNG: ext == "png", quality: quality)
        return destination
    }

    /// En uzun kenarı max(maxWidth, maxHeight) olacak şekilde thumbnail üretir.
    public func thumbnail(_ url: URL,
                          maxWidth: Int,
                          maxHeight: Int,
                          quality: Double) throws -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxPixel = max(maxWidth, maxHeight)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let ext = formatExtension(for: url)
        let destination = try TempFiles.url(named: url.deletingPathExtension().lastPathComponent, extension: ext)
        try write(thumb, to: destination, isPNG: ext == "png", quality: quality)

        // Kare olmayan hedefler için ikinci kez sığdır (isteğe bağlı, küçük sapmalar)
        if thumb.width > maxWidth || thumb.height > maxHeight {
            if let fitted = try resized(destination, maxWidth: maxWidth, maxHeight: maxHeight, quality: quality) {
                try? FileManager.default.removeItem(at: destination)
                return fitted
            }
        }
        return destination
    }

    public func imageSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    // MARK: - Yardımcılar

    private func formatExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "heic", "heif", "tiff", "tif", "gif", "webp":
            // Şeffaflığı korumak için PNG'ye çevir
            return ext == "png" ? "png" : "jpg"
        default:
            return "jpg"
        }
    }

    private func write(_ image: CGImage, to url: URL, isPNG: Bool, quality: Double) throws {
        let type = isPNG ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw MCBUploadError.transportFailed(exitCode: -1, message: "Görsel yazılamadı: \(url.lastPathComponent)")
        }
        let props: [CFString: Any] = isPNG ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MCBUploadError.transportFailed(exitCode: -1, message: "Görsel kaydedilemedi: \(url.lastPathComponent)")
        }
    }
}

// MARK: - Geçici dosyalar

public enum TempFiles {
    public static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcb-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static func url(extension ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    /// Geçici dosya, orijinal ada sahip olsun (progress mesajları ve HTTP dosya adı için).
    public static func url(named name: String, extension ext: String) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name).appendingPathExtension(ext)
    }

    public static func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
