import Testing
@testable import GeetCore

@Suite struct HorizontalShelfDragTests {
    @Test func aSmallMovementStillClicks() {
        var drag = HorizontalShelfDrag(x: 100, y: 80, offset: 0, maximumOffset: 300)
        #expect(drag.move(x: 103, y: 82) == nil)
        #expect(drag.shouldClick)
    }
    @Test func horizontalDraggingClampsAndNeverBecomesAClickAgain() {
        var drag = HorizontalShelfDrag(x: 100, y: 80, offset: 30, maximumOffset: 102)
        #expect(drag.move(x: 40, y: 82) == 90)
        #expect(!drag.shouldClick)
        #expect(drag.move(x: -200, y: 82) == 102)
        #expect(drag.move(x: 150, y: 82) == 0)
        #expect(drag.move(x: 100, y: 80) == 30)
        #expect(!drag.shouldClick)
    }
    @Test func verticalDraggingCancelsTheClickWithoutScrolling() {
        var drag = HorizontalShelfDrag(x: 100, y: 80, offset: 30, maximumOffset: 102)
        #expect(drag.move(x: 101, y: 95) == nil)
        #expect(!drag.shouldClick)
        #expect(drag.move(x: 20, y: 95) == nil)
        #expect(drag.move(x: 100, y: 80) == nil)
        #expect(!drag.shouldClick)
    }
}
