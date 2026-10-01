@testable import ChordyCore
import Foundation
import Testing

@Suite struct NeoPlanCommandTests {
    func parse(_ text: String, add: Bool = true, mark: Bool = true) -> NeoPlanCommand? {
        NeoPlanCommand.parse(text, allowAdd: add, allowMark: mark)
    }

    @Test func plainLinesAreNewItems() {
        #expect(parse("Chemistry quiz due Friday.") == .add("Chemistry quiz due Friday"))
    }

    @Test func turnedInAndDoneAreCommands() {
        #expect(parse("Turned in the titration lab.") == .turnIn("the titration lab"))
        #expect(parse("I just submitted Problem Set 4") == .turnIn("Problem Set 4"))
        #expect(parse("I’m done with the history reading") == .done("the history reading"))
        #expect(parse("Okay, finished problem set 3.") == .done("problem set 3"))
    }

    @Test func aVerbWithNothingAfterItIsNotACommand() {
        #expect(parse("Turned in.") == .add("Turned in"))
    }

    @Test func eachSwitchTurnsOffItsOwnHalf() {
        #expect(parse("Turned in the lab", mark: false) == .add("Turned in the lab"))
        #expect(parse("Chemistry quiz Friday", add: false) == nil)
        #expect(parse("Turned in the lab", add: false) == .turnIn("the lab"))
        #expect(parse("anything", add: false, mark: false) == nil)
    }

    @Test func wordsThatOnlyStartLikeAVerbAreTitles() {
        #expect(parse("Completely redo the essay") == .add("Completely redo the essay"))
        #expect(parse("Ice cream for the club") == .add("Ice cream for the club"))
    }
}

@Suite struct NeoPlanItemTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US")
        return c
    }
    // Thu 1 Oct 2026, noon Pacific.
    let now = Date(timeIntervalSince1970: 1_790_881_200)

    func item(_ on: String?, column: String? = "AP Chemistry") -> NeoPlanItem {
        NeoPlanItem(
            id: "1", title: "Quiz", type: "exam", work: "todo", cleared: false,
            due: .init(on: on), class: column.map { .init(name: $0) }
        )
    }

    @Test func summarySaysTheColumnAndTheDay() {
        #expect(item("2026-10-01").summary(now: now, calendar: calendar) == "AP Chemistry · Today")
        #expect(item("2026-10-02").summary(now: now, calendar: calendar) == "AP Chemistry · Tomorrow")
        #expect(item("2026-10-05").summary(now: now, calendar: calendar) == "AP Chemistry · Mon")
        #expect(item("2026-10-20").summary(now: now, calendar: calendar) == "AP Chemistry · Oct 20")
        #expect(item(nil).summary(now: now, calendar: calendar) == "AP Chemistry")
    }

    @Test func decodesThePanelShape() throws {
        let json = """
        {"id":"a","title":"Lab","type":"assignment","work":"ready","cleared":false,
         "due":{"at":null,"on":"2026-10-02","mode":"none"},"starts_at":null,
         "class":{"id":"c","name":"Chem","short_code":"chem","colour_index":1,"kind":"class"},
         "source_url":null,"source_id":null,"can_turn_in":true,"cleared_by":null,"missing":false,"removed":false}
        """
        let item = try JSONDecoder().decode(NeoPlanItem.self, from: Data(json.utf8))
        #expect(item.class?.name == "Chem")
        #expect(item.due.on == "2026-10-02")
    }
}

@Suite struct NeoPlanClientTests {
    let client = NeoPlanClient(baseURL: URL(string: "https://example.test")!, token: "np_x")

    @Test func requestsCarryTheTokenAndJSON() throws {
        let request = client.request("POST", "items/abc/work", body: ["work": "ready"])
        #expect(request.url?.absoluteString == "https://example.test/api/extension/items/abc/work")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer np_x")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
        #expect(body == ["work": "ready"])
    }

    @Test func statusCodesBecomeErrors() {
        func status(_ code: Int) -> URLResponse {
            HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: code, httpVersion: nil, headerFields: nil)!
        }
        #expect(throws: NeoPlanError.badToken) { try NeoPlanClient.check(status(401), data: Data()) }
        #expect(throws: NeoPlanError.noColumn) { try NeoPlanClient.check(status(422), data: Data()) }
        #expect(throws: Never.self) { try NeoPlanClient.check(status(201), data: Data()) }
    }
}
