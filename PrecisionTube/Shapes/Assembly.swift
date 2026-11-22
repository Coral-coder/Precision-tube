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

    static func build(pieces: [PatternToShape.Piece], gauge: Gauge, flip: Bool? = nil) -> Assembly {
        guard !pieces.isEmpty else { return Assembly(parts: [], colorCount: 1, mainTopDown: false) }
        let models = pieces.map {
            // Stuffed pieces round out; sewn-on pieces (ears, arms) stay flatter.
            StitchModel.from(counts: $0.counts, gauge: gauge, heights: $0.heights, colors: $0.colors,
                             collars: $0.collars, puff: $0.attach == nil ? 0.6 : 0.3)
        }
        let main = pieces.indices.max { pieces[$0].counts.reduce(0, +) < pieces[$1].counts.reduce(0, +) } ?? 0
        let topDown = flip ?? pieces[main].topDown
        let mainModel = models[main]
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
        for j in pieces.indices where j != main {
            let model = models[j]
            let h = Float(model.height)
            let copies = max(1, pieces[j].repeatCount)
            if let attach = pieces[j].attach, attach.target == main {
                let a = surface(attach.rounds.lowerBound), b = surface(attach.rounds.upperBound)
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
            } else {
                // Not sewn anywhere we can tell: stand it beside the main piece.
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
        if let e = pieces[main].eyes {
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
        let colors = (pieces.flatMap(\.colors).max() ?? 0) + 1
        return Assembly(parts: parts, eyes: eyes, colorCount: colors, mainTopDown: topDown)
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> Mat4 { .translation(x, y, z) }
    private static func rotation(_ angle: Float, axis: SIMD3<Float>) -> Mat4 { .rotation(angle, axis: axis) }
    private static func scale(_ x: Float, _ y: Float, _ z: Float) -> Mat4 { .scale(x, y, z) }
}
