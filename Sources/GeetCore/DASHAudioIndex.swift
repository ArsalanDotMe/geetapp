import Foundation

/// Maps immutable DASH fragments to native HLS byte ranges. Audio samples stay
/// unchanged; only a small in-memory playlist and initialization section are made.
public struct DASHAudioIndex: Sendable {
    public struct Segment: Sendable, Equatable {
        public let offset: Int64
        public let length: Int64
        public let duration: Double
    }
    public let initialization: Data
    public let segments: [Segment]
    public var duration: Double { segments.reduce(0) { $0 + $1.duration } }
    public var playlist: Data {
        let maximum = segments.map(\.duration).max() ?? 1
        var text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(Int(ceil(maximum)))\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI=\"init.mp4\"\n"
        for segment in segments {
            text += "#EXTINF:" + String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), segment.duration) + ",\n"
            text += "#EXT-X-BYTERANGE:\(segment.length)@\(segment.offset)\naudio.m4a\n"
        }
        text += "#EXT-X-ENDLIST\n"
        return Data(text.utf8)
    }
    public static func parse(_ input: Data, length: Int64) -> Self? {
        guard length > 0 else { return nil }
        let bytes = [UInt8](input)
        func read(_ offset: Int, _ count: Int) -> UInt64? {
            guard offset >= 0, count <= 8, offset <= bytes.count - count else { return nil }
            return bytes[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        var cursor = 0, movieEnd: Int?, index: (Int, Int)?
        while cursor <= bytes.count - 8 {
            guard let small = read(cursor, 4) else { return nil }
            let header = small == 1 ? 16 : 8
            let size = small == 1 ? read(cursor + 8, 8) : small
            guard let size, size >= header, size <= bytes.count - cursor else { break }
            let kind = String(decoding: bytes[(cursor + 4)..<(cursor + 8)], as: UTF8.self)
            if kind == "moov" { movieEnd = cursor + Int(size) }
            if kind == "sidx" { index = (cursor + header, cursor + Int(size)); break }
            cursor += Int(size)
        }
        guard let movieEnd, let (payload, end) = index, movieEnd <= payload,
              payload + 12 <= end, bytes[payload] <= 1,
              let timescale = read(payload + 8, 4), timescale > 0 else { return nil }
        let versionOne = bytes[payload] == 1
        guard payload + (versionOne ? 32 : 24) <= end,
              Int64(end) <= length,
              let skip = read(payload + (versionOne ? 20 : 16), versionOne ? 8 : 4),
              skip <= UInt64(max(0, length - Int64(end))),
              let count = read(payload + (versionOne ? 30 : 22), 2), count > 0, count <= 10_000 else { return nil }
        cursor = payload + (versionOne ? 32 : 24)
        guard Int(count) <= (end - cursor) / 12 else { return nil }
        var offset = Int64(end) + Int64(skip), segments: [Segment] = []
        for _ in 0..<Int(count) {
            guard let reference = read(cursor, 4), reference & 0x8000_0000 == 0,
                  reference > 0, reference <= UInt64(max(0, length - offset)),
                  let ticks = read(cursor + 4, 4), ticks > 0 else { return nil }
            segments.append(Segment(offset: offset, length: Int64(reference), duration: Double(ticks) / Double(timescale)))
            offset += Int64(reference); cursor += 12
        }
        return Self(initialization: MP4Audio.normalizedHeader(Data(bytes[..<movieEnd])), segments: segments)
    }
}
