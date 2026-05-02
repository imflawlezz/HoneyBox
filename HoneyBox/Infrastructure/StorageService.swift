import Foundation

enum StorageServiceError: Error, LocalizedError {
    case noApplicationSupport
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noApplicationSupport: "Missing Application Support directory."
        case .writeFailed(let message): message
        }
    }
}

final class StorageService: @unchecked Sendable, LibraryFileStorage {
    nonisolated let rootURL: URL

    nonisolated init() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageServiceError.noApplicationSupport
        }
        rootURL = appSupport.standardizedFileURL
    }

    nonisolated func ensureLayoutExists() throws {
        try FileManager.default.createDirectory(at: StoragePaths.authorsDirectory(root: rootURL), withIntermediateDirectories: true)
        try applyFileProtectionIfNeeded(at: rootURL)
    }

    nonisolated private func applyFileProtectionIfNeeded(at url: URL) throws {
        try FileManager.default.setAttributes(
            [FileAttributeKey.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    nonisolated func readDataIfPresent(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    nonisolated func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    nonisolated func atomicWrite(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: false)
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp, backupItemName: nil, options: [])
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }

    nonisolated func removeItem(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated func copyItem(from source: URL, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    nonisolated func moveItem(from source: URL, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    nonisolated func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
    }

    nonisolated func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
