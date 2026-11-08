import Foundation
import Testing
@testable import GeetCore

@Suite struct ExtractorArchiveTests {
    // Minimal stored ZIP entries, sufficient to exercise preflight independently
    // of the system extractor. No downloaded executable is involved.
    private func archive(_ entries: [(String, Int, Int)]) -> Data {
        var data = Data(), central = Data()
        func append(_ value: Int, _ width: Int, to target: inout Data) {
            for byte in 0..<width { target.append(UInt8(truncatingIfNeeded: value >> (byte * 8))) }
        }
        for (name, mode, expanded) in entries {
            let offset = data.count, bytes = Data(name.utf8)
            append(0x04034b50, 4, to: &data)
            for value in [20, 0, 0, 0, 0] { append(value, 2, to: &data) }
            for value in [0, 0, expanded] { append(value, 4, to: &data) }
            append(bytes.count, 2, to: &data); append(0, 2, to: &data); data.append(bytes)
            append(0x02014b50, 4, to: &central)
            for value in [0x0314, 20, 0, 0, 0, 0] { append(value, 2, to: &central) }
            for value in [0, 0, expanded] { append(value, 4, to: &central) }
            for value in [bytes.count, 0, 0, 0, 0] { append(value, 2, to: &central) }
            append(mode << 16, 4, to: &central); append(offset, 4, to: &central); central.append(bytes)
        }
        let start = data.count
        data.append(central)
        append(0x06054b50, 4, to: &data)
        for value in [0, 0, entries.count, entries.count] { append(value, 2, to: &data) }
        append(central.count, 4, to: &data); append(start, 4, to: &data); append(0, 2, to: &data)
        return data
    }
    @Test func acceptsRegularRuntimePaths() throws {
        try ExtractorArchive.validate(archive([("yt-dlp_macos", 0o100755, 10), ("_internal/", 0o040755, 0), ("_internal/libpython.dylib", 0o100644, 10)]))
    }
    @Test(arguments: ["../escape", "/escape", "a/../../escape", "a\\escape", "a/./file", "a//file", "a:file", "nul\0file"])
    func rejectsEscapingAndAmbiguousPaths(name: String) {
        #expect(throws: (any Error).self) { try ExtractorArchive.validate(archive([(name, 0o100644, 0)])) }
    }
    @Test(arguments: [0o120777, 0o060644, 0o020644])
    func rejectsSymlinksAndSpecialFiles(mode: Int) {
        #expect(throws: (any Error).self) { try ExtractorArchive.validate(archive([("_internal/link", mode, 0)])) }
    }
    @Test func rejectsDuplicatePathsAndExpandedSizeOverflow() {
        #expect(throws: (any Error).self) { try ExtractorArchive.validate(archive([("same", 0o100644, 0), ("same/", 0o040755, 0)])) }
        #expect(throws: (any Error).self) { try ExtractorArchive.validate(archive([("large", 0o100644, 512 * 1024 * 1024 + 1)])) }
    }
    @Test func rejectsTruncatedAndMismatchedLocalHeaders() {
        let valid = archive([("file", 0o100644, 0)])
        for length in 0..<valid.count {
            #expect(throws: (any Error).self) { try ExtractorArchive.validate(Data(valid.prefix(length))) }
        }
        var mismatch = valid
        mismatch[30] = 120
        #expect(throws: (any Error).self) { try ExtractorArchive.validate(mismatch) }
    }
}
