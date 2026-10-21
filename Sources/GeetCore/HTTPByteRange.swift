import Foundation

/// A single HTTP byte range, clipped to an immutable resource's actual length.
public enum HTTPByteRange {
    public static func parse(_ header: String?, length: Int64) -> ClosedRange<Int64>? {
        guard length > 0 else { return nil }
        guard let header else { return 0...(length - 1) }
        guard header.lowercased().hasPrefix("bytes="), !header.contains(",") else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        if parts[0].isEmpty {
            guard let count = Int64(parts[1]), count > 0 else { return nil }
            return max(0, length - count)...(length - 1)
        }
        guard let start = Int64(parts[0]), start >= 0, start < length else { return nil }
        let last = parts[1].isEmpty ? length - 1 : Int64(parts[1])
        guard let last, last >= start else { return nil }
        return start...min(last, length - 1)
    }
}
