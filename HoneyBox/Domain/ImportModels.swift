import Foundation

struct ImportReport: Sendable {
    var importedImages: Int
    var skippedInvalidNames: Int
    var skippedDuplicates: Int
    var albumsTouched: Set<String>
    var messages: [String]
}

enum ImportProgressPhase: String, Sendable {
    case copying
    case thumbnails
}

enum ImportGalleryError: Error, LocalizedError {
    case emptyTitle
    case noImages

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a gallery name."
        case .noImages: "No images to import."
        }
    }
}

protocol LibraryImporting: Sendable {
    func importFiles(
        authorId: String,
        fileURLs: [URL],
        onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)?
    ) async throws -> ImportReport

    func importNewGallery(
        authorId: String,
        displayTitle: String,
        fileURLs: [URL],
        onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)?
    ) async throws -> ImportReport

    func appendLooseImages(
        authorId: String,
        albumId: String,
        fileURLs: [URL]
    ) async throws -> ImportReport
}
