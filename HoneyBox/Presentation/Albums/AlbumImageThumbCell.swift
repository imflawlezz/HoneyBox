import SwiftUI

struct AlbumImageThumbCell: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let albumId: String
    let fileName: String
    var decodeMaxEdge: CGFloat = 420
    @Environment(\.displayScale) private var displayScale
    @State private var cg: CGImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let cg {
                Image(decorative: cg, scale: displayScale, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: fileName) {
            let ref = ImageRef(authorId: authorId, albumId: albumId, fileName: fileName)
            cg = try? await env.images.loadThumbnailCGImage(
                authorId: authorId,
                albumId: albumId,
                thumbFileName: ref.thumbnailFileName,
                decodeMaxEdge: decodeMaxEdge
            )
        }
    }
}
