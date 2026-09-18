import XCTest
@testable import Cenit

/// FER-522 — pure spoken summary for «¿qué toca hoy?». Never exposes a numeric score.
final class TodaySpokenSummaryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testConRutinaYVeredicto() {
        let snap = TrainWidgetSnapshot(
            writtenAt: now,
            today: .init(routineName: "Empuje", sessionLive: false),
            verdict: .init(tone: .clear, word: "En rango", advice: "Sigue el plan."),
            week: [])
        let s = TodaySpokenSummary.from(snapshot: snap, now: now)
        XCTAssertEqual(s.state, .ready)
        XCTAssertEqual(s.routineName, "Empuje")
        XCTAssertEqual(s.word, "En rango")
        XCTAssertEqual(s.advice, "Sigue el plan.")
        XCTAssertTrue(s.spokenText.contains("Empuje"))
        XCTAssertTrue(s.spokenText.contains("En rango"))
    }

    func testDiaDeDescanso() {
        let snap = TrainWidgetSnapshot(
            writtenAt: now, today: nil,
            verdict: .init(tone: .clear, word: "Descansa", advice: nil),
            week: [])
        let s = TodaySpokenSummary.from(snapshot: snap, now: now)
        XCTAssertEqual(s.state, .restDay)
        XCTAssertNil(s.routineName)
    }

    func testSnapshotNilEsUnavailable() {
        let s = TodaySpokenSummary.from(snapshot: nil, now: now)
        XCTAssertEqual(s.state, .unavailable)
        XCTAssertNil(s.routineName)
        XCTAssertNil(s.word)
    }

    func testSnapshotStaleEsUnavailable() {
        let snap = TrainWidgetSnapshot(
            writtenAt: now.addingTimeInterval(-TrainWidgetSnapshot.staleAfter - 1),
            today: .init(routineName: "Empuje", sessionLive: false),
            verdict: .init(tone: .clear, word: "En rango"),
            week: [])
        let s = TodaySpokenSummary.from(snapshot: snap, now: now)
        XCTAssertEqual(s.state, .unavailable)
    }

    /// Structural invariant: the spoken summary type has no numeric score field to leak.
    func testNoExponePuntaje() {
        let mirror = Mirror(reflecting: TodaySpokenSummary(
            state: .ready, routineName: "X", word: "Y", advice: "Z"))
        let names = mirror.children.compactMap(\.label)
        XCTAssertEqual(Set(names), ["state", "routineName", "word", "advice"])
        XCTAssertFalse(names.contains(where: { $0.lowercased().contains("score") }))
        XCTAssertFalse(names.contains(where: { $0.lowercased().contains("load") }))
        XCTAssertFalse(names.contains(where: { $0.lowercased().contains("ratio") }))
    }
}
