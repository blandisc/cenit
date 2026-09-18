import XCTest
@testable import Cenit

/// FER-522 — StartRoutineBridge additive routineId; old Bool-only writers drain as `.today`.
final class StartRoutineBridgeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = StartRoutineBridge.drain()   // clear any leftover from a prior test
    }

    func testRequestSinIdDrenaComoToday() {
        StartRoutineBridge.request()
        XCTAssertEqual(StartRoutineBridge.drain(), .today)
        XCTAssertNil(StartRoutineBridge.drain())
    }

    func testRequestConIdDrenaComoNamed() {
        StartRoutineBridge.request(routineId: "push")
        XCTAssertEqual(StartRoutineBridge.drain(), .named("push"))
        XCTAssertNil(StartRoutineBridge.drain())
    }

    func testDrainSinRequestEsNil() {
        XCTAssertNil(StartRoutineBridge.drain())
    }
}
