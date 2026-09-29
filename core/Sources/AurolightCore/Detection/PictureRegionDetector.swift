import Foundation

public struct PictureRegionDetector: Sendable {
    static let step = 4
    static let changeThreshold = 6
    static let activitySeconds = 1.5
    static let maxStep = 0.25
    static let minMovingShare = 0.005
    static let activeLevel: Float = 0.02
    static let staticSeconds = 1.0
    static let coverageSeconds = 3.0
    static let scrollMemory = 1.0
    static let minArea = 0.08
    static let minFill = 0.6
    static let minStaticSurround = 0.97
    static let minSurroundLevel = 40.0
    static let centerTolerance = 0.02
    static let boundaryContrast = 20
    static let boundaryShare = 0.5
    static let continuityShare = 0.6
    static let blackLevel = 24
    static let confirmSeconds = 1.5
    static let confirmFrames = 8
    static let decisionInterval = 0.1
    static let edgeTolerance = 6
    public static let idleRelease = 30.0
    static let busySeconds = 0.3
    static let busyShare = 0.05
    static let busyRingShare = 0.2
    static let minScrollArea = 0.02
    static let scrollChange = 6
    static let scrollMatch = 2
    static let maxScrollShift = 24
    static let minScrollMatches = 30
    static let minScrollShare = 0.25
    static let minGrowthMotion = 0.25

    struct Box: Equatable, Sendable {
        var x0, y0, x1, y1: Int

        func agrees(with other: Box) -> Bool {
            abs(x0 - other.x0) <= edgeTolerance && abs(x1 - other.x1) <= edgeTolerance
                && abs(y0 - other.y0) <= edgeTolerance && abs(y1 - other.y1) <= edgeTolerance
        }
    }

    private var width = 0, height = 0
    private var rowSamples: [UInt8] = []
    private var nextRowSamples: [UInt8] = []
    private var columnSamples: [UInt8] = []
    private var columnHits: [Int] = []
    private var lastChange: [Double] = []
    private var rowActivity: [Float] = []
    private var columnActivity: [Float] = []
    private var lastTime: Double?
    private var candidate: Box?
    private var candidateSeconds = 0.0
    private var candidateFrames = 0
    private var lastActivity = 0.0
    private var changedSamples = 0
    private var lastScroll = -Double.infinity
    private var sinceDecision = 0.0

    private(set) var region: Box?

    public init() {}

    public var insets: EdgeValues? {
        guard let region, width > 0, height > 0 else { return nil }
        return EdgeValues(
            top: Double(region.y0) / Double(height), right: Double(width - region.x1) / Double(width),
            bottom: Double(height - region.y1) / Double(height), left: Double(region.x0) / Double(width))
    }

    public mutating func expire(at time: Double) -> Bool {
        guard region != nil, time - lastActivity >= Self.idleRelease else { return false }
        release()
        return true
    }

    public mutating func update(
        bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, at time: Double,
        allowsOffCenter: Bool
    ) -> Bool {
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        guard width >= 64, height >= 64 else { return false }
        if width != self.width || height != self.height { start(width: width, height: height) }
        guard let last = lastTime else {
            lastTime = time
            measure(pixels, bytesPerRow: bytesPerRow, blend: nil, time: time)
            swap(&rowSamples, &nextRowSamples)
            return false
        }
        let dt = min(max(time - last, 0), Self.maxStep)
        guard dt > 0 else { return false }
        lastTime = time
        // Swap only after the scroll check has compared against the previous frame.
        defer { swap(&rowSamples, &nextRowSamples) }

        measure(pixels, bytesPerRow: bytesPerRow, blend: Float(1 - exp(-dt / Self.activitySeconds)), time: time)
        if Double(changedSamples) > Self.minMovingShare * Double(columns * rows) { lastActivity = time }
        if !allowsOffCenter, let region, !isCentered(region) {
            startOver()
            return true
        }
        // Checked every frame, not per decision: a moved picture must be let go at once.
        if let region, surroundIsBusy(around: region) {
            startOver()
            return true
        }
        sinceDecision += dt
        guard sinceDecision >= Self.decisionInterval * 0.99 else { return false }  // tolerate timestamp jitter
        let elapsed = sinceDecision
        sinceDecision = 0
        let before = region
        watchForScrolling(pixels, bytesPerRow: bytesPerRow, now: time)
        track(find(pixels, bytesPerRow: bytesPerRow, allowsOffCenter: allowsOffCenter), dt: elapsed)
        return region != before
    }

    private var columns: Int { width / Self.step }
    private var rows: Int { height / Self.step }

    private mutating func start(width: Int, height: Int) {
        self = PictureRegionDetector()
        self.width = width
        self.height = height
        lastChange = [Double](repeating: -.infinity, count: columns * rows)
        rowActivity = [Float](repeating: 0, count: height)
        columnActivity = [Float](repeating: 0, count: width)
        rowSamples = [UInt8](repeating: 0, count: height * columns * 3)
        nextRowSamples = rowSamples
        columnSamples = [UInt8](repeating: 0, count: rows * width * 3)
        columnHits = [Int](repeating: 0, count: width)
    }

    private mutating func measure(_ pixels: UnsafePointer<UInt8>, bytesPerRow: Int, blend k: Float?, time: Double) {
        changedSamples = 0
        let t = Self.changeThreshold, step = Self.step
        for y in 0..<height {
            let line = pixels + y * bytesPerRow
            let grid = y.isMultiple(of: step) && y / step < rows ? (y / step) * columns : nil
            var hits = 0
            for gx in 0..<columns {
                let p = line + gx * step * 4
                let o = (y * columns + gx) * 3
                let hit =
                    abs(Int(p[0]) - Int(rowSamples[o])) > t || abs(Int(p[1]) - Int(rowSamples[o + 1])) > t
                    || abs(Int(p[2]) - Int(rowSamples[o + 2])) > t
                nextRowSamples[o] = p[0]
                nextRowSamples[o + 1] = p[1]
                nextRowSamples[o + 2] = p[2]
                guard k != nil else { continue }
                if hit { hits += 1 }
                if hit, let grid {
                    lastChange[grid + gx] = time
                    changedSamples += 1
                }
            }
            if let k { rowActivity[y] += (Float(hits) / Float(columns) - rowActivity[y]) * k }
        }
        for x in 0..<width { columnHits[x] = 0 }
        for gy in 0..<rows {
            let line = pixels + gy * step * bytesPerRow
            for x in 0..<width {
                let p = line + x * 4
                let o = (gy * width + x) * 3
                if abs(Int(p[0]) - Int(columnSamples[o])) > t || abs(Int(p[1]) - Int(columnSamples[o + 1])) > t
                    || abs(Int(p[2]) - Int(columnSamples[o + 2])) > t
                {
                    columnHits[x] += 1
                }
                columnSamples[o] = p[0]
                columnSamples[o + 1] = p[1]
                columnSamples[o + 2] = p[2]
            }
        }
        if let k {
            for x in 0..<width { columnActivity[x] += (Float(columnHits[x]) / Float(rows) - columnActivity[x]) * k }
        }
    }

    private mutating func find(_ pixels: UnsafePointer<UInt8>, bytesPerRow: Int, allowsOffCenter: Bool) -> Box?? {
        let now = lastTime ?? 0
        guard let cells = movingCells(now: now) else { return nil }
        let (gx0, gy0, gx1, gy1) = cells
        if gx0 <= 1, gy0 <= 1, gx1 >= columns - 2, gy1 >= rows - 2 { return .some(nil) }
        guard surroundingsAreStill(outside: cells, now: now, pixels, bytesPerRow: bytesPerRow, allowsOffCenter)
        else { return nil }

        let moving = refine(
            Box(x0: gx0 * Self.step, y0: gy0 * Self.step, x1: (gx1 + 1) * Self.step, y1: (gy1 + 1) * Self.step))
        let boundaries = PictureBoundaries(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
        guard var box = boundaries.snap(moving) else { return nil }
        if !allowsOffCenter {
            guard isCentered(box) else { return nil }
            let tolX = Int(Self.centerTolerance * Double(width)), tolY = Int(Self.centerTolerance * Double(height))
            if box.x0 <= tolX { (box.x0, box.x1) = (0, width) }
            if box.y0 <= tolY { (box.y0, box.y1) = (0, height) }
        }
        if !(region?.agrees(with: box) ?? false), now - lastScroll < Self.scrollMemory { return nil }
        // A dark picture edge can snap past it onto static page content; real growth reveals moving picture.
        if let region, !growthIsMoving(from: region, to: box, now: now) { return nil }
        return box
    }

    private func movingCells(now: Double) -> (Int, Int, Int, Int)? {
        func moving(_ gx: Int, _ gy: Int) -> Bool {
            gx >= 0 && gy >= 0 && gx < columns && gy < rows
                && now - lastChange[gy * columns + gx] < Self.coverageSeconds
        }
        var gx0 = columns, gy0 = rows, gx1 = -1, gy1 = -1, activeCount = 0
        for gy in 0..<rows {
            for gx in 0..<columns where moving(gx, gy) {
                let neighbors = Self.neighborOffsets.count { moving(gx + $0.x, gy + $0.y) }
                guard neighbors >= 3 else { continue }
                activeCount += 1
                gx0 = min(gx0, gx)
                gy0 = min(gy0, gy)
                gx1 = max(gx1, gx)
                gy1 = max(gy1, gy)
            }
        }
        guard activeCount > 0 else { return nil }
        let boxCells = (gx1 - gx0 + 1) * (gy1 - gy0 + 1)
        guard Double(boxCells) >= Self.minArea * Double(columns * rows),
            Double(activeCount) >= Self.minFill * Double(boxCells)
        else { return nil }
        return (gx0, gy0, gx1, gy1)
    }

    private static let neighborOffsets = [
        (x: -1, y: -1), (x: 0, y: -1), (x: 1, y: -1), (x: -1, y: 0), (x: 1, y: 0), (x: -1, y: 1), (x: 0, y: 1),
        (x: 1, y: 1),
    ]

    private func surroundingsAreStill(
        outside cells: (Int, Int, Int, Int), now: Double, _ pixels: UnsafePointer<UInt8>, bytesPerRow: Int,
        _ allowsOffCenter: Bool
    ) -> Bool {
        let (gx0, gy0, gx1, gy1) = cells
        var outside = 0, still = 0, level = 0.0
        for gy in 0..<rows {
            for gx in 0..<columns where gx < gx0 || gx > gx1 || gy < gy0 || gy > gy1 {
                outside += 1
                if now - lastChange[gy * columns + gx] >= Self.staticSeconds { still += 1 }
                let p = pixels + gy * Self.step * bytesPerRow + gx * Self.step * 4
                level += Double(max(p[0], p[1], p[2]))
            }
        }
        return outside > 0 && Double(still) >= Self.minStaticSurround * Double(outside)
            && (allowsOffCenter || level / Double(outside) > Self.minSurroundLevel)
    }

    private func growthIsMoving(from region: Box, to box: Box, now: Double) -> Bool {
        let tolerance = Self.edgeTolerance
        let strips = [
            box.y0 < region.y0 - tolerance ? Box(x0: box.x0, y0: box.y0, x1: box.x1, y1: region.y0) : nil,
            box.y1 > region.y1 + tolerance ? Box(x0: box.x0, y0: region.y1, x1: box.x1, y1: box.y1) : nil,
            box.x0 < region.x0 - tolerance ? Box(x0: box.x0, y0: box.y0, x1: region.x0, y1: box.y1) : nil,
            box.x1 > region.x1 + tolerance ? Box(x0: region.x1, y0: box.y0, x1: box.x1, y1: box.y1) : nil,
        ]
        return strips.allSatisfy { strip in
            guard let strip else { return true }
            var cells = 0, moving = 0
            for gy in strip.y0 / Self.step..<min(rows, (strip.y1 + Self.step - 1) / Self.step) {
                for gx in strip.x0 / Self.step..<min(columns, (strip.x1 + Self.step - 1) / Self.step) {
                    cells += 1
                    if now - lastChange[gy * columns + gx] < Self.coverageSeconds { moving += 1 }
                }
            }
            return cells == 0 || Double(moving) >= Self.minGrowthMotion * Double(cells)
        }
    }

    private func isCentered(_ box: Box) -> Bool {
        let tolX = Int(Self.centerTolerance * Double(width)), tolY = Int(Self.centerTolerance * Double(height))
        return abs(box.x0 - (width - box.x1)) <= tolX && abs(box.y0 - (height - box.y1)) <= tolY
    }

    private func refine(_ box: Box) -> Box {
        func active(_ values: [Float], _ i: Int) -> Bool { values[i] > Self.activeLevel }
        var b = box
        let s = Self.step
        b.y0 = (max(0, box.y0 - s)..<min(height, box.y0 + s)).first { active(rowActivity, $0) } ?? box.y0
        b.y1 = ((max(0, box.y1 - s)..<min(height, box.y1 + s)).last { active(rowActivity, $0) } ?? box.y1 - 1) + 1
        b.x0 = (max(0, box.x0 - s)..<min(width, box.x0 + s)).first { active(columnActivity, $0) } ?? box.x0
        b.x1 = ((max(0, box.x1 - s)..<min(width, box.x1 + s)).last { active(columnActivity, $0) } ?? box.x1 - 1) + 1
        return b
    }

    private mutating func watchForScrolling(_ pixels: UnsafePointer<UInt8>, bytesPerRow: Int, now: Double) {
        var gx0 = columns, gy0 = rows, gx1 = -1, gy1 = -1, count = 0
        for gy in 0..<rows {
            for gx in 0..<columns where now - lastChange[gy * columns + gx] < Self.decisionInterval * 1.5 {
                gx0 = min(gx0, gx); gy0 = min(gy0, gy); gx1 = max(gx1, gx); gy1 = max(gy1, gy)
                count += 1
            }
        }
        guard Double(count) >= Self.minScrollArea * Double(columns * rows) else { return }
        let changed = Box(
            x0: gx0 * Self.step, y0: gy0 * Self.step, x1: (gx1 + 1) * Self.step, y1: (gy1 + 1) * Self.step)
        guard isScrolling(pixels, bytesPerRow: bytesPerRow, in: changed) else { return }
        lastScroll = now
        for i in lastChange.indices { lastChange[i] = -.infinity }
    }

    private func isScrolling(_ pixels: UnsafePointer<UInt8>, bytesPerRow: Int, in box: Box) -> Bool {
        let step = Self.step
        let gx0 = (box.x0 + step - 1) / step, gx1 = min(columns, box.x1 / step)
        guard gx1 > gx0 else { return false }
        func current(_ gx: Int, _ y: Int) -> Int { Int((pixels + y * bytesPerRow + gx * step * 4)[1]) }
        func previous(_ gx: Int, _ y: Int) -> Int { Int(rowSamples[(y * columns + gx) * 3 + 1]) }
        // Only samples with detail: flat areas match any shift.
        var changed: [(gx: Int, y: Int)] = []
        let shift = Self.maxScrollShift, change = Self.scrollChange
        var y = box.y0 + shift
        while y < box.y1 - shift {
            for gx in stride(from: gx0, to: gx1, by: 2)
            where abs(current(gx, y) - previous(gx, y)) > change && abs(current(gx, y) - current(gx, y - 1)) > change {
                changed.append((gx, y))
            }
            y += 2
        }
        guard changed.count >= Self.minScrollMatches else { return false }
        let needed = max(Self.minScrollMatches, Int((Self.minScrollShare * Double(changed.count)).rounded(.up)))
        let now = changed.map { current($0.gx, $0.y) }
        for magnitude in 1...shift {
            for dy in [magnitude, -magnitude] {
                var matches = 0
                for (k, sample) in changed.enumerated() {
                    if abs(now[k] - previous(sample.gx, sample.y - dy)) <= Self.scrollMatch {
                        matches += 1
                        if matches >= needed { return true }
                    } else if matches + changed.count - k - 1 < needed {
                        break
                    }
                }
            }
        }
        return false
    }

    private mutating func track(_ found: Box??, dt: Double) {
        let now = lastTime ?? 0
        if now - lastActivity >= Self.idleRelease { release() }

        guard let found else { return }
        guard let box = found else {
            candidate = nil
            release()
            return
        }
        if let current = candidate, current.agrees(with: box) {
            candidateSeconds += dt
            candidateFrames += 1
            candidate = box
        } else {
            candidate = box
            candidateSeconds = 0
            candidateFrames = 1
        }
        if candidateSeconds >= Self.confirmSeconds, candidateFrames >= Self.confirmFrames {
            if !(region?.agrees(with: box) ?? false) { region = box }
        }
    }

    private func surroundIsBusy(around box: Box) -> Bool {
        let now = lastTime ?? 0
        let ring = 2 * Self.step
        var outside = 0, busy = 0, ringCount = 0, ringBusy = 0
        for gy in 0..<rows {
            for gx in 0..<columns {
                let x = gx * Self.step, y = gy * Self.step
                let inside = x >= box.x0 && x < box.x1 && y >= box.y0 && y < box.y1
                guard !inside else { continue }
                let recent = now - lastChange[gy * columns + gx] < Self.busySeconds
                let nearEdge = x >= box.x0 - ring && x < box.x1 + ring && y >= box.y0 - ring && y < box.y1 + ring
                if nearEdge {
                    ringCount += 1
                    if recent { ringBusy += 1 }
                } else {
                    outside += 1
                    if recent { busy += 1 }
                }
            }
        }
        return (outside > 0 && Double(busy) > Self.busyShare * Double(outside))
            || (ringCount > 0 && Double(ringBusy) > Self.busyRingShare * Double(ringCount))
    }

    private mutating func startOver() {
        release()
        candidate = nil
        for i in lastChange.indices { lastChange[i] = -.infinity }
        for i in rowActivity.indices { rowActivity[i] = 0 }
        for i in columnActivity.indices { columnActivity[i] = 0 }
    }

    private mutating func release() {
        region = nil
        candidateSeconds = 0
        candidateFrames = 0
    }
}
