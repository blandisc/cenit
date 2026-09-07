import XCTest
@testable import CenitStore

/// Las marcas con nombre. Los prefijos son contrato observable: la marca de subida y la de lectura
/// del mismo flujo tienen que vivir bajo nombres distintos o se pisarían.
final class MarkStoreTests: XCTestCase {

    func testAnUnwrittenMarkIsNil() async throws {
        let store = try await CenitStore.inMemory()
        let mark = try await store.cursor("compact_v1")
        XCTAssertNil(mark)
    }

    func testAMarkRoundTrips() async throws {
        let store = try await CenitStore.inMemory()
        try await store.setCursor("compact_v1", 12345)
        let mark = try await store.cursor("compact_v1")
        XCTAssertEqual(mark, 12345)
    }

    func testWritingTheSameNameTwiceKeepsTheLastValue() async throws {
        let store = try await CenitStore.inMemory()
        try await store.setCursor("compact_v1", 1)
        try await store.setCursor("compact_v1", 2)
        let mark = try await store.cursor("compact_v1")
        XCTAssertEqual(mark, 2, "es un upsert por nombre, no una fila nueva")
    }

    func testTheUploadMarkLivesUnderItsPrefix() async throws {
        let store = try await CenitStore.inMemory()
        try await store.setHighwater("hr", 1_716_400_000)
        let byAccessor = try await store.highwater("hr")
        let byRawName = try await store.cursor("highwater:hr")
        XCTAssertEqual(byAccessor, 1_716_400_000)
        XCTAssertEqual(byRawName, 1_716_400_000, "el prefijo es contrato, no un detalle interno")
    }

    /// El punto de los prefijos: la marca de subida no se lee como marca de lectura.
    func testTheTwoMarksOfOneStreamDoNotCollide() async throws {
        let store = try await CenitStore.inMemory()
        try await store.setHighwater("hr", 1_716_400_000)
        let read = try await store.readHighwater("hr")
        XCTAssertNil(read)
    }

    func testTheReadMarkLivesUnderItsOwnPrefix() async throws {
        let store = try await CenitStore.inMemory()
        try await store.setReadHighwater("hr", 777)
        let byRawName = try await store.cursor("read:hr")
        XCTAssertEqual(byRawName, 777)
    }

    func testTwoStreamsKeepSeparateMarks() async throws {
        let store = try await CenitStore.inMemory()
        try await store.setHighwater("hr", 100)
        try await store.setHighwater("rr", 200)
        let hr = try await store.highwater("hr")
        let rr = try await store.highwater("rr")
        XCTAssertEqual(hr, 100)
        XCTAssertEqual(rr, 200)
    }
}
