import XCTest
@testable import BiometricStreams

/// FER-382 — `ParsedValue` is the box every mixed-type payload travels in, and its wire shape
/// is a bare JSON scalar. These pin the two things that would break silently: the ORDER the
/// decoder tries types in, and the fact that encoding adds no wrapper (the stored JSON is a
/// dedupe key, so it has to stay byte-stable).
final class ParsedValueTests: XCTestCase {

    // MARK: - Accessors

    func testEachAccessorOnlyAnswersForItsOwnCase() {
        XCTAssertEqual(ParsedValue.int(60).intValue, 60)
        XCTAssertEqual(ParsedValue.double(25.5).doubleValue, 25.5)
        XCTAssertEqual(ParsedValue.string("hi").stringValue, "hi")
        XCTAssertEqual(ParsedValue.intArray([1, 2, 3]).intArrayValue, [1, 2, 3])

        XCTAssertNil(ParsedValue.string("x").intValue)
        XCTAssertNil(ParsedValue.int(1).stringValue)
        XCTAssertNil(ParsedValue.bool(true).intValue)
        XCTAssertNil(ParsedValue.null.stringValue)
        XCTAssertNil(ParsedValue.int(1).intArrayValue)
    }

    /// The one deliberate widening: an integer reads as a double, so a payload that arrived
    /// as `60` and one that arrived as `60.0` are the same number to the math side.
    func testIntegersReadAsDoubles() {
        XCTAssertEqual(ParsedValue.int(3).doubleValue, 3.0)
        XCTAssertEqual(ParsedValue.int(-7).doubleValue, -7.0)
        XCTAssertNil(ParsedValue.string("3").doubleValue)
    }

    // MARK: - Decoding

    func testDecodesAMixedPayloadDictionary() throws {
        let json = """
        {"heart_rate": 60, "battery_pct": 25.5, "log": "hello",
         "rr_intervals": [800, 810], "flag": true, "nothing": null}
        """
        let payload = try JSONDecoder().decode([String: ParsedValue].self,
                                               from: Data(json.utf8))

        XCTAssertEqual(payload["heart_rate"], .int(60))
        XCTAssertEqual(payload["battery_pct"], .double(25.5))
        XCTAssertEqual(payload["log"], .string("hello"))
        XCTAssertEqual(payload["rr_intervals"], .intArray([800, 810]))
        XCTAssertEqual(payload["nothing"], .null)
    }

    /// Booleans are tried before integers on purpose: `JSONDecoder` reads `true` as `1` if
    /// asked for an `Int` first, which would turn every flag in the payload into a number.
    func testBooleanDoesNotDecodeAsAnInteger() throws {
        let payload = try JSONDecoder().decode([String: ParsedValue].self,
                                               from: Data(#"{"flag": true, "off": false}"#.utf8))
        XCTAssertEqual(payload["flag"], .bool(true))
        XCTAssertEqual(payload["off"], .bool(false))
    }

    func testEmptyArrayDecodesAsAnEmptyIntArray() throws {
        let payload = try JSONDecoder().decode([String: ParsedValue].self,
                                               from: Data(#"{"rr_intervals": []}"#.utf8))
        XCTAssertEqual(payload["rr_intervals"], .intArray([]))
    }

    func testUnsupportedShapeThrows() {
        let json = #"{"nested": {"a": 1}}"#
        XCTAssertThrowsError(try JSONDecoder().decode([String: ParsedValue].self,
                                                      from: Data(json.utf8)))
    }

    // MARK: - Encoding

    func testEncodesTheBareScalar() throws {
        XCTAssertEqual(try encoded(.int(7)), "7")
        XCTAssertEqual(try encoded(.intArray([1, 2])), "[1,2]")
        XCTAssertEqual(try encoded(.string("hi")), "\"hi\"")
        XCTAssertEqual(try encoded(.bool(true)), "true")
        XCTAssertEqual(try encoded(.null), "null")
    }

    /// The stored payload is a dedupe key, so a round trip has to come back identical.
    func testRoundTripsThroughSortedJSON() throws {
        let payload: [String: ParsedValue] = [
            "heart_rate": .int(60), "battery_pct": .double(25.5), "log": .string("ok"),
            "rr_intervals": .intArray([800, 810]), "flag": .bool(false), "nothing": .null,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let again = try JSONDecoder().decode([String: ParsedValue].self, from: data)

        XCTAssertEqual(again, payload)
        XCTAssertEqual(try encoder.encode(again), data)
    }

    private func encoded(_ value: ParsedValue) throws -> String {
        // A bare scalar is not a legal JSON *document*, so it travels inside an array and
        // the brackets come back off.
        let data = try JSONEncoder().encode([value])
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }
}
