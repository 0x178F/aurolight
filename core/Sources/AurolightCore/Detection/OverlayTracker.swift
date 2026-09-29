struct OverlayTracker: Sendable {
    static let stillDistance = 0.012
    static let stillChannel = 5
    static let textChannel = 24
    static let neutralSpread = 24
    static let clippedLevels = (dark: 4, light: 250)
    static let brightPeak = 0.85
    static let movingShare = 0.5
    static let stableFrames = 120
    static let cutShare = 0.8
    static let cutEvidence = 30
    static let detailSpread = 32
    static let minDetailShare = 0.1
    static let detailFrames = 30
    static let patchEdgeLevels = 10
    static let maxComponentShare = 0.05
    static let maxTotalShare = 0.1
    static let groupingInterval = 10

    private var columns = 0, rows = 0
    private var template: [(Double, Double, Double)] = []
    private var peakTemplate: [PackedColor] = []
    private var textureTemplate: [CellSamples] = []
    private var still: [Int] = []
    private var detailed: [Bool] = []
    private var detailSeen: [Int] = []
    private var textureAge: [Int] = []
    private var core: [Bool] = []
    private(set) var mask: [Bool] = []
    private var framesSinceGrouping = 0
    private var inside: [Bool] = []
    private var insideCount = 0
    private var insideArea: NormRect?

    mutating func apply(to grid: inout ScreenSampler.Grid, area: NormRect) {
        if grid.columns != columns || grid.rows != rows {
            self = OverlayTracker()
            columns = grid.columns
            rows = grid.rows
            template = grid.cells.map { ($0.okL, $0.okA, $0.okB) }
            peakTemplate = grid.cells.map(\.brightestColor)
            textureTemplate = grid.cells.map(\.samples)
            still = [Int](repeating: 0, count: grid.cells.count)
            detailed = [Bool](repeating: false, count: grid.cells.count)
            textureAge = still
            detailSeen = still
            core = [Bool](repeating: false, count: grid.cells.count)
            mask = core
            return
        }
        if area != insideArea { scope(to: area, grid) }
        learn(grid)
        framesSinceGrouping += 1
        if framesSinceGrouping >= Self.groupingInterval {
            framesSinceGrouping = 0
            group()
        }
        guard core.contains(true) else {
            mask = core
            return
        }
        dilate()
        inpaint(&grid)
    }

    private mutating func scope(to area: NormRect, _ grid: ScreenSampler.Grid) {
        insideArea = area
        let was = inside
        inside = (0..<(columns * rows)).map { i in
            area.contains(
                x: (Double(i % columns) + 0.5) / Double(columns), y: (Double(i / columns) + 0.5) / Double(rows))
        }
        insideCount = inside.count { $0 }
        for i in inside.indices where !inside[i] || !(was.indices.contains(i) && was[i]) {
            still[i] = 0
            core[i] = false
            detailSeen[i] = 0
            detailed[i] = false
            textureAge[i] = 0
            let c = grid.cells[i]
            template[i] = (c.okL, c.okA, c.okB)
            peakTemplate[i] = c.brightestColor
            textureTemplate[i] = c.samples
        }
    }

    private func forEachNeighbor(of i: Int, _ body: (Int) -> Void) {
        let x = i % columns, y = i / columns
        if x > 0 { body(i - 1) }
        if x < columns - 1 { body(i + 1) }
        if y > 0 { body(i - columns) }
        if y < rows - 1 { body(i + columns) }
    }

    private mutating func learn(_ grid: ScreenSampler.Grid) {
        var isStill = [Bool](repeating: false, count: grid.cells.count)
        var isText = isStill
        var moving = 0
        for (i, c) in grid.cells.enumerated() where inside[i] {
            let t = template[i]
            let d = ((c.okL - t.0) * (c.okL - t.0) + (c.okA - t.1) * (c.okA - t.1) + (c.okB - t.2) * (c.okB - t.2))
                .squareRoot()
            let meanHolds = d <= Self.stillDistance
            let textureHolds = c.samples.matches(textureTemplate[i], within: Self.stillChannel)
            let peakHolds =
                c.brightest >= Self.brightPeak
                && c.brightestColor.matches(
                    peakTemplate[i],
                    within: peakTemplate[i].isNeutral(spread: Self.neutralSpread) ? Self.textChannel : Self.stillChannel
                )
            if !meanHolds {
                moving += 1  // only the mean, not texture: film grain alone moves texture
                template[i] = (c.okL, c.okA, c.okB)
            }
            if textureHolds {
                textureAge[i] = min(textureAge[i] + 1, Self.stableFrames)
            } else {
                textureTemplate[i] = c.samples
                textureAge[i] = 0
            }
            if !peakHolds { peakTemplate[i] = c.brightestColor }
            isStill[i] =
                !c.samples.isClipped(dark: Self.clippedLevels.dark, light: Self.clippedLevels.light)
                && ((meanHolds && textureHolds) || peakHolds)
            isText[i] = isStill[i] && peakHolds && !meanHolds
            if !isStill[i] {
                still[i] = 0
                core[i] = false
            }
        }
        findDetail(grid, isStill: isStill, isText: isText)
        let share = Double(moving) / Double(max(insideCount, 1))
        guard share >= Self.movingShare else { return }
        let evidence = share >= Self.cutShare ? Self.cutEvidence : 1
        for i in still.indices where isStill[i] { still[i] = min(still[i] + evidence, Self.stableFrames) }
    }

    private mutating func findDetail(_ grid: ScreenSampler.Grid, isStill: [Bool], isText: [Bool]) {
        for i in detailed.indices {
            detailed[i] = detailSeen[i] >= Self.detailFrames
            guard isStill[i] else {
                detailSeen[i] = 0
                detailed[i] = false
                continue
            }
            let c = grid.cells[i]
            let level = c.samples.mean
            let flat = !isText[i] && c.samples.spread < Self.detailSpread
            if !isText[i], !flat {
                if textureAge[i] >= Self.stableFrames { see(i, frames: Self.detailFrames) }
                continue
            }
            let bright = c.brightestColor.luma
            var contrast = false, patchEdge = false, enclosed = true
            forEachNeighbor(of: i) { n in
                if inside[n], !isStill[n] { enclosed = false }
                guard inside[n], isStill[n], !isText[n] else { return }
                let other = grid.cells[n].samples
                if flat, textureAge[n] >= Self.stableFrames, abs(other.mean - level) >= Self.detailSpread {
                    contrast = true
                }
                if isText[i], other.spread < Self.detailSpread, abs(other.mean - bright) <= Self.patchEdgeLevels {
                    patchEdge = true
                }
            }
            if isText[i] ? !patchEdge || enclosed : contrast { see(i) }
        }
    }

    private mutating func see(_ i: Int, frames: Int = 1) {
        detailSeen[i] = min(detailSeen[i] + frames, Self.detailFrames)
        detailed[i] = detailSeen[i] >= Self.detailFrames
    }

    private mutating func group() {
        let count = columns * rows
        var seen = [Bool](repeating: false, count: count)
        var next = [Bool](repeating: false, count: count)
        var total = 0
        for start in 0..<count where inside[start] && !seen[start] && still[start] >= Self.stableFrames {
            var component: [Int] = []
            var stack = [start]
            seen[start] = true
            while let i = stack.popLast() {
                component.append(i)
                forEachNeighbor(of: i) { n in
                    if inside[n], !seen[n], still[n] >= Self.stableFrames {
                        seen[n] = true
                        stack.append(n)
                    }
                }
            }
            guard Double(component.count) <= Self.maxComponentShare * Double(insideCount),
                Double(component.count { detailed[$0] }) >= Self.minDetailShare * Double(component.count)
            else { continue }
            total += component.count
            for i in component { next[i] = true }
        }
        core = Double(total) <= Self.maxTotalShare * Double(insideCount) ? next : [Bool](repeating: false, count: count)
    }

    private mutating func dilate() {
        mask = core
        for i in core.indices where core[i] {
            forEachNeighbor(of: i) { n in
                if inside[n] { mask[n] = true }
            }
        }
    }

    private func inpaint(_ grid: inout ScreenSampler.Grid) {
        var pending = mask
        var changed = true
        while changed {
            changed = false
            let snapshot = pending
            for i in pending.indices where snapshot[i] {
                var r = 0.0, g = 0.0, b = 0.0, peak = 0.0, n = 0.0
                forEachNeighbor(of: i) { j in
                    guard inside[j], !snapshot[j] else { return }
                    let c = grid.cells[j]
                    r += c.lr
                    g += c.lg
                    b += c.lb
                    peak += c.peak
                    n += 1
                }
                guard n > 0 else { continue }
                grid.cells[i] = ScreenSampler.Grid.Cell(lr: r / n, lg: g / n, lb: b / n, peak: peak / n)
                pending[i] = false
                changed = true
            }
        }
    }
}
