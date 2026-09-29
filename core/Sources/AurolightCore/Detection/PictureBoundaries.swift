struct PictureBoundaries {
    typealias Box = PictureRegionDetector.Box
    typealias Detector = PictureRegionDetector

    let pixels: UnsafePointer<UInt8>
    let width: Int, height: Int, bytesPerRow: Int

    private static let gap = 2
    private static let reach = 0.25

    func snap(_ box: Box) -> Box? {
        var b = box
        // Twice: each edge samples surroundings past the others, which may move in the first pass.
        for _ in 0..<2 {
            guard let snapped = snapOnce(b) else { return nil }
            b = snapped
        }
        return b
    }

    private func snapOnce(_ box: Box) -> Box? {
        let gap = Self.gap
        let reachX = Int(Self.reach * Double(width)), reachY = Int(Self.reach * Double(height))
        var b = box
        if b.y0 > gap {
            let columns = stride(from: b.x0, to: b.x1, by: 3)
            guard
                let y = nearest(
                    b.y0, inward: 1, reach: reachY, within: gap...(height - gap - 1),
                    { y in
                        isEdge(
                            along: columns, outside: { ($0, y - gap) }, inside: { ($0, min(y + 1, height - 1)) },
                            references: [
                                (b.x0 - 3, y - gap), (b.x0 - 6, y - gap), (b.x1 + 2, y - gap), (b.x1 + 5, y - gap),
                            ])
                    })
            else { return nil }
            b.y0 = y
        }
        if b.y1 < height - gap {
            let columns = stride(from: b.x0, to: b.x1, by: 3), row = { (y: Int) in y + gap - 1 }
            guard
                let y = nearest(
                    b.y1, inward: -1, reach: reachY, within: (gap + 1)...(height - gap),
                    { y in
                        isEdge(
                            along: columns, outside: { ($0, row(y)) }, inside: { ($0, max(y - 2, 0)) },
                            references: [
                                (b.x0 - 3, row(y)), (b.x0 - 6, row(y)), (b.x1 + 2, row(y)), (b.x1 + 5, row(y)),
                            ])
                    })
            else { return nil }
            b.y1 = y
        }
        if b.x0 > gap {
            let rows = stride(from: b.y0, to: b.y1, by: 3)
            guard
                let x = nearest(
                    b.x0, inward: 1, reach: reachX, within: gap...(width - gap - 1),
                    { x in
                        isEdge(
                            along: rows, outside: { (x - gap, $0) }, inside: { (min(x + 1, width - 1), $0) },
                            references: [
                                (x - gap, b.y0 - 3), (x - gap, b.y0 - 6), (x - gap, b.y1 + 2), (x - gap, b.y1 + 5),
                            ])
                    })
            else { return nil }
            b.x0 = x
        }
        if b.x1 < width - gap {
            let rows = stride(from: b.y0, to: b.y1, by: 3), column = { (x: Int) in x + gap - 1 }
            guard
                let x = nearest(
                    b.x1, inward: -1, reach: reachX, within: (gap + 1)...(width - gap),
                    { x in
                        isEdge(
                            along: rows, outside: { (column(x), $0) }, inside: { (max(x - 2, 0), $0) },
                            references: [
                                (column(x), b.y0 - 3), (column(x), b.y0 - 6), (column(x), b.y1 + 2),
                                (column(x), b.y1 + 5),
                            ])
                    })
            else { return nil }
            b.x1 = x
        }
        return b
    }

    private func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let p = pixels + y * bytesPerRow + x * 4
        return (Int(p[0]), Int(p[1]), Int(p[2]))
    }

    private func similar(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2)) <= Detector.boundaryContrast
    }

    private func isEdge(
        along positions: StrideTo<Int>, outside: (Int) -> (Int, Int), inside: (Int) -> (Int, Int),
        references: [(Int, Int)]
    ) -> Bool {
        let surroundings = references.filter { $0.0 >= 0 && $0.0 < width && $0.1 >= 0 && $0.1 < height }
            .map { pixel($0.0, $0.1) }
        var contrast = 0, continuous = 0, total = 0
        for i in positions {
            let o = outside(i), n = inside(i)
            let out = pixel(o.0, o.1)
            if !similar(out, pixel(n.0, n.1)) { contrast += 1 }
            let black = max(out.0, out.1, out.2) <= Detector.blackLevel
            if black || surroundings.isEmpty || surroundings.contains(where: { similar($0, out) }) { continuous += 1 }
            total += 1
        }
        guard total > 0 else { return false }
        return Double(contrast) >= Detector.boundaryShare * Double(total)
            && Double(continuous) >= Detector.continuityShare * Double(total)
    }

    private func nearest(
        _ start: Int, inward: Int, reach: Int, within range: ClosedRange<Int>, _ valid: (Int) -> Bool
    ) -> Int? {
        for d in 0...reach {
            for p in d == 0 ? [start] : [start + inward * d, start - inward * d]
            where range.contains(p) && (d <= 2 * Detector.step || p == start - inward * d) && valid(p) {
                return p
            }
        }
        return nil
    }
}
