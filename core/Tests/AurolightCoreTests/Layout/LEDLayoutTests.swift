import Foundation
import Testing

@testable import AurolightCore

struct LEDLayoutTests {
    let layout = LEDLayout(top: 4, right: 2, bottom: 4, left: 2)

    @Test func aBadSettingsFileCantAskForTooManyLEDs() throws {
        let json = #"{"top": 10000000000, "right": -5, "startOffset": 9223372036854775807}"#
        let decoded = try JSONDecoder().decode(LEDLayout.self, from: Data(json.utf8))
        #expect(decoded.top == LEDLayout.maxPerEdge && decoded.right == 0)
        #expect(abs(decoded.startOffset) <= decoded.placedCount / 2)
        #expect(decoded.slots().count == decoded.placedCount)
    }

    @Test func counts() {
        #expect(layout.placedCount == 12)
        #expect(layout.slots().count == 12)
    }

    @Test func clockwiseFromBottomLeftGoesUpTheLeftEdge() {
        var l = layout
        l.startCorner = .bottomLeft
        l.direction = .clockwise
        let slots = l.slots()
        #expect(slots[0].edge == .left && slots[0].position == 0.75)
        #expect(slots[1].edge == .left && slots[1].position == 0.25)
        #expect(slots[2].edge == .top && slots[2].position == 0.125)
        #expect(slots.last?.edge == .bottom && slots.last?.position == 0.125)
    }

    @Test func counterClockwiseFromBottomLeftGoesAlongTheBottom() {
        var l = layout
        l.startCorner = .bottomLeft
        l.direction = .counterClockwise
        let slots = l.slots()
        #expect(slots[0].edge == .bottom && slots[0].position == 0.125)
        #expect(slots[3].edge == .bottom && slots[3].position == 0.875)
        #expect(slots[4].edge == .right && slots[4].position == 0.75)
        #expect(slots.last?.edge == .left && slots.last?.position == 0.75)
    }

    @Test func offsetShiftsStartAndWraps() {
        var l = layout
        l.startCorner = .topLeft
        l.startOffset = 2
        #expect(l.slots()[0].edge == .top && l.slots()[0].position == 0.625)
        l.startOffset = -1
        #expect(l.slots()[0].edge == .left && l.slots()[0].position == 0.25)
    }

    @Test func negativeCountAssignmentIsClamped() {
        var l = LEDLayout(top: 4, right: 2, bottom: 4, left: 2)
        l.right = -3
        #expect(l.right == 0)
        #expect(l.slots().count == 10)
    }

    @Test func missingEdgeIsSkipped() {
        let l = LEDLayout(top: 3, right: 2, bottom: 0, left: 2, startCorner: .bottomLeft)
        let edges = l.slots().map(\.edge)
        #expect(edges == [.left, .left, .top, .top, .top, .right, .right])
    }

    @Test func regionsStayInsideScreen() {
        for slot in LEDLayout(insets: EdgeValues(top: 0.3, right: 0.2, bottom: 0.25, left: 0.15)).slots() {
            let r = slot.region
            #expect(r.x >= 0 && r.y >= 0)
            #expect(r.x + r.width <= 1.0000001 && r.y + r.height <= 1.0000001)
        }
    }

    @Test func insetsMoveRegionsInward() {
        let l = LEDLayout(
            top: 2, right: 0, bottom: 0, left: 0, startCorner: .topLeft,
            insets: EdgeValues(top: 0.2, right: 0.1, bottom: 0.2, left: 0.1))
        let first = l.slots()[0].region
        #expect(abs(first.x - 0.1) < 1e-9)
        #expect(abs(first.y - 0.2) < 1e-9)
        #expect(abs(first.width - 0.4) < 1e-9)
        #expect(abs(first.height - 0.06) < 1e-9)
    }

    @Test(arguments: [StripDirection.clockwise, .counterClockwise])
    func makeStartMovesClickedLEDToIndexZero(direction: StripDirection) {
        var l = layout
        l.direction = direction
        l.startOffset = 1
        for k in [0, 3, 7, 11] {
            var m = l
            let target = l.slots()[k]
            m.makeStart(stripIndex: k)
            #expect(m.slots()[0] == target)
            #expect(abs(m.startOffset) <= l.placedCount / 2)
        }
    }

    @Test(arguments: [StripDirection.clockwise, .counterClockwise])
    func reverseKeepsStartAndFlipsOrder(direction: StripDirection) {
        var l = layout
        l.direction = direction
        l.startOffset = 3
        let before = l.slots()
        l.reverseDirection()
        let after = l.slots()
        #expect(l.direction != direction)
        #expect(after[0] == before[0])
        #expect(after[1] == before[before.count - 1])
    }

    @Test func staleKeysStillDecodeWithoutACrop() throws {
        let json =
            #"{"top":2,"right":2,"bottom":2,"left":2,"insetX":0.05,"insetY":0.03,"#
            + #""insets":{"top":0.1,"right":0.1,"bottom":0.1,"left":0.1},"#
            + #""depths":{"top":0.3,"right":0.3,"bottom":0.3,"left":0.3}}"#
        let l = try JSONDecoder().decode(LEDLayout.self, from: Data(json.utf8))
        #expect(l.top == 2 && l.left == 2)
        #expect(l.insets == .uniform(0))
    }

    @Test func insetsAreNotPersisted() throws {
        let l = LEDLayout(
            top: 3, right: 1, bottom: 2, left: 1, startCorner: .topRight, startOffset: 1,
            direction: .counterClockwise, insets: EdgeValues(top: 0.1, right: 0.05, bottom: 0.1, left: 0.05))
        let decoded = try JSONDecoder().decode(LEDLayout.self, from: JSONEncoder().encode(l))
        #expect(decoded.insets == .uniform(0))
        var expected = l
        expected.insets = .uniform(0)
        #expect(decoded == expected)
    }

    @Test func negativeCountDecodesAsZero() throws {
        let l = try JSONDecoder().decode(LEDLayout.self, from: Data(#"{"top":-5}"#.utf8))
        #expect(l.top == 0)
        #expect(l.placedCount == l.slots().count)
    }

    @Test func badEnumValueFallsBackAlone() throws {
        let json = #"{"top":5,"startCorner":"middle","direction":"counterClockwise"}"#
        let l = try JSONDecoder().decode(LEDLayout.self, from: Data(json.utf8))
        #expect(l.startCorner == LEDLayout().startCorner)
        #expect(l.top == 5 && l.direction == .counterClockwise)
    }

    @Test func topOnlyInsetLeavesBottomUntouched() {
        let l = LEDLayout(
            top: 1, right: 0, bottom: 1, left: 0, startCorner: .topLeft,
            insets: EdgeValues(top: 0.0326, right: 0, bottom: 0, left: 0))
        let area = l.detectionArea
        #expect(abs(area.y - 0.0326) < 1e-9)
        #expect(abs(area.y + area.height - 1) < 1e-9)
    }

    @Test func largeInsetsAreKeptWhilePictureRemains() {
        var layout = LEDLayout()
        layout.insets = EdgeValues(top: 0.5, right: 0.06, bottom: 0.1, left: 0.56)
        let area = layout.detectionArea
        #expect(abs(area.x - 0.56) < 1e-9 && abs(area.width - 0.38) < 1e-9)
        #expect(abs(area.y - 0.5) < 1e-9 && abs(area.height - 0.4) < 1e-9)
    }

    @Test func insetsLeaveAtLeastTheMinimumPicture() {
        var layout = LEDLayout()
        layout.insets = EdgeValues(top: 0, right: 0.6, bottom: 0, left: 0.6)
        let area = layout.detectionArea
        #expect(abs(area.width - LEDLayout.minExtent) < 1e-9 && abs(area.x - 0.45) < 1e-9)
    }
}
