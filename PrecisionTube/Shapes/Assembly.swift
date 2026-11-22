import Foundation

/// A whole amigurumi put together: the biggest piece in the middle, pieces that are sewn on
/// ("Sew on ears between rounds 4 & 6 of head") placed there, the rest set beside it.
struct Assembly: Equatable {
    struct Part: Equatable {
        var model: StitchModel
        var transform: Mat4
    }
    var parts: [Part]
    /// Safety eyes.
    var eyes: [Eye] = []
    struct Eye: Equatable { var center: SIMD3<Float>; var radius: Float }
    /// How many yarn colours the pattern uses.
    var colorCount: Int
    /// Whether the main piece is drawn magic ring up.
    var mainTopDown: Bool

    /// - Parameters:
    ///   - lineVisible: which pattern lines count as done (nil = all). Rounds show up to the first
    ///     line that isn't; collars, eyes and sewing show once their line is.
    ///   - highlightLine: the round(s) from this line glow (the one being written, or worked next)
    ///     and are shown even if not done yet.
    static func build(pieces allPieces: [PatternToShape.Piece], gauge: Gauge, flip: Bool? = nil,
                      lineVisible: ((Int) -> Bool)? = nil, highlightLine: Int? = nil) -> Assembly {
        let visible: (Int) -> Bool = { line in lineVisible?(line) ?? true || line == highlightLine }
        // Only the rounds made so far.
        var pieces: [PatternToShape.Piece] = []
        var originalIndex: [Int] = []
        for (i, var piece) in allPieces.enumerated() {
            var n = 0
            while n < piece.counts.count, n >= piece.lines.count || visible(piece.lines[n]) { n += 1 }
            if lineVisible == nil && highlightLine == nil { n = piece.counts.count }
            guard n > 0 else { continue }
            if n < piece.counts.count {
                piece.counts = Array(piece.counts.prefix(n))
                piece.heights = Array(piece.heights.prefix(n))
                piece.lines = Array(piece.lines.prefix(n))
                // Not finished, so don't close it up.
            }
            var colors = Array(piece.colors.prefix(n))
            if let h = highlightLine {
                for r in 0..<min(n, piece.lines.count) where piece.lines[r] == h { colors[r] = -2 }
            }
            piece.colors = colors
            piece.collars = piece.collars.filter { visible($0.line) && $0.round <= n }
            if let a = piece.attach, !visible(a.line) { piece.attach = nil }
            if let e = piece.eyes, n < e.rounds.lowerBound { piece.eyes = nil }
            pieces.append(piece)
            originalIndex.append(i)
        }
        guard !pieces.isEmpty else { return Assembly(parts: [], colorCount: 1, mainTopDown: false) }

        let models = pieces.indices.map { k -> StitchModel in
            let p = pieces[k]
            // A piece still being made stays open; stuffed pieces round out, sewn-on ones stay flatter.
            let complete = p.counts.count == allPieces[originalIndex[k]].counts.count
            return StitchModel.from(counts: p.counts, gauge: gauge, heights: p.heights, colors: p.colors,
                                    collars: p.collars, puff: p.attach == nil ? 0.6 : 0.3, closeEnd: complete)
        }
        let mainLocal = pieces.indices.max { pieces[$0].counts.reduce(0, +) < pieces[$1].counts.reduce(0, +) } ?? 0
        let main = originalIndex[mainLocal]
        let topDown = flip ?? pieces[mainLocal].topDown
        let mainModel = models[mainLocal]
        let H = Float(mainModel.height)

        var parts: [Part] = []
        // Magic ring up: turn it over (rotate half a turn about x) and lift it back above the floor.
        let mainTransform = topDown ? translation(0, H, 0) * rotation(.pi, axis: SIMD3(1, 0, 0)) : Mat4.identity
        parts.append(Part(model: mainModel, transform: mainTransform))

        /// Where round n of the main piece is: (radius, height above the floor).
        func surface(_ round: Int) -> (r: Float, y: Float) {
            let i = min(max(round, 1), mainModel.roundCount) - 1
            guard i >= 0, i < mainModel.bands.count else { return (Float(mainModel.maxRadius), H / 2) }
            let edge = mainModel.bands[i].top
            return (Float(edge.x), topDown ? H - Float(edge.y) : Float(edge.y))
        }

        var besideX = Float(mainModel.maxRadius) * 1.5
        for j in pieces.indices where j != mainLocal {
            let model = models[j]
            let h = Float(model.height)
            let copies = max(1, pieces[j].repeatCount)
            if let attach = pieces[j].attach, attach.target == main {
                switch attach.place {
                case .top, .bottom:
                    // A hat or a base: worn over the top (magic ring up) or under the bottom.
                    if attach.place == .top {
                        let lift = Float(gauge.h) * 0.4
                        parts.append(Part(model: model, transform: translation(0, H + lift, 0) * rotation(.pi, axis: SIMD3(1, 0, 0))))
                    } else {
                        parts.append(Part(model: model, transform: translation(0, -Float(gauge.h) * 0.4, 0)))
                    }
                case .between:
                    let rounds = attach.rounds ?? (mainModel.roundCount / 2)...(mainModel.roundCount / 2)
                    let a = surface(rounds.lowerBound), b = surface(rounds.upperBound)
                    let r = max(a.r, b.r) * 0.85
                    let y = (a.y + b.y) / 2
                    // Small sewn-on pieces aren't stuffed: pressed flat, a tube is as wide as half its
                    // circumference (π/2 × its round width) and thin.
                    let flat = scale(1.45, 1, 0.25)
                    if copies >= 2 {
                        // A pair, one on each side. A flattened piece is sewn on along its edge, so its
                        // flat width sticks out sideways (tilted up a little) and its rounds run up and down.
                        let tilt: Float = 0.25
                        let halfWidth = Float(model.maxRadius) * 1.45
                        let out = r + halfWidth * 0.8
                        parts.append(Part(model: model, transform: translation(out, y - h / 2, 0) * rotation(tilt, axis: SIMD3(0, 0, 1)) * flat))
                        parts.append(Part(model: model, transform: translation(-out, y - h / 2, 0) * rotation(-tilt, axis: SIMD3(0, 0, 1)) * flat))
                    } else {
                        parts.append(Part(model: model, transform: translation(0, y, r + h) * rotation(-.pi / 2, axis: SIMD3(1, 0, 0))))
                    }
                }
            } else {
                // Not sewn on (yet): stand it beside the main piece.
                for _ in 0..<copies {
                    let radius = Float(model.maxRadius)
                    besideX += radius + 0.6
                    parts.append(Part(model: model, transform: translation(besideX, 0, 0)))
                    besideX += radius
                }
            }
        }
        // Safety eyes on the front of the main piece, the given number of stitches apart.
        var eyes: [Eye] = []
        if let e = pieces[mainLocal].eyes {
            let a = surface(e.rounds.lowerBound), b = surface(e.rounds.upperBound)
            let r = (a.r + b.r) / 2, y = (a.y + b.y) / 2
            let w = Float(gauge.w)
            let half = Float(e.apart + 1) / 2 * w
            let angle = half / max(r, 0.1)
            let size = w * 0.5
            for side: Float in [-1, 1] {
                eyes.append(Eye(center: SIMD3(side * r * sin(angle), y, r * cos(angle) + size * 0.3), radius: size))
            }
        }
        let colors = (allPieces.flatMap(\.colors).max() ?? 0) + 1
        return Assembly(parts: parts, eyes: eyes, colorCount: colors, mainTopDown: topDown)
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> Mat4 { .translation(x, y, z) }
    private static func rotation(_ angle: Float, axis: SIMD3<Float>) -> Mat4 { .rotation(angle, axis: axis) }
    private static func scale(_ x: Float, _ y: Float, _ z: Float) -> Mat4 { .scale(x, y, z) }
}
