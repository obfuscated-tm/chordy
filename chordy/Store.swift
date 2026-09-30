import ChordyCore
import Foundation

/// Text-only record of one dictation. Audio is never kept.
struct HistoryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var raw: String
    var text: String
    var mode: String
    var app: String?
    /// Which models produced it. Optional so older history still loads.
    var speechModel: String?
    var cleanupModel: String?

    var preview: String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 60 ? flat.prefix(60) + "…" : flat
    }
}

enum HistoryRetention: Int, CaseIterable, Identifiable {
    case never = 0, day = 1, week = 7, month = 30, forever = -1

    var id: Self { self }
    var label: String {
        switch self {
        case .never: "Don't save"
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .forever: "Forever"
        }
    }
}

/// JSON files in ~/Library/Application Support/Chordy.
enum Store {
    static let directory: URL = {
        let url = URL.applicationSupportDirectory.appending(path: "Chordy", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? JSONDecoder.chordy.decode(type, from: data)
    }

    static func save(_ value: some Encodable, to name: String) {
        guard let data = try? JSONEncoder.chordy.encode(value) else { return }
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
}

private extension JSONEncoder {
    static let chordy: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let chordy: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
