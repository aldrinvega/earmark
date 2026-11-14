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
        let url = Bundle.module.bundleURL.appending(path: "Fixtures").appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw Missing.file(name) }
        return url
    }

    public static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
}
