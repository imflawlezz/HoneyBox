import Foundation

enum ZipLibraryError: Error, LocalizedError {
    case invalidArchive
    case missingIndex

    var errorDescription: String? {
        switch self {
        case .invalidArchive: "The selected file is not a valid HoneyBox backup."
        case .missingIndex: "Backup is missing index.json."
        }
    }
}

enum ZipRestorePhase: String, Sendable {
    case extracting
    case installing
    case finalizing
}

protocol ZipLibraryManaging: Sendable {
    func exportLibrary(
        to zipURL: URL,
        onProgress: (@MainActor (_ completed: Int, _ total: Int, _ currentPath: String) -> Void)?
    ) async throws

    func restoreLibrary(
        from zipURL: URL,
        indexService: any LibraryIndexing,
        onProgress: (@MainActor (ZipRestorePhase, Int, Int, String) -> Void)?
    ) async throws
}
