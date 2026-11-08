import Foundation

/// Preflight the ZIP before passing it to the system extractor. No symlinks,
/// special files, duplicate paths, encrypted entries, ZIP64, or escaping names.
enum ExtractorArchive {
    static func validate(_ data: Data) throws {
        func invalid() -> ExtractorUpdater.UpdateError { .invalidDownload }
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - count else { throw invalid() }
            return (0..<count).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        guard data.count >= 22 else { throw invalid() }
        // Search only the bounded EOCD/comment region, requiring an exact end.
        let end = try (max(0, data.count - 65_557)...(data.count - 22)).reversed().first {
            try number($0, 4) == 0x06054b50 && $0 + 22 + number($0 + 20, 2) == data.count
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw invalid() }
        let count = try number(end + 10, 2), size = try number(end + 12, 4), start = try number(end + 16, 4)
        guard (1...5_000).contains(count), try number(end + 8, 2) == count,
              start + size == end else { throw invalid() }
        var offset = start, totalSize = 0
        var names = Set<String>()
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw invalid() }
            let flags = try number(offset + 8, 2), method = try number(offset + 10, 2)
            let compressed = try number(offset + 20, 4), expanded = try number(offset + 24, 4)
            let length = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            let mode = try number(offset + 38, 4) >> 16
            let local = try number(offset + 42, 4)
            let nameStart = offset + 46
            guard flags & 1 == 0, [0, 8].contains(method), [0, 0o100000, 0o040000].contains(mode & 0o170000),
                  length > 0, nameStart + length + extra + comment <= end,
                  compressed != 0xffffffff, expanded != 0xffffffff,
                  try number(offset + 34, 2) == 0,
                  let name = String(data: data.subdata(in: nameStart..<(nameStart + length)), encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0") else { throw invalid() }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.contains(".."), !parts.contains("."), !parts.dropLast().contains(""),
                  names.insert(name.hasSuffix("/") ? String(name.dropLast()) : name).inserted else { throw invalid() }
            // The local header must describe the same name as the directory.
            guard local < start, try number(local, 4) == 0x04034b50,
                  try number(local + 26, 2) == length else { throw invalid() }
            let localExtra = try number(local + 28, 2)
            guard local + 30 + length + localExtra + compressed <= start,
                  data.subdata(in: (local + 30)..<(local + 30 + length)) == data.subdata(in: nameStart..<(nameStart + length)) else { throw invalid() }
            totalSize += expanded
            guard totalSize <= 512 * 1024 * 1024 else { throw invalid() }
            offset = nameStart + length + extra + comment
        }
        guard offset == end else { throw invalid() }
    }
}
