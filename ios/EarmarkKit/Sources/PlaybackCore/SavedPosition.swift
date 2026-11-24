import Foundation

/// A saved listening position and when the server last stamped it (milliseconds since 1970).
public struct SavedPosition: Sendable, Equatable {
    public let time: TimeInterval
    public let lastUpdate: Int64

    public init(time: TimeInterval, lastUpdate: Int64) {
        self.time = time
        self.lastUpdate = lastUpdate
    }

    /// The newest `lastUpdate` wins, so a phone that was offline never overwrites a later position from another
    /// device. A tie keeps the server's.
    public static func newest(local: SavedPosition?, server: SavedPosition?) -> SavedPosition? {
        switch (local, server) {
        case (nil, let server): return server
        case (let local, nil): return local
        case (let local?, let server?): return local.lastUpdate > server.lastUpdate ? local : server
        }
    }
}
