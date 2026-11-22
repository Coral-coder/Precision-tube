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
            // How much stuffing rounds it out: none for ears and wings, some for a beak or muzzle,
            // fully for the main piece, a head, arms and legs.
            let kind = PieceKind(p.name)
            let puff: Double
            switch kind {
            case _ where p.attach == nil: puff = 0.6
            case .ear, .flat: puff = 0.3          // soft, not stuffed; flattened when placed
            case .worn:
                // A hat with sides takes the shape of the head under it; a plain circle (leaves) stays flat.
                let peak = p.counts.max() ?? 0
                puff = p.counts.filter { $0 == peak }.count >= 2 ? 0.5 : 0
            case .front, .tail: puff = 0.35
            default: puff = 0.6
            }
            // A sewn-on piece is open where it's sewn, unless it was closed up (6 stitches or fewer).
            return StitchModel.from(counts: p.counts, gauge: gauge, heights: p.heights, colors: p.colors,
                                    collars: p.collars, puff: puff, closeEnd: complete,
                                    closeAt: p.attach == nil ? 12 : 6)
        }
        let local = Dictionary(uniqueKeysWithValues: originalIndex.enumerated().map { ($1, $0) })   // original → shown
        // The main piece: not sewn to anything shown, with the most sewn onto it (then the biggest).
        let roots = pieces.indices.filter { k in pieces[k].attach.flatMap { local[$0.target] } == nil }
        let mainLocal = roots.max { a, b in
            let na = pieces.filter { $0.attach?.target == originalIndex[a] }.count
            let nb = pieces.filter { $0.attach?.target == originalIndex[b] }.count
            return na != nb ? na < nb : models[a].totalStitches < models[b].totalStitches
        } ?? 0

        // Each placed piece: its frame (position, before its own turn-over) and its orientation.
        var frames: [Int: Mat4] = [:]
        var parts: [Part] = []
        var eyes: [Eye] = []
        func orientation(_ k: Int) -> Mat4 {
            let topDown = k == mainLocal ? (flip ?? pieces[k].topDown) : pieces[k].topDown
            return topDown ? translation(0, Float(models[k].height), 0) * rotation(.pi, axis: SIMD3(1, 0, 0)) : Mat4.identity
        }
        /// Where round n of piece k is, in its upright frame: (radius, height).
        func surface(_ k: Int, _ round: Int) -> (r: Float, y: Float) {
            let m = models[k]
            let H = Float(m.height)
            let topDown = k == mainLocal ? (flip ?? pieces[k].topDown) : pieces[k].topDown
            let i = min(max(round, 1), max(1, m.roundCount)) - 1
            guard i >= 0, i < m.bands.count else { return (Float(m.maxRadius), H / 2) }
            let edge = m.bands[i].top
            return (Float(edge.x), topDown ? H - Float(edge.y) : Float(edge.y))
        }
        /// The round at a height fraction (0 = bottom, 1 = top) of piece k, as it stands.
        func round(_ k: Int, atHeight f: Float) -> Int {
            let n = max(1, models[k].roundCount)
            let H = Float(models[k].height)
            let rounds = (1...n).map { ($0, abs(surface(k, $0).y - f * H)) }
            return rounds.min { $0.1 < $1.1 }?.0 ?? n / 2
        }
        func place(_ k: Int, frame: Mat4, extra: Mat4 = .identity) {
            parts.append(Part(model: models[k], transform: frame * extra * orientation(k)))
        }

        func placeAttached(_ k: Int, on t: Int, attach: PatternToShape.Piece.Attach, frame F: Mat4) {
            let piece = pieces[k]
            let model = models[k]
            let h = Float(model.height)
            let pr = Float(model.maxRadius)
            let T = models[t]
            let TH = Float(T.height), TR = Float(T.maxRadius)
            let copies = max(1, piece.repeatCount)
            let kind = PieceKind(piece.name)
            var where_ = attach.place
            if where_ == .auto || (where_ == .between && attach.rounds == nil) { where_ = kind.defaultPlace }
            if attach.rounds != nil { where_ = .between }
            let w = Float(gauge.w)

            switch where_ {
            case .top:
                if isStuffed(piece) || kind == .head {
                    // A stuffed piece (a head on a body) sits on top, sunk in a little.
                    let G = F * translation(0, TH - h * 0.12, 0)
                    frames[k] = G
                    place(k, frame: G)
                } else {
                    // A hat, cap or leaves: worn over the top, magic ring up. It slides down until
                    // the piece under it is as wide as its opening; a cap wider than its stem rests
                    // on top, with the stem tucked up inside a little.
                    let rim = Float(model.bands[max(0, model.roundCount - 1)].top.x)
                    var rimY = TH - min(h * 0.5, TH * 0.35)
                    let n = max(1, T.roundCount)
                    let fromTop = (1...n).map { surface(t, $0) }.sorted { $0.y > $1.y }
                    if let fit = fromTop.first(where: { $0.r >= rim * 0.95 }) { rimY = min(TH, fit.y + w * 0.3) }
                    let G = F * translation(0, rimY + h, 0) * rotation(.pi, axis: SIMD3(1, 0, 0))
                    frames[k] = G
                    parts.append(Part(model: model, transform: G))
                }
            case .bottom:
                // Legs, feet, tentacles: under the piece, spread around and pointing down.
                let ring = copies == 1 ? 0 : max(TR * 0.45, pr * 1.2)
                for c in 0..<copies {
                    let a = Float(c) / Float(copies) * 2 * .pi + (copies == 2 ? .pi / 2 : 0)
                    let x = ring * sin(a), z = ring * cos(a)
                    let splay: Float = -(copies > 2 ? 0.55 : 0.12)   // feet out, away from the middle
                    let tiltAxis = SIMD3<Float>(cos(a), 0, -sin(a))
                    let G = F * translation(x, h * 0.15, z) * rotation(copies == 1 ? 0 : splay, axis: tiltAxis) * translation(0, -h, 0)
                    if c == 0 { frames[k] = G }
                    parts.append(Part(model: model, transform: G))
                }
            case .back:
                // A tail: out of the back, low down, pointing back and up a little.
                let at = surface(t, round(t, atHeight: 0.35))
                let theta: Float = .pi / 2 + 0.35
                for c in 0..<copies {
                    // A pair (tail fins) fans out to each side, flat.
                    let spread: Float = copies == 1 ? 0 : (Float(c) - Float(copies - 1) / 2) * 1.1
                    let G = F * translation(0, at.y, 0) * rotation(spread, axis: SIMD3(0, 1, 0))
                        * translation(0, -h * cos(theta), -(at.r * 0.85) - h * sin(theta)) * rotation(theta, axis: SIMD3(1, 0, 0))
                        * (kind == .flat || copies > 1 ? scale(1.45, 1, 0.3) : .identity)
                    if c == 0 { frames[k] = G }
                    parts.append(Part(model: model, transform: G))
                }
            case .front:
                let at = surface(t, round(t, atHeight: 0.55))
                let G = F * translation(0, at.y, at.r * 0.95 + h) * rotation(-.pi / 2, axis: SIMD3(1, 0, 0))
                frames[k] = G
                parts.append(Part(model: model, transform: G))
            case .sides, .between, .auto:
                let rounds = attach.rounds ?? {
                    let r = round(t, atHeight: kind == .arm ? 0.7 : 0.55)
                    return r...r
                }()
                let a = surface(t, rounds.lowerBound), b = surface(t, rounds.upperBound)
                let r = max(a.r, b.r), y = (a.y + b.y) / 2
                if copies == 1 && where_ != .sides {
                    // One piece at those rounds: on the front (a muzzle, a beak), or the back (a tail).
                    if kind == .tail {
                        let theta: Float = .pi / 2 + 0.35
                        let G = F * translation(0, y - h * cos(theta), -(r * 0.85) - h * sin(theta)) * rotation(theta, axis: SIMD3(1, 0, 0))
                        frames[k] = G
                        parts.append(Part(model: model, transform: G))
                    } else {
                        let G = F * translation(0, y, r * 0.95 + h) * rotation(-.pi / 2, axis: SIMD3(1, 0, 0))
                        frames[k] = G
                        parts.append(Part(model: model, transform: G))
                    }
                    break
                }
                let fromTop = (TH - y) / max(TH, 0.01)
                // An ear that narrows back down (6, 9, 12, 6) is a closed leaf sewn on by its edge,
                // so it sticks out sideways; one that ends open is sewn by its opening and stands up.
                let closedLeaf = Float(piece.counts.last ?? 0) < Float(piece.counts.max() ?? 0) * 0.6
                let flatWidth = pr * 1.45
                for side: Float in (copies >= 2 ? [1, -1] : [1]) {
                    var G: Mat4
                    switch kind {
                    case .arm, .flat:
                        // Arms and wings hang down the sides from the shoulder, splayed a little;
                        // wings are flat.
                        let flat = kind == .flat ? scale(0.35, 1, 1.3) : Mat4.identity
                        G = F * translation(side * (r * 0.97 + pr * 0.7), y - h * 0.92, 0)
                            * rotation(side * 0.22, axis: SIMD3(0, 0, 1)) * flat
                    case .ear where !closedLeaf && (h > flatWidth * 1.15 || fromTop < 0.28):
                        // Long ears, or ears near the top: stand up, flat face forward, magic ring up,
                        // leaning out a little.
                        G = F * translation(side * r * 0.75, y - h * 0.1, 0) * rotation(-side * 0.3, axis: SIMD3(0, 0, 1))
                            * translation(0, h, 0) * rotation(.pi, axis: SIMD3(1, 0, 0)) * scale(1.45, 1, 0.25)
                    default:
                        // Short flat pieces (ears like Grogu's): sewn on edge, sticking out sideways.
                        G = F * translation(side * (r * 0.85 + flatWidth * 0.8), y - h / 2, 0)
                            * rotation(side * 0.25, axis: SIMD3(0, 0, 1)) * scale(1.45, 1, 0.25)
                    }
                    if side == 1 { frames[k] = G }
                    parts.append(Part(model: model, transform: G))
                }
            }
        }

        // A long thin piece with nothing sewn on (a snake, a caterpillar) lies down.
        let mainModel = models[mainLocal]
        let lieDown = mainModel.height > mainModel.maxRadius * 2 * 3 && !pieces.contains { $0.attach != nil }
        let mainFrame = lieDown
            ? translation(Float(mainModel.height) / 2, Float(mainModel.maxRadius), 0) * rotation(.pi / 2, axis: SIMD3(0, 0, 1))
            : Mat4.identity
        frames[mainLocal] = mainFrame
        place(mainLocal, frame: mainFrame)

        // Place pieces whose target is placed, until nothing more can be placed.
        var pending = pieces.indices.filter { $0 != mainLocal }
        var besideX = Float(models[mainLocal].maxRadius) * 1.6
        var progress = true
        while progress {
            progress = false
            for k in pending {
                let piece = pieces[k]
                guard let attach = piece.attach, let t = local[attach.target], let F = frames[t] else { continue }
                pending.removeAll { $0 == k }
                progress = true
                placeAttached(k, on: t, attach: attach, frame: F)
            }
        }
        // Not sewn on (yet): stand them beside.
        for k in pending {
            for _ in 0..<max(1, pieces[k].repeatCount) {
                let radius = Float(models[k].maxRadius)
                besideX += radius + 0.6
                let F = translation(besideX, 0, 0)
                frames[k] = F
                place(k, frame: F)
                besideX += radius
            }
        }

        // Safety eyes on whichever piece has them, the given number of stitches apart, facing front.
        for k in pieces.indices {
            guard let e = pieces[k].eyes, let F = frames[k] else { continue }
            let a = surface(k, e.rounds.lowerBound), b = surface(k, e.rounds.upperBound)
            let r = (a.r + b.r) / 2, y = (a.y + b.y) / 2
            let w = Float(gauge.w)
            let angle = (Float(e.apart + 1) / 2 * w) / max(r, 0.1)
            let size = w * 0.5
            for side: Float in [-1, 1] {
                let p = SIMD3(side * r * sin(angle), y, r * cos(angle) + size * 0.3)
                eyes.append(Eye(center: F.point(p), radius: size))
            }
        }
        let colors = (allPieces.flatMap(\.colors).max() ?? 0) + 1
        return Assembly(parts: parts, eyes: eyes, colorCount: colors, mainTopDown: flip ?? pieces[mainLocal].topDown)
    }

    /// Closed up and (going by its name) stuffed: a head, a body, legs. Hats, leaves, collars,
    /// ears and wings aren't.
    private static func isStuffed(_ p: PatternToShape.Piece) -> Bool {
        let kind = PieceKind(p.name)
        if kind == .ear || kind == .flat || kind == .worn { return false }
        return (p.counts.last ?? 99) <= 12
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> Mat4 { .translation(x, y, z) }
    private static func rotation(_ angle: Float, axis: SIMD3<Float>) -> Mat4 { .rotation(angle, axis: axis) }
    private static func scale(_ x: Float, _ y: Float, _ z: Float) -> Mat4 { .scale(x, y, z) }
}

/// What kind of piece, going by its name, for where it goes when the pattern doesn't say.
enum PieceKind: Equatable {
    case head, arm, leg, ear, flat, tail, front, worn, other

    init(_ name: String) {
        let n = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { n.range(of: "\\b\($0)", options: .regularExpression) != nil } }
        if has(["head"]) { self = .head }
        else if has(["ear", "horn", "antenna"]) { self = .ear }
        else if has(["wing", "fin", "flipper"]) && !has(["tail"]) { self = .flat }
        else if has(["arm", "hand", "paw"]) { self = .arm }
        else if has(["leg", "feet", "foot", "tentacle", "stand"]) { self = .leg }
        else if has(["tail"]) { self = .tail }
        else if has(["beak", "nose", "muzzle", "snout", "mouth", "belly", "face"]) { self = .front }
        else if has(["hat", "cap", "hair", "leaf", "leaves", "bow", "crown", "hood", "beanie"]) { self = .worn }
        else { self = .other }
    }

    var defaultPlace: PatternToShape.Piece.Attach.Place {
        switch self {
        case .head, .worn: return .top
        case .leg: return .bottom
        case .tail: return .back
        case .front: return .front
        case .arm, .flat, .ear: return .sides
        case .other: return .front
        }
    }
}
