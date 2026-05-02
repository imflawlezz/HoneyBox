import CoreGraphics
import Foundation
import ImageIO
import UIKit

protocol ImageLoading: AnyObject, Sendable {
    func invalidateCaches()
    func imageURL(authorId: String, albumId: String, fileName: String) -> URL
    func thumbnailURL(authorId: String, albumId: String, fileName: String) -> URL
    func loadThumbnailUIImage(
        authorId: String,
        albumId: String,
        thumbFileName: String,
        decodeMaxEdge: CGFloat
    ) async throws -> UIImage?
    func loadFullUIImage(ref: ImageRef) async throws -> UIImage?
    func loadFullCGImage(ref: ImageRef) async throws -> CGImage?
    func loadThumbnailCGImage(
        authorId: String,
        albumId: String,
        thumbFileName: String,
        decodeMaxEdge: CGFloat
    ) async throws -> CGImage?
    func loadDownsampledCGImage(url: URL, maxPixel: CGFloat) async throws -> CGImage?
    func loadAnimatedRaster(ref: ImageRef, maxFrames: Int) async throws -> AnimatedGIF?
    nonisolated func generateThumbnailJPEG(fromImageAt source: URL, to destination: URL, maxPixel: CGFloat, quality: CGFloat) throws

    static func supportsAnimatedPlaybackExtension(_ ext: String) -> Bool
}

extension ImageLoading {
    func loadAnimatedRaster(ref: ImageRef) async throws -> AnimatedGIF? {
        try await loadAnimatedRaster(ref: ref, maxFrames: AnimatedRasterDecoder.defaultMaxPlaybackFrames)
    }
}

/// Animated playback metadata — **never** retains decoded frames; bitmaps come from disk on demand.
struct AnimatedGIF: Sendable {
    /// File on disk backing this clip.
    var sourceURL: URL
    /// Number of logical frames surfaced to the player (`min(encoderCount, cap)`).
    var frameCount: Int
    /// Logical canvas sized from encoder metadata (`max(width × height)` over a bounded property scan).
    var canvasPixelWidth: CGFloat
    var canvasPixelHeight: CGFloat
    /// Downscaled edge so decoding never loads full-megapixel bursts into RAM while playing.
    var maxDecodedPixelDimension: CGFloat
    /// When non-nil (`short clips`), delays after frame `i` before advancing — avoids millions of floats for long loops.
    var embeddedDelays: [TimeInterval]?

    var boundsPixelWidth: CGFloat { canvasPixelWidth }
    var boundsPixelHeight: CGFloat { canvasPixelHeight }

    var boundsAspectRatio: CGFloat {
        canvasPixelWidth / max(canvasPixelHeight, 1)
    }

    func delay(afterFrame index: Int) -> TimeInterval {
        guard frameCount > 0 else { return 0.1 }
        let i = ((index % frameCount) + frameCount) % frameCount
        if let embeddedDelays, embeddedDelays.indices.contains(i) {
            return Self.sanitizedDelay(embeddedDelays[i])
        }
        return Self.sanitizedDelay((try? AnimatedRasterDecoder.frameDelayFromFile(url: sourceURL, frameIndex: i)) ?? 0.1)
    }

    func decodeFrame(at index: Int) throws -> CGImage {
        guard frameCount > 0 else {
            throw ImageLoaderError.cannotDecodeImage
        }
        let i = ((index % frameCount) + frameCount) % frameCount
        return try AnimatedRasterDecoder.decodeFrame(
            url: sourceURL,
            frameIndex: i,
            maxPixelDimension: maxDecodedPixelDimension
        )
    }

    private static func sanitizedDelay(_ raw: TimeInterval) -> TimeInterval {
        let d = raw <= 0 ? 0.1 : raw
        let clampedGifMinimum: TimeInterval = d < 0.02 ? 0.1 : d
        return max(clampedGifMinimum, 1.0 / 60.0)
    }
}

/// Playback session retaining one `CGImageSource` for its lifetime — decode / delay queries share one handle instead of reopening the file each tick (which starved loaders and stalled other images).
final class AnimatedRasterPlaybackSession: @unchecked Sendable {
    private let lock = NSLock()
    /// Reads/writes are serialized by `lock`; `nonisolated(unsafe)` avoids bogus MainActor isolation from `UIKit`/`ImageIO`.
    nonisolated(unsafe) private let source: CGImageSource
    private let surfacedFrameCount: Int
    nonisolated(unsafe) private let thumbnailOpts: CFDictionary
    private let embeddedDelaysDense: ContiguousArray<TimeInterval>?

    nonisolated init(descriptor: AnimatedGIF) throws {
        let baseOpts = [kCGImageSourceShouldCache: false] as NSDictionary
        guard let raw = CGImageSourceCreateWithURL(descriptor.sourceURL as CFURL, baseOpts) else {
            throw ImageLoaderError.cannotCreateImageSource
        }
        guard CGImageSourceGetCount(raw) > 0 else { throw ImageLoaderError.cannotDecodeImage }

        surfacedFrameCount = descriptor.frameCount

        let maxPx = AnimatedRasterDecoder.thumbnailMaxPixelInt(forDecodedDimension: descriptor.maxDecodedPixelDimension)
        thumbnailOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx
        ] as [CFString: Any] as CFDictionary

        if let table = descriptor.embeddedDelays, table.count == descriptor.frameCount {
            embeddedDelaysDense = ContiguousArray(table)
        } else {
            embeddedDelaysDense = nil
        }
        source = raw
    }

    nonisolated func decodedFrame(forLogicalIndex logical: Int) throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        guard surfacedFrameCount > 0 else { throw ImageLoaderError.cannotDecodeImage }
        let idx = AnimatedRasterPlaybackSession.normalized(logical, modulo: surfacedFrameCount)
        guard idx < CGImageSourceGetCount(source) else { throw ImageLoaderError.cannotDecodeImage }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, idx, thumbnailOpts) else {
            throw ImageLoaderError.cannotDecodeImage
        }
        return cg
    }

    nonisolated func delayAfterFrame(_ logicalIndex: Int) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard surfacedFrameCount > 0 else { return 1.0 / 60.0 }
        let idx = AnimatedRasterPlaybackSession.normalized(logicalIndex, modulo: surfacedFrameCount)
        if let dense = embeddedDelaysDense, idx < dense.count {
            return FrameTiming.sanitized(dense[idx])
        }
        return FrameTiming.sanitized(AnimatedRasterDecoder.copyDelay(from: source, frameIndex: idx))
    }

    private nonisolated static func normalized(_ index: Int, modulo count: Int) -> Int {
        ((index % count) + count) % count
    }
}

private enum FrameTiming {
    nonisolated static func sanitized(_ raw: TimeInterval) -> TimeInterval {
        let d = raw <= 0 ? 0.1 : raw
        let minGif = d < 0.02 ? 0.1 : d
        return max(minGif, 1.0 / 60.0)
    }
}

// MARK: - Streaming animated decode (bounded memory)

enum AnimatedRasterDecoder {
    /// Playback never loads more metadata than this; keeps delay arrays sane.
    nonisolated static let defaultMaxPlaybackFrames = 50_000

    /// Hard safety bound — still allows long GIFs/wallpapers without pre-decoding raster.
    nonisolated private static let absoluteFrameHardCap = 50_000
    /// If frame count exceeds this we **do not** embed delay arrays — use `AnimatedRasterPlaybackSession` (single open source).
    nonisolated private static let embedDelayArrayMaxFrames = 4_096
    /// How many indexes to probe for canvas sizing when we cannot scan every metadata entry.
    nonisolated private static let canvasPropertyScanBudget = 768

    nonisolated static func loadPlaybackMetadata(url: URL, ext: String, maxPlaybackFrames: Int, maxDecodedPixelDimension: CGFloat) throws -> AnimatedGIF? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as NSDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ImageLoaderError.cannotCreateImageSource
        }
        let rawCount = CGImageSourceGetCount(source)
        guard rawCount > 0 else { return nil }

        switch ext.lowercased() {
        case "webp", "png":
            guard rawCount > 1 else { return nil }
        default:
            break
        }

        let capped = min(rawCount, maxPlaybackFrames, absoluteFrameHardCap)
        guard capped > 0 else { return nil }

        var canvasW: CGFloat = 1
        var canvasH: CGFloat = 1
        for probe in evenlySpacedFrameIndices(total: capped, budget: canvasPropertyScanBudget) {
            if let size = logicalPixelDimensions(source: source, frameIndex: probe) {
                canvasW = max(canvasW, size.width)
                canvasH = max(canvasH, size.height)
            }
        }

        let embeddedDelays: [TimeInterval]?
        if capped <= embedDelayArrayMaxFrames {
            var delays: [TimeInterval] = []
            delays.reserveCapacity(capped)
            for i in 0..<capped {
                delays.append(Self.copyDelay(from: source, frameIndex: i))
            }
            normalizeDelaysIfNeeded(&delays)
            embeddedDelays = delays
        } else {
            embeddedDelays = nil
        }

        let dim = sanitizeDecodeDimension(maxDecodedPixelDimension)

        return AnimatedGIF(
            sourceURL: url,
            frameCount: capped,
            canvasPixelWidth: max(canvasW, 1),
            canvasPixelHeight: max(canvasH, 1),
            maxDecodedPixelDimension: dim,
            embeddedDelays: embeddedDelays
        )
    }

    /// Single-frame raster with hard pixel cap — safe to call repeatedly from workers.
    nonisolated static func decodeFrame(url: URL, frameIndex: Int, maxPixelDimension: CGFloat) throws -> CGImage {
        guard frameIndex >= 0 else {
            throw ImageLoaderError.cannotDecodeImage
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as NSDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ImageLoaderError.cannotCreateImageSource
        }
        guard frameIndex < CGImageSourceGetCount(source) else {
            throw ImageLoaderError.cannotDecodeImage
        }

        let dim = thumbnailMaxPixelInt(forDecodedDimension: maxPixelDimension)
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dim
        ] as [CFString: Any] as CFDictionary

        if let cg = CGImageSourceCreateThumbnailAtIndex(source, frameIndex, thumbOpts) {
            return cg
        }
        throw ImageLoaderError.cannotDecodeImage
    }

    nonisolated static func frameDelayFromFile(url: URL, frameIndex: Int) throws -> TimeInterval {
        let sourceOptions = [kCGImageSourceShouldCache: false] as NSDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ImageLoaderError.cannotCreateImageSource
        }
        guard frameIndex >= 0, frameIndex < CGImageSourceGetCount(source) else {
            throw ImageLoaderError.cannotDecodeImage
        }
        return copyDelay(from: source, frameIndex: frameIndex)
    }

    // MARK: - Internal helpers

    nonisolated static func thumbnailMaxPixelInt(forDecodedDimension px: CGFloat) -> Int {
        max(1, Int(sanitizeDecodeDimension(px)))
    }

    nonisolated private static func sanitizeDecodeDimension(_ px: CGFloat) -> CGFloat {
        min(max(px, 256), 4096)
    }

    nonisolated private static func evenlySpacedFrameIndices(total: Int, budget: Int) -> [Int] {
        guard total > 0 else { return [] }
        if total <= budget { return Array(0..<total) }
        var out: [Int] = []
        out.reserveCapacity(budget)
        out.append(0)
        let stride = max(1, (total - 1) / max(budget - 1, 1))
        var i = stride
        while i < total - 1, out.count < budget - 1 {
            out.append(i)
            i += stride
        }
        out.append(total - 1)
        var seen = Set(out)
        var fill = 1
        while out.count < budget, fill < total - 1 {
            if seen.insert(fill).inserted { out.append(fill) }
            fill += 1
        }
        return out.sorted()
    }

    nonisolated private static func logicalPixelDimensions(source: CGImageSource, frameIndex: Int) -> (width: CGFloat, height: CGFloat)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as? [NSString: Any] else { return nil }
        guard let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        guard w > 0, h > 0 else { return nil }
        return (w, h)
    }

    nonisolated static func copyDelay(from source: CGImageSource, frameIndex: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as? [AnyHashable: Any] else {
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
            return u < 0.02 ? 0.1 : u
        }
        if let c = double(from: props, key: kCGImagePropertyAPNGDelayTime as AnyHashable) {
            return c < 0.02 ? 0.1 : c
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

    nonisolated private static func normalizeDelaysIfNeeded(_ delays: inout [TimeInterval]) {
        guard !delays.isEmpty else { return }
        if delays.allSatisfy({ $0 <= 0 }) {
            delays = Array(repeating: 0.1, count: delays.count)
        }
    }

    nonisolated private static func double(from dict: [AnyHashable: Any], key: AnyHashable) -> Double? {
        if let d = dict[key] as? Double { return d }
        if let n = dict[key] as? NSNumber { return n.doubleValue }
        return nil
    }
}
