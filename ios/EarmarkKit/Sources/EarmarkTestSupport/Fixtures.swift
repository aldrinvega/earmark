import Foundation

/// Loads files from `Fixtures/` (public-domain books, audio clips and recorded server responses; see its README).
public enum Fixtures {
    public enum Missing: Error, CustomStringConvertible {
        case file(String)
        public var description: String {
            switch self {
            case .file(let name): "No fixture named \(name) in EarmarkTestSupport/Fixtures"
            }
        }
    }

    public static func url(_ name: String) throws -> URL {
        // Ask the bundle for the copied folder: on macOS it sits in Contents/Resources, on iOS at the bundle root.
        guard let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else { throw Missing.file(name) }
        let url = folder.appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw Missing.file(name) }
        return url
    }

    public static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
}
