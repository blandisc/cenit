import Foundation

// MARK: - Civil-time arithmetic (FER-382)
//
// The two conversions on the hot path of an Apple Health import: text → instant, and
// instant → civil day. A fifteen-year export carries tens of millions of records and each
// one goes through both, so they are integer arithmetic and nothing else — no `Calendar`,
// no `TimeZone`, no `DateFormatter`, no `String(format:)`, and no heap allocation per
// record (the scratch buffers below live on the stack).
//
// The day ⇄ (year, month, day) pair is Howard Hinnant's `days_from_civil` /
// `civil_from_days` (howardhinnant.github.io/date_algorithms.html, public domain): the
// proleptic Gregorian calendar, valid far outside any range Apple Health can produce.

enum CivilTime {

    static let secondsPerDay = 86_400

    // MARK: Days ⇄ calendar

    /// Days since 1970-01-01 for a proleptic Gregorian date. Does not validate the date:
    /// a day number past the end of the month rolls forward, which is what lets the fast
    /// text parser skip calendar validation on the hot path.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                                        // [0, 399]
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The proleptic Gregorian date of a day number counted from 1970-01-01.
    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097                                     // [0, 146096]
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153                           // [0, 11], March-based
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex + (monthIndex < 10 ? 3 : -9)
        return (year + (month <= 2 ? 1 : 0), month, day)
    }

    /// Floor division — `-1 / 86400` must be day `-1`, not day `0`, or every instant before
    /// the epoch lands one day late.
    static func floorDiv(_ numerator: Int, _ denominator: Int) -> Int {
        let quotient = numerator / denominator
        return (numerator % denominator < 0) ? quotient - 1 : quotient
    }

    // MARK: Formatting

    /// `yyyy-MM-dd` for a day number. Ten ASCII bytes written into stack scratch, so the
    /// result fits Swift's inline string representation: no heap traffic per record.
    static func dayString(_ days: Int) -> String {
        let (year, month, day) = civilFromDays(days)
        // Years before year 1 have no `yyyy-MM-dd` spelling; they cannot occur in a health
        // export, so they collapse to `0000` rather than growing a sign.
        let safeYear = year < 0 ? 0 : year

        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 20) { scratch in
            var end = 0
            if safeYear < 10_000 {
                scratch[0] = asciiDigit(safeYear / 1000)
                scratch[1] = asciiDigit((safeYear / 100) % 10)
                scratch[2] = asciiDigit((safeYear / 10) % 10)
                scratch[3] = asciiDigit(safeYear % 10)
                end = 4
            } else {
                var magnitude = 1
                while safeYear / magnitude >= 10 { magnitude *= 10 }
                while magnitude > 0 {
                    scratch[end] = asciiDigit((safeYear / magnitude) % 10)
                    end += 1
                    magnitude /= 10
                }
            }
            scratch[end] = UInt8(ascii: "-"); end += 1
            scratch[end] = asciiDigit(month / 10); end += 1
            scratch[end] = asciiDigit(month % 10); end += 1
            scratch[end] = UInt8(ascii: "-"); end += 1
            scratch[end] = asciiDigit(day / 10); end += 1
            scratch[end] = asciiDigit(day % 10); end += 1
            return String(decoding: UnsafeBufferPointer(rebasing: scratch[0..<end]), as: UTF8.self)
        }
    }

    private static func asciiDigit(_ value: Int) -> UInt8 {
        UInt8(ascii: "0") &+ UInt8(value)
    }
}

// MARK: - Timestamp parsing

/// Turns the timestamps of an Apple Health export into `(instant in UTC, offset in minutes)`.
///
/// Apple's canonical spelling is fixed width — `yyyy-MM-dd HH:mm:ss ±HHMM` — so the common
/// case is decided by looking at a couple of dozen bytes and doing arithmetic. Anything that
/// does not match that shape exactly falls back to Foundation, which is orders of magnitude
/// slower but runs on a vanishing fraction of the records.
struct HealthTimestampReader {

    struct Instant {
        let utc: Date
        let offsetMinutes: Int
    }

    /// Longest text the fast path will even look at. A legal timestamp is 19–25 bytes.
    private static let scratchCapacity = 32

    // Foundation fallbacks. Built once per import, never per record.
    private let wallClockFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        wallClockFormatter = formatter

        let internetDates = ISO8601DateFormatter()
        internetDates.formatOptions = [ISO8601DateFormatter.Options.withInternetDateTime]
        isoFormatter = internetDates
    }

    /// Parses a timestamp, fast path first. `nil` when neither path recognises the text —
    /// the caller then drops the whole element.
    func parse(_ text: String) -> Instant? {
        if let quick = Self.parseFixedWidth(text) { return quick }
        return parseTolerant(text)
    }

    // MARK: Fast path

    /// Recognises `yyyy-MM-dd HH:mm:ss` optionally followed by a zone token (`Z`, `±HH`,
    /// `±HHMM`, `±HH:MM`), with at most one space before it. Returns `nil` — never a wrong
    /// answer — for anything else, including a wrongly punctuated or out-of-range field.
    ///
    /// Seconds are allowed up to 61 so a leap second does not throw a record away. The
    /// calendar itself is NOT validated: `2024-02-31` normalises into March instead of being
    /// rejected. Apple never emits an impossible date, and checking one costs cycles on
    /// every record of a multi-gigabyte file.
    static func parseFixedWidth(_ text: String) -> Instant? {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: scratchCapacity) { scratch -> Instant? in
            var count = 0
            for byte in text.utf8 {
                if count == scratchCapacity { return nil }
                scratch[count] = byte
                count += 1
            }
            return decodeFixedWidth(scratch, count)
        }
    }

    private static func decodeFixedWidth(_ bytes: UnsafeMutableBufferPointer<UInt8>,
                                         _ count: Int) -> Instant? {
        guard count >= 19 else { return nil }
        guard bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              bytes[10] == UInt8(ascii: " "),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":")
        else { return nil }

        guard let year = number(bytes, count, 0, 4),
              let month = number(bytes, count, 5, 2), month >= 1, month <= 12,
              let day = number(bytes, count, 8, 2), day >= 1, day <= 31,
              let hour = number(bytes, count, 11, 2), hour < 24,
              let minute = number(bytes, count, 14, 2), minute < 60,
              let second = number(bytes, count, 17, 2), second < 62
        else { return nil }

        var index = 19
        if index < count, bytes[index] == UInt8(ascii: " ") { index += 1 }

        var offsetMinutes = 0
        if index < count {
            let token = bytes[index]
            if token == UInt8(ascii: "Z") || token == UInt8(ascii: "z") {
                guard index + 1 == count else { return nil }
            } else if token == UInt8(ascii: "+") || token == UInt8(ascii: "-") {
                let sign = token == UInt8(ascii: "-") ? -1 : 1
                index += 1
                guard let offsetHours = number(bytes, count, index, 2) else { return nil }
                index += 2
                if index < count, bytes[index] == UInt8(ascii: ":") { index += 1 }
                var offsetMins = 0
                if index < count {
                    guard let tail = number(bytes, count, index, 2) else { return nil }
                    offsetMins = tail
                    index += 2
                }
                guard index == count else { return nil }
                offsetMinutes = sign * (offsetHours * 60 + offsetMins)
            } else {
                return nil
            }
        }

        let civilSeconds = CivilTime.daysFromCivil(year: year, month: month, day: day)
            * CivilTime.secondsPerDay + hour * 3600 + minute * 60 + second
        let utcSeconds = civilSeconds - offsetMinutes * 60
        return Instant(utc: Date(timeIntervalSince1970: TimeInterval(utcSeconds)),
                       offsetMinutes: offsetMinutes)
    }

    /// `width` ASCII digits starting at `start`, or `nil` if any of them is not a digit.
    private static func number(_ bytes: UnsafeMutableBufferPointer<UInt8>, _ count: Int,
                               _ start: Int, _ width: Int) -> Int? {
        guard start >= 0, start + width <= count else { return nil }
        var value = 0
        for offset in 0..<width {
            let byte = bytes[start + offset]
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    // MARK: Tolerant path

    private func parseTolerant(_ text: String) -> Instant? {
        if let date = wallClockFormatter.date(from: text) {
            return Instant(utc: date, offsetMinutes: Self.trailingOffsetMinutes(text))
        }
        if let date = isoFormatter.date(from: text) {
            return Instant(utc: date, offsetMinutes: Self.trailingOffsetMinutes(text))
        }
        return nil
    }

    /// Recovers the declared offset from a timestamp Foundation accepted. Only the tail of
    /// the string can hold a zone token, so the search is confined to the last six
    /// characters — otherwise the `-` of `2024-06-01` would be mistaken for a sign.
    static func trailingOffsetMinutes(_ text: String) -> Int {
        let compact = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let last = compact.last else { return 0 }
        if last == "Z" || last == "z" { return 0 }

        let tail = compact.suffix(6)
        guard let signIndex = tail.firstIndex(where: { $0 == "+" || $0 == "-" }) else { return 0 }
        let sign = tail[signIndex] == "-" ? -1 : 1

        var digits: [Int] = []
        for character in tail[tail.index(after: signIndex)...] {
            if let digit = character.wholeNumberValue, character.isASCII, character.isNumber {
                digits.append(digit)
            }
        }
        guard digits.count >= 2 else { return 0 }

        let hours = digits[0] * 10 + digits[1]
        let minutes = digits.count >= 4 ? digits[2] * 10 + digits[3] : 0
        return sign * (hours * 60 + minutes)
    }
}
