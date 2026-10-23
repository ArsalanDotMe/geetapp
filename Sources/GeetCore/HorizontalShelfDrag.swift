import Foundation

/// A drag remains a drag even if the pointer returns to its starting point.
/// Vertical movement cancels the click without moving a horizontal shelf.
public struct HorizontalShelfDrag {
    private enum Direction { case undecided, horizontal, cancelled }
    private var direction = Direction.undecided
    private let startX: Double
    private let startY: Double
    private let initialOffset: Double
    private let maximumOffset: Double
    public var shouldClick: Bool { direction == .undecided }

    public init(x: Double, y: Double, offset: Double, maximumOffset: Double) {
        startX = x; startY = y; initialOffset = offset; self.maximumOffset = max(0, maximumOffset)
    }

    public mutating func move(x: Double, y: Double) -> Double? {
        let dx = x - startX, dy = y - startY
        if direction == .undecided, hypot(dx, dy) >= 6 {
            direction = abs(dx) > abs(dy) ? .horizontal : .cancelled
        }
        guard direction == .horizontal else { return nil }
        return min(maximumOffset, max(0, initialOffset - dx))
    }
}
