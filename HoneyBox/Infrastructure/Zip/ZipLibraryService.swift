import Foundation
import ZIPFoundation

private struct ZipFileEntry: Sendable {
    var url: URL
    var relativePath: String
}

final class ZipLibraryService: Sendable, ZipLibraryManaging {
    private let storage: StorageService

    init(storage: StorageService) {
        self.storage = storage
    }

    func exportLibrary(
        to zipURL: URL,
        onProgress: (@MainActor (_ completed: Int, _ total: Int, _ currentPath: String) -> Void)? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .create)
        } catch {
            throw ZipLibraryError.invalidArchive
        }
        let root = storage.rootURL
        let files = try collectFiles(directory: root, relativePrefix: "")
        let total = max(1, files.count)
        await MainActor.run { onProgress?(0, total, "") }

        for (i, entry) in files.enumerated() {
            try archive.addEntry(with: entry.relativePath, fileURL: entry.url, compressionMethod: .deflate)
            let done = i + 1
            let label = entry.relativePath
            await MainActor.run { onProgress?(done, total, label) }
        }
    }

    private func collectFiles(directory: URL, relativePrefix: String) throws -> [ZipFileEntry] {
        let fm = FileManager.default
        var out: [ZipFileEntry] = []
        let children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for url in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            let rel = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                try out.append(contentsOf: collectFiles(directory: url, relativePrefix: rel))
            } else {
                out.append(ZipFileEntry(url: url, relativePath: rel))
            }
        }
        return out
    }

    func restoreLibrary(
        from zipURL: URL,
        indexService: any LibraryIndexing,
        onProgress: (@MainActor (ZipRestorePhase, Int, Int, String) -> Void)? = nil
    ) async throws {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ZipLibraryError.invalidArchive
        }

        let entries = Array(archive)
        let extractTotal = max(1, entries.count)
        await MainActor.run { onProgress?(.extracting, 0, extractTotal, "Reading archive…") }

        let temp = storage.rootURL.deletingLastPathComponent()
            .appendingPathComponent("HoneyBoxRestore_\(UUID().uuidString)", isDirectory: true)
        try storage.createDirectory(at: temp)

        for (i, entry) in entries.enumerated() {
            let dest = temp.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try storage.createDirectory(at: dest)
            } else {
                try storage.createDirectory(at: dest.deletingLastPathComponent())
                _ = try archive.extract(entry, to: dest)
            }
            await MainActor.run { onProgress?(.extracting, i + 1, extractTotal, entry.path) }
        }

        let idx = temp.appendingPathComponent(StoragePaths.indexFileName)
        guard FileManager.default.fileExists(atPath: idx.path) else {
            try? storage.removeItem(at: temp)
            throw ZipLibraryError.missingIndex
        }
        let authors = temp.appendingPathComponent(StoragePaths.authorsFolderName)
        guard FileManager.default.fileExists(atPath: authors.path) else {
            try? storage.removeItem(at: temp)
            throw ZipLibraryError.invalidArchive
        }

        let root = storage.rootURL
        let fm = FileManager.default
        let movedItems = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil).sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        let n = movedItems.count
        let installTotal = max(1, n + 1)

        await MainActor.run { onProgress?(.installing, 0, installTotal, "Removing existing library…") }
        try clearStorageRootKeepingParent(root)

        for (i, url) in movedItems.enumerated() {
            let dest = root.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: url, to: dest)
            await MainActor.run {
                onProgress?(.installing, i + 1, installTotal, url.lastPathComponent)
            }
        }
        try? storage.removeItem(at: temp)

        await MainActor.run { onProgress?(.finalizing, 0, 1, "Reloading index…") }
        try await indexService.reloadFromDisk()
        await MainActor.run { onProgress?(.finalizing, 1, 1, "Done") }
    }

    private func clearStorageRootKeepingParent(_ root: URL) throws {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for url in children {
            try fm.removeItem(at: url)
        }
    }
}
