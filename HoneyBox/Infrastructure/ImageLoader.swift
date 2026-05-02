import Foundation
import ImageIO
import UIKit

enum ImageLoaderError: Error {
    case cannotCreateImageSource
    case cannotDecodeImage
}

final class ImageLoader: @unchecked Sendable {
    /// File layout only; safe to use from background (e.g. import thumbnails).
    nonisolated private let storage: StorageService
    private let thumbCache = NSCache<NSString, UIImage>()
    private let fullCache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "dev.imflawlezz.HoneyBox.ImageLoader", qos: .userInitiated, attributes: .concurrent)

    init(storage: StorageService) {
        self.storage = storage
        thumbCache.countLimit = 400
        fullCache.countLimit = 24
    }

    private func cacheKey(authorId: String, albumId: String, fileName: String, kind: String) -> NSString {
        "\(authorId)/\(albumId)/\(kind)/\(fileName)" as NSString
    }

    func invalidateCaches() {
        thumbCache.removeAllObjects()
        fullCache.removeAllObjects()
    }

    func imageURL(authorId: String, albumId: String, fileName: String) -> URL {
        StoragePaths.imagesDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func thumbnailURL(authorId: String, albumId: String, fileName: String) -> URL {
        StoragePaths.thumbnailsDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func supportsAnimatedPlaybackExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "gif", "webp", "png": return true
        default: return false
        }
    }

    func loadThumbnailUIImage(
        authorId: String,
        albumId: String,
        thumbFileName: String,
        decodeMaxEdge: CGFloat = 280
    ) async throws -> UIImage? {
        let key = "\(authorId)/\(albumId)/t/\(thumbFileName)/\(Int(decodeMaxEdge))" as NSString
        if let hit = thumbCache.object(forKey: key) { return hit }
        let url = thumbnailURL(authorId: authorId, albumId: albumId, fileName: thumbFileName)
        let image = try await decodeDownsampled(url: url, maxPixel: decodeMaxEdge)
        if let image {
            thumbCache.setObject(image, forKey: key, cost: imageCost(image))
        }
        return image
    }

    func loadFullUIImage(ref: ImageRef) async throws -> UIImage? {
        let key = cacheKey(authorId: ref.authorId, albumId: ref.albumId, fileName: ref.fileName, kind: "f")
        if let hit = fullCache.object(forKey: key) { return hit }
        let url = imageURL(authorId: ref.authorId, albumId: ref.albumId, fileName: ref.fileName)
        let ext = (ref.fileName as NSString).pathExtension.lowercased()
        if Self.supportsAnimatedPlaybackExtension(ext) {
            let image = try await decodeAnimatedRepresentativeForFullCache(url: url, ext: ext)
            if let image {
                fullCache.setObject(image, forKey: key, cost: imageCost(image))
                return image
            }
        }
        let image = try await decodeDownsampled(url: url, maxPixel: 4096)
        if let image {
            fullCache.setObject(image, forKey: key, cost: imageCost(image))
        }
        return image
    }

    func loadFullCGImage(ref: ImageRef) async throws -> CGImage? {
        try await loadFullUIImage(ref: ref)?.cgImage
    }

    func loadThumbnailCGImage(
        authorId: String,
        albumId: String,
        thumbFileName: String,
        decodeMaxEdge: CGFloat = 280
    ) async throws -> CGImage? {
        try await loadThumbnailUIImage(
            authorId: authorId,
            albumId: albumId,
            thumbFileName: thumbFileName,
            decodeMaxEdge: decodeMaxEdge
        )?.cgImage
    }

    func loadDownsampledCGImage(url: URL, maxPixel: CGFloat) async throws -> CGImage? {
        try await decodeDownsampled(url: url, maxPixel: maxPixel)?.cgImage
    }

    func loadAnimatedRaster(ref: ImageRef, maxFrames: Int = AnimatedRasterDecoder.defaultMaxPlaybackFrames) async throws -> AnimatedGIF? {
        let url = imageURL(authorId: ref.authorId, albumId: ref.albumId, fileName: ref.fileName)
        let ext = (ref.fileName as NSString).pathExtension.lowercased()
        guard Self.supportsAnimatedPlaybackExtension(ext) else { return nil }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result {
                    try AnimatedRasterDecoder.loadPlaybackMetadata(
                        url: url,
                        ext: ext,
                        maxPlaybackFrames: maxFrames,
                        maxDecodedPixelDimension: 2048
                    )
                })
            }
        }
    }

    nonisolated func generateThumbnailJPEG(fromImageAt source: URL, to destination: URL, maxPixel: CGFloat = 768, quality: CGFloat = 0.88) throws {
        try storage.createDirectory(at: destination.deletingLastPathComponent())
        guard let data = try Self.downsampledJPEGData(url: source, maxPixel: maxPixel, quality: quality) else {
            throw ImageLoaderError.cannotDecodeImage
        }
        try data.write(to: destination, options: .atomic)
    }

    private func imageCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    private func decodeDownsampled(url: URL, maxPixel: CGFloat) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do {
                    let img = try Self.downsampledUIImage(url: url, maxPixel: maxPixel)
                    cont.resume(returning: img)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func decodeAnimatedRepresentativeForFullCache(url: URL, ext: String) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    cont.resume(returning: nil)
                    return
                }
                let count = CGImageSourceGetCount(source)
                guard count > 0 else {
                    cont.resume(returning: nil)
                    return
                }
                let useFirstFrame: Bool
                switch ext.lowercased() {
                case "gif":
                    useFirstFrame = true
                case "webp", "png":
                    useFirstFrame = count > 1
                default:
                    useFirstFrame = false
                }
                guard useFirstFrame, let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: UIImage(cgImage: cg))
            }
        }
    }

    private nonisolated static func downsampledUIImage(url: URL, maxPixel: CGFloat) throws -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let image = downsample(data: data, maxPixel: maxPixel) else {
            return nil
        }
        return image
    }

    private nonisolated static func downsampledJPEGData(url: URL, maxPixel: CGFloat, quality: CGFloat) throws -> Data? {
        guard let data = try? Data(contentsOf: url),
              let image = downsample(data: data, maxPixel: maxPixel),
              let jpeg = image.jpegData(compressionQuality: quality) else {
            return nil
        }
        return jpeg
    }

    private nonisolated static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: [NSString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [NSString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        let maxSide = max(width, height)
        let scale = min(1, maxPixel / maxSide)
        let targetW = max(1, Int(width * scale))
        let targetH = max(1, Int(height * scale))
        let downOpts: [NSString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetW, targetH)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, downOpts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

extension ImageLoader: ImageLoading {}
