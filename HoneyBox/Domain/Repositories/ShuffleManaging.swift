import Foundation

protocol ShuffleManaging: Actor {
    func reset() async throws
    func current() -> ImageRef?
    func advance() async throws -> ImageRef?
    func preloadAroundCurrent() async
    func preloadAroundCurrent(ahead: Int, behind: Int) async
    func positionLabel() -> String
}
