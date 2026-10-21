import Foundation

/// YouTube DASH audio includes a complete duration in an otherwise empty movie
/// header as well as timed fragments. AVFoundation adds these durations together.
/// Clear those durations for an HLS initialization section, preserving every byte offset and
/// every encoded audio sample. No remuxer or transcoder is needed.
public enum MP4Audio {
    public static func normalizedHeader(_ input: Data) -> Data {
        let bytes = [UInt8](input)
        struct Box { let kind: String; let payload: Int; let end: Int }
        func integer(_ offset: Int, _ count: Int) -> UInt64? {
            guard offset >= 0, count <= 8, offset <= bytes.count - count else { return nil }
            return bytes[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func boxes(_ start: Int, _ end: Int) -> [Box] {
            var result: [Box] = [], cursor = start
            while cursor <= end - 8 {
                guard let small = integer(cursor, 4) else { break }
                let header = small == 1 ? 16 : 8
                let size = small == 1 ? integer(cursor + 8, 8) : small == 0 ? UInt64(end - cursor) : small
                guard let size, size >= header, size <= end - cursor else { break }
                result.append(Box(kind: String(decoding: bytes[(cursor + 4)..<(cursor + 8)], as: UTF8.self), payload: cursor + header, end: cursor + Int(size)))
                cursor += Int(size)
            }
            return result
        }
        let top = boxes(0, bytes.count)
        guard let type = top.first(where: { $0.kind == "ftyp" }), type.end - type.payload >= 8,
              stride(from: type.payload, through: type.end - 4, by: 4).contains(where: { offset in
                  offset != type.payload + 4 && String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self) == "dash"
              }), let movie = top.first(where: { $0.kind == "moov" }) else { return input }
        let children = boxes(movie.payload, movie.end)
        guard children.contains(where: { $0.kind == "mvex" }) else { return input }
        var fields: [Range<Int>] = []
        func duration(_ box: Box) {
            guard box.payload < box.end, bytes[box.payload] <= 1 else { return }
            let versionOne = bytes[box.payload] == 1
            let offset = box.payload + (box.kind == "tkhd" ? (versionOne ? 28 : 20) : (versionOne ? 24 : 16))
            let count = versionOne ? 8 : 4
            if offset <= box.end - count { fields.append(offset..<(offset + count)) }
        }
        for box in children {
            if box.kind == "mvhd" { duration(box) }
            if box.kind == "trak" {
                for track in boxes(box.payload, box.end) {
                    if track.kind == "tkhd" { duration(track) }
                    if track.kind == "mdia" {
                        let media = boxes(track.payload, track.end)
                        let tables = media.filter { $0.kind == "minf" }.flatMap { boxes($0.payload, $0.end) }
                            .filter { $0.kind == "stbl" }.flatMap { boxes($0.payload, $0.end) }
                        // A header with real base samples must retain their duration.
                        guard let timing = tables.first(where: { $0.kind == "stts" }),
                              timing.end - timing.payload >= 8, integer(timing.payload + 4, 4) == 0 else { return input }
                        for header in media where header.kind == "mdhd" { duration(header) }
                    }
                }
            }
        }
        guard !fields.isEmpty else { return input }
        var output = Data(bytes)
        for field in fields { output.replaceSubrange(field, with: repeatElement(UInt8(0), count: field.count)) }
        return output
    }
}
