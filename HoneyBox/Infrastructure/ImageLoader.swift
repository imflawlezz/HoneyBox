import Foundation
import ImageIO
import UIKit

enum ImageLoaderError: Error {
    case cannotCreateImageSource
    case cannotDecodeImage
}

final class ImageLoader: @unchecked Sendable {
    private let storage: StorageService
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

    func loadAnimatedRaster(ref: ImageRef, maxFrames: Int = 30_000) async throws -> AnimatedGIF? {
        let url = imageURL(authorId: ref.authorId, albumId: ref.albumId, fileName: ref.fileName)
        let ext = (ref.fileName as NSString).pathExtension.lowercased()
        guard Self.supportsAnimatedPlaybackExtension(ext) else { return nil }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result {
                    try Self.decodeAnimatedRaster(url: url, ext: ext, maxFrames: maxFrames)
                })
            }
        }
    }

    func generateThumbnailJPEG(fromImageAt source: URL, to destination: URL, maxPixel: CGFloat = 768, quality: CGFloat = 0.88) throws {
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

    private static let animatedRasterAbsoluteFrameCap = 40_000

    private static func decodeAnimatedRaster(url: URL, ext: String, maxFrames: Int) throws -> AnimatedGIF? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.cannotCreateImageSource
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        switch ext.lowercased() {
        case "webp", "png":
            guard count > 1 else { return nil }
        default:
            break
        }
        let limit = min(count, maxFrames, animatedRasterAbsoluteFrameCap)
        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        frames.reserveCapacity(limit)
        delays.reserveCapacity(limit)
        for i in 0..<limit {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let delay = Self.frameDelay(source: source, index: i)
            frames.append(cg)
            delays.append(delay)
        }
        guard !frames.isEmpty else { return nil }
        if delays.allSatisfy({ $0 <= 0 }) {
            delays = Array(repeating: 0.1, count: frames.count)
        }
        return AnimatedGIF(frames: frames, delays: delays)
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [AnyHashable: Any] else {
            return 0.1
        }
        if let gif = props[kCGImagePropertyGIFDictionary as AnyHashable] as? [AnyHashable: Any] {
            let u = double(from: gif, key: kCGImagePropertyGIFUnclampedDelayTime as AnyHashable)
            let c = double(from: gif, key: kCGImagePropertyGIFDelayTime as AnyHashable)
            let d = u ?? c ?? 0.1
            return d < 0.02 ? 0.1 : d
        }
        if let webp = props[kCGImagePropertyWebPDictionary as AnyHashable] as? [AnyHashable: Any] {
            let u = double(from: webp, key: kCGImagePropertyWebPUnclampedDelayTime as AnyHashable)
            let c = double(from: webp, key: kCGImagePropertyWebPDelayTime as AnyHashable)
            let d = u ?? c ?? 0.1
            return d < 0.02 ? 0.1 : d
        }
        if let u = double(from: props, key: kCGImagePropertyAPNGUnclampedDelayTime as AnyHashable) {
            let d = u < 0.02 ? 0.1 : u
            return d
        }
        if let c = double(from: props, key: kCGImagePropertyAPNGDelayTime as AnyHashable) {
            let d = c < 0.02 ? 0.1 : c
            return d
        }
        if let png = props[kCGImagePropertyPNGDictionary as AnyHashable] as? [AnyHashable: Any] {
            if let u = double(from: png, key: kCGImagePropertyAPNGUnclampedDelayTime as AnyHashable) {
                return u < 0.02 ? 0.1 : u
            }
            if let c = double(from: png, key: kCGImagePropertyAPNGDelayTime as AnyHashable) {
                return c < 0.02 ? 0.1 : c
            }
        }
        return 0.1
    }

    private static func double(from dict: [AnyHashable: Any], key: AnyHashable) -> Double? {
        if let d = dict[key] as? Double { return d }
        if let n = dict[key] as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func downsampledUIImage(url: URL, maxPixel: CGFloat) throws -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let image = downsample(data: data, maxPixel: maxPixel) else {
            return nil
        }
        return image
    }

    private static func downsampledJPEGData(url: URL, maxPixel: CGFloat, quality: CGFloat) throws -> Data? {
        guard let data = try? Data(contentsOf: url),
              let image = downsample(data: data, maxPixel: maxPixel),
              let jpeg = image.jpegData(compressionQuality: quality) else {
            return nil
        }
        return jpeg
    }

    private static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
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

struct AnimatedGIF: Sendable {
    var frames: [CGImage]
    var delays: [TimeInterval]

    var boundsPixelWidth: CGFloat {
        frames.map { CGFloat($0.width) }.max() ?? 1
    }

    var boundsPixelHeight: CGFloat {
        frames.map { CGFloat($0.height) }.max() ?? 1
    }

    var boundsAspectRatio: CGFloat {
        boundsPixelWidth / max(boundsPixelHeight, 1)
    }
}
