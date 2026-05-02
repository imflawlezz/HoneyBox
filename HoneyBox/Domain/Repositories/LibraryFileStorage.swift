import Foundation

protocol LibraryFileStorage: Sendable {
    var rootURL: URL { get }

    func readDataIfPresent(at url: URL) -> Data?
    func readData(at url: URL) throws -> Data
    func atomicWrite(_ data: Data, to destination: URL) throws
    func removeItem(at url: URL) throws
    func copyItem(from source: URL, to destination: URL) throws
    func moveItem(from source: URL, to destination: URL) throws
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) -> Int64?
    func createDirectory(at url: URL) throws
}
