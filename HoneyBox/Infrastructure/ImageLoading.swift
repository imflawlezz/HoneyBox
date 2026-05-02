import CoreGraphics
import Foundation
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
    func generateThumbnailJPEG(fromImageAt source: URL, to destination: URL, maxPixel: CGFloat, quality: CGFloat) throws

    static func supportsAnimatedPlaybackExtension(_ ext: String) -> Bool
}

extension ImageLoading {
    func loadAnimatedRaster(ref: ImageRef) async throws -> AnimatedGIF? {
        try await loadAnimatedRaster(ref: ref, maxFrames: 30_000)
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
