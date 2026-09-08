import Foundation

// MARK: - UTF-8 sanitiser (FER-382)
//
// A fifteen-year Apple Health export is a single XML document of many hundreds of
// megabytes. One byte in it that XML 1.0 does not admit — a stray NUL, half a character
// truncated by whatever wrote the file — makes a strict parser stop dead, and everything
// after that byte is lost. So the bytes are cleaned ON THE WAY IN: an `InputStream` that
// wraps the real one, hands the parser only legal UTF-8, and counts how many runs it had to
// touch so the caller can tell the user the export was not pristine.
//
// It is a filter, not a buffer: it holds one chunk plus, at most, the 1–3 bytes of a
// character that straddles a chunk boundary. Nothing is copied to RAM or to disk.
//
// Rules (XML 1.0 §2.2 for the legal character range; Unicode 15 §3.9 Table 3-7 for what
// makes a UTF-8 sequence well-formed):
//   · control bytes below 0x20 other than TAB, LF and CR are DELETED;
//   · 0x20–0x7F pass through untouched (0x7F/DEL included — XML allows it);
//   · a well-formed multi-byte sequence passes through byte for byte;
//   · anything else — stray continuation byte, overlong form, encoded surrogate, code point
//     beyond U+10FFFF, sequence truncated at end of file — becomes U+FFFD, and only the
//     offending header byte is consumed so the scan resynchronises immediately.
final class ScrubbedUTF8Stream: InputStream {

    /// Default read granularity. Big enough that the per-chunk work disappears next to the
    /// parsing, small enough that memory stays flat.
    static let defaultChunkSize = 65_536

    private let source: InputStream
    private let chunkSize: Int

    private var inputBuffer: [UInt8]
    private var work: [UInt8] = []
    /// The 1–3 leading bytes of a character cut in half by a chunk boundary.
    private var carry: [UInt8] = []
    private var output: [UInt8] = []
    private var outputCursor = 0
    private var sourceExhausted = false

    private var inScrubbedRun = false
    /// Contiguous runs of deleted or replaced bytes. A hundred bad bytes in a row is ONE.
    private(set) var scrubbedRuns = 0

    private var status: Stream.Status = .notOpen
    private var failure: Error?
    private var delegateStorage: StreamDelegate?

    init(source: InputStream, chunkSize: Int = ScrubbedUTF8Stream.defaultChunkSize) {
        self.source = source
        self.chunkSize = max(8, chunkSize)
        self.inputBuffer = [UInt8](repeating: 0, count: self.chunkSize)
        super.init(data: Data())
    }

    // MARK: InputStream

    override func open() {
        if source.streamStatus == .notOpen { source.open() }
        status = .open
    }

    override func close() {
        source.close()
        status = .closed
    }

    override var streamStatus: Stream.Status { status }
    override var streamError: Error? { failure ?? source.streamError }

    override var delegate: StreamDelegate? {
        get { delegateStorage }
        set { delegateStorage = newValue }
    }

    override var hasBytesAvailable: Bool {
        outputCursor < output.count || !sourceExhausted || !carry.isEmpty
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard len > 0 else { return 0 }
        while outputCursor == output.count {
            guard refill() else {
                status = .atEnd
                return 0
            }
        }
        let count = min(len, output.count - outputCursor)
        output.withUnsafeBufferPointer { bytes in
            buffer.update(from: bytes.baseAddress! + outputCursor, count: count)
        }
        outputCursor += count
        return count
    }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
                            length: UnsafeMutablePointer<Int>) -> Bool {
        false
    }

    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override func property(forKey key: Stream.PropertyKey) -> Any? { nil }
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }

    // MARK: Filtering

    /// Fills `output` with at least one byte, or reports that the source is spent.
    private func refill() -> Bool {
        output.removeAll(keepingCapacity: true)
        outputCursor = 0

        while output.isEmpty {
            if sourceExhausted {
                guard !carry.isEmpty else { return false }
                // A character cut short by the end of the file: one replacement, and done.
                carry.removeAll(keepingCapacity: true)
                emitReplacement()
                return true
            }
            let read = inputBuffer.withUnsafeMutableBufferPointer { buffer in
                source.read(buffer.baseAddress!, maxLength: buffer.count)
            }
            if read <= 0 {
                if read < 0 { failure = source.streamError }
                sourceExhausted = true
                continue
            }
            scrub(count: read)
        }
        return true
    }

    private func scrub(count: Int) {
        work.removeAll(keepingCapacity: true)
        work.append(contentsOf: carry)
        work.append(contentsOf: inputBuffer[0..<count])
        carry.removeAll(keepingCapacity: true)

        var index = 0
        while index < work.count {
            let byte = work[index]

            if byte < 0x20 {
                if byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    emit(byte)
                } else {
                    markScrubbed()          // illegal in XML 1.0 — dropped, not replaced
                }
                index += 1
                continue
            }
            if byte < 0x80 {
                emit(byte)
                index += 1
                continue
            }

            // Multi-byte header: how long, and what the second byte is allowed to be.
            // The narrowed second-byte ranges are what reject overlong forms (C0/C1, E0 80,
            // F0 80), encoded surrogates (ED A0) and code points past U+10FFFF (F4 90, F5+).
            let width: Int
            var secondLow: UInt8 = 0x80
            var secondHigh: UInt8 = 0xBF
            switch byte {
            case 0xC2...0xDF: width = 2
            case 0xE0:        width = 3; secondLow = 0xA0
            case 0xE1...0xEC: width = 3
            case 0xED:        width = 3; secondHigh = 0x9F
            case 0xEE...0xEF: width = 3
            case 0xF0:        width = 4; secondLow = 0x90
            case 0xF1...0xF3: width = 4
            case 0xF4:        width = 4; secondHigh = 0x8F
            default:
                emitReplacement()
                index += 1
                continue
            }

            if work.count - index < width {
                // The character straddles the chunk boundary — keep the head for next time.
                carry.append(contentsOf: work[index...])
                return
            }

            var wellFormed = work[index + 1] >= secondLow && work[index + 1] <= secondHigh
            if wellFormed && width > 2 {
                for offset in 2..<width where !(0x80...0xBF).contains(work[index + offset]) {
                    wellFormed = false
                    break
                }
            }
            guard wellFormed else {
                emitReplacement()
                index += 1
                continue
            }

            for offset in 0..<width { output.append(work[index + offset]) }
            inScrubbedRun = false
            index += width
        }
    }

    private func emit(_ byte: UInt8) {
        output.append(byte)
        inScrubbedRun = false
    }

    /// U+FFFD REPLACEMENT CHARACTER.
    private func emitReplacement() {
        output.append(0xEF)
        output.append(0xBF)
        output.append(0xBD)
        markScrubbed()
    }

    private func markScrubbed() {
        guard !inScrubbedRun else { return }
        scrubbedRuns += 1
        inScrubbedRun = true
    }
}
