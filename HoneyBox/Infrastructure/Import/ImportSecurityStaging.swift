import Foundation

enum ImportSecurityStaging {
    static let stagingFolderName = "HoneyBoxImportStaging"

    static func isStagedFile(_ url: URL) -> Bool {
        url.path.contains("/\(stagingFolderName)/")
    }

    static func stageFilesForImport(_ urls: [URL]) async throws -> (files: [URL], sessionDirectory: URL) {
        let session = UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(stagingFolderName, isDirectory: true)
            .appendingPathComponent(session, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ordered = try await copyPreservingOrder(urls: urls, destinationRoot: root)
        return (ordered, root)
    }

    static func removeSessionDirectory(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private static func copyPreservingOrder(urls: [URL], destinationRoot: URL) async throws -> [URL] {
        let concurrency = 6
        var ordered: [URL] = []
        ordered.reserveCapacity(urls.count)
        var start = 0
        while start < urls.count {
            let end = min(start + concurrency, urls.count)
            let batch = try await withThrowingTaskGroup(of: (Int, URL).self) { group in
                for i in start..<end {
                    let url = urls[i]
                    group.addTask {
                        let slotDir = destinationRoot.appendingPathComponent(String(format: "%06d", i), isDirectory: true)
                        try FileManager.default.createDirectory(at: slotDir, withIntermediateDirectories: true)
                        let originalName = url.lastPathComponent
                        let dest = slotDir.appendingPathComponent(originalName, isDirectory: false)
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.copyItem(at: url, to: dest)
                        return (i, dest)
                    }
                }
                var map: [Int: URL] = [:]
                for try await pair in group {
                    map[pair.0] = pair.1
                }
                return (start..<end).map { map[$0]! }
            }
            ordered.append(contentsOf: batch)
            start = end
        }
        return ordered
    }
}
