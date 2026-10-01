import Foundation

/// What a dictation to neo-plan asks for (see neo-plan's docs/VOICE.md).
public enum NeoPlanCommand: Equatable, Sendable {
    /// "Chemistry quiz due Friday": a new item, parsed by neo-plan.
    case add(String)
    /// "Done with the titration lab": the work is finished.
    case done(String)
    /// "Turned in the titration lab": handed in, so it leaves the board.
    case turnIn(String)

    private static let turnInVerbs = ["turned in", "turn in", "handed in", "hand in", "submitted", "submit"]
    private static let doneVerbs = ["done with", "finished with", "finished", "finish", "completed", "complete"]
    /// Said before the verb and meaning nothing: "I just turned in…".
    private static let leadIns = ["i've", "i have", "i'm", "im", "i am", "i", "just", "ok", "okay", "so", "and"]

    /// nil when the feature that would handle it is off.
    public static func parse(_ text: String, allowAdd: Bool, allowMark: Bool) -> NeoPlanCommand? {
        let spoken = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !spoken.isEmpty else { return nil }

        if allowMark {
            var rest = spoken.lowercased()
            var stripped = true
            while stripped {
                stripped = false
                for lead in leadIns where rest.hasPrefix(lead + " ") || rest.hasPrefix(lead + ",") {
                    rest = String(rest.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                    stripped = true
                    break
                }
            }
            // Keep the original capitals of the name: "Problem Set 4", not "problem set 4".
            let offset = spoken.count - rest.count
            func name(after verb: String) -> String? {
                let original = String(spoken.dropFirst(offset + verb.count))
                let cleaned = original.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                return cleaned.isEmpty ? nil : cleaned
            }
            for verb in turnInVerbs where rest.hasPrefix(verb + " ") {
                return name(after: verb).map(NeoPlanCommand.turnIn)
            }
            for verb in doneVerbs where rest.hasPrefix(verb + " ") {
                return name(after: verb).map(NeoPlanCommand.done)
            }
        }
        return allowAdd ? .add(spoken) : nil
    }
}

/// An item as neo-plan's extension routes answer with it (the panel shape).
public struct NeoPlanItem: Decodable, Equatable, Sendable {
    public struct Column: Decodable, Equatable, Sendable {
        public var name: String
    }
    public struct Due: Decodable, Equatable, Sendable {
        /// "YYYY-MM-DD" in the user's zone, or nil when undated.
        public var on: String?
    }

    public var id: String
    public var title: String
    public var type: String
    public var work: String
    public var cleared: Bool
    public var due: Due
    public var `class`: Column?

    public init(id: String, title: String, type: String, work: String, cleared: Bool, due: Due, class column: Column?) {
        self.id = id
        self.title = title
        self.type = type
        self.work = work
        self.cleared = cleared
        self.due = due
        self.class = column
    }

    /// "Chemistry · Fri" for the pill: the column, and the day if it has one.
    public func summary(now: Date = Date(), calendar: Calendar = .current) -> String {
        [self.class?.name, Self.day(due.on, now: now, calendar: calendar)].compactMap { $0 }.joined(separator: " · ")
    }

    static func day(_ on: String?, now: Date, calendar: Calendar) -> String? {
        guard let on else { return nil }
        let parts = on.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0
        let format = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2..<7: return date.formatted(format.weekday(.abbreviated))
        default: return date.formatted(format.month(.abbreviated).day())
        }
    }
}

public enum NeoPlanError: LocalizedError, Equatable {
    case notConnected
    case badToken
    /// The line named no class or list.
    case noColumn
    /// Nothing open matched what was said, or two things matched equally.
    case noMatch(String, ambiguous: Bool)
    case server(Int)
    case offline

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Connect neo-plan in Settings"
        case .badToken: "neo-plan token was revoked"
        case .noColumn: "Say which class it's for"
        case .noMatch(let name, ambiguous: true): "More than one “\(name)”"
        case .noMatch(let name, ambiguous: false): "No open “\(name)”"
        case .server(let code): "neo-plan error \(code)"
        case .offline: "Can't reach neo-plan"
        }
    }
}

/// Chordy's side of neo-plan's extension routes, on an extension token.
public struct NeoPlanClient: Sendable {
    public static let defaultURL = URL(string: "https://neo-plan.vercel.app")!

    public var baseURL: URL
    public var token: String
    var session: URLSession

    public init(baseURL: URL = defaultURL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public enum Purpose: String, Sendable { case done, turnIn = "turn_in" }

    struct Match: Decodable {
        var best: NeoPlanItem?
        var candidates: [NeoPlanItem]
    }

    /// Sends a dictated line to the capture box's parser.
    public func capture(_ text: String) async throws -> NeoPlanItem {
        try await send("POST", "capture", body: ["text": text])
    }

    /// The open item a spoken name means.
    public func match(_ name: String, for purpose: Purpose) async throws -> NeoPlanItem {
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "for", value: purpose.rawValue)]
        let match: Match = try await send("GET", "match?" + (parts.percentEncodedQuery ?? ""))
        guard let best = match.best else { throw NeoPlanError.noMatch(name, ambiguous: match.candidates.count > 1) }
        return best
    }

    @discardableResult
    public func setWork(_ id: String, done: Bool) async throws -> NeoPlanItem {
        try await send("POST", "items/\(id)/work", body: ["work": done ? "ready" : "todo"])
    }

    @discardableResult
    public func turnIn(_ id: String) async throws -> NeoPlanItem {
        try await send("POST", "items/\(id)/turn-in")
    }

    @discardableResult
    public func putBack(_ id: String) async throws -> NeoPlanItem {
        try await send("POST", "items/\(id)/put-back")
    }

    @discardableResult
    public func remove(_ id: String) async throws -> NeoPlanItem {
        try await send("POST", "items/\(id)/remove")
    }

    /// A cheap authenticated read, for Settings' Test button.
    public func check() async throws {
        let request = request("GET", "today")
        let (_, response) = try await load(request)
        try Self.check(response, data: Data())
    }

    func request(_ method: String, _ path: String, body: [String: String]? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "api/extension/" + path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> T {
        let (data, response) = try await load(request(method, path, body: body))
        try Self.check(response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NeoPlanError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw NeoPlanError.offline
        }
    }

    static func check(_ response: URLResponse, data: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return
        case 401: throw NeoPlanError.badToken
        case 422: throw NeoPlanError.noColumn
        default: throw NeoPlanError.server(code)
        }
    }
}
