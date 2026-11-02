import Foundation
import simd

/// Crochet gauge: how big one single crochet is.
struct Gauge: Equatable {
    var stitchesPer10cm: Double = 20
    var roundsPer10cm: Double = 20
    /// Width of one stitch, cm.
    var w: Double { 10 / max(stitchesPer10cm, 1) }
    /// Height of one round, cm.
    var h: Double { 10 / max(roundsPer10cm, 1) }
}

/// The outline of a round shape, from the bottom pole to the top pole, as (radius, height)
/// points in cm. Spinning it around the vertical axis gives the solid.
struct Profile: Equatable {
    var points: [SIMD2<Double>]   // x = radius, y = height

    var height: Double { (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0) }
    var maxRadius: Double { points.map(\.x).max() ?? 0 }

    var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + simd_distance($1.0, $1.1) }
    }

    /// Radius at arc length `s` from the bottom pole.
    func radius(at s: Double) -> Double {
        var walked = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let d = simd_distance(a, b)
            if walked + d >= s, d > 0 {
                let t = (s - walked) / d
                return a.x + (b.x - a.x) * t
            }
            walked += d
        }
        return points.last?.x ?? 0
    }

    func scaled(by f: Double) -> Profile { Profile(points: points.map { $0 * f }) }
}

// MARK: - Built-in shapes

enum ShapePrimitive: String, CaseIterable, Identifiable {
    case ball = "Ball", egg = "Egg", pear = "Pear", capsule = "Bean", cylinder = "Cylinder", cone = "Cone"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ball: return "circle.fill"
        case .egg: return "oval.portrait.fill"
        case .pear: return "drop.fill"
        case .capsule: return "capsule.portrait.fill"
        case .cylinder: return "cylinder.fill"
        case .cone: return "cone.fill"
        }
    }

    /// `width` is the widest diameter, `height` the total height, both cm.
    func profile(width: Double, height: Double) -> Profile {
        let R = width / 2, H = height
        let n = 120
        func revolve(_ r: (Double) -> Double) -> Profile {
            Profile(points: (0...n).map { i in
                let t = Double.pi * Double(i) / Double(n)
                return SIMD2(max(0, r(t)), H / 2 * (1 - cos(t)))
            })
        }
        switch self {
        case .ball:
            return revolve { R * sin($0) }
        case .egg:
            // Fuller at the bottom, narrower at the top.
            return revolve { R * sin($0) * (1 + 0.18 * cos($0)) / 1.04 }
        case .pear:
            return revolve { t in
                let up = (1 - cos(t)) / 2          // 0 at the bottom, 1 at the top
                return R * sin(t) * (1.08 - 0.55 * pow(up, 1.6))
            }
        case .capsule:
            let r = min(R, H / 2)
            let straight = max(0, H - 2 * r)
            var pts: [SIMD2<Double>] = []
            for i in 0...40 { let a = Double.pi / 2 * Double(i) / 40; pts.append(SIMD2(r * sin(a), r * (1 - cos(a)))) }
            pts.append(SIMD2(r, r + straight))
            for i in 1...40 { let a = Double.pi / 2 * Double(i) / 40; pts.append(SIMD2(r * cos(a), r + straight + r * sin(a))) }
            return Profile(points: pts)
        case .cylinder:
            return Profile(points: [SIMD2(0, 0), SIMD2(R, 0), SIMD2(R, H), SIMD2(0, H)])
        case .cone:
            return Profile(points: [SIMD2(0, 0), SIMD2(R, 0), SIMD2(0, H)])
        }
    }
}

// MARK: - Shape → pattern

struct GeneratedPattern: Equatable {
    var counts: [Int]
    var rows: [String]
}

enum ShapeToPattern {
    /// Stitch count for every round of a single-crochet spiral that follows `profile`.
    static func counts(for profile: Profile, gauge: Gauge) -> [Int] {
        let L = profile.length
        guard L > 0 else { return [] }
        let n = max(2, Int((L / gauge.h).rounded()))
        let step = L / Double(n)
        var counts: [Int] = []
        for i in 0..<n {
            let r = profile.radius(at: (Double(i) + 0.5) * step)
            let target = 2 * Double.pi * r / gauge.w
            guard let prev = counts.last else { counts.append(6); continue }
            if abs(target - Double(prev)) < 0.75 { counts.append(prev); continue }
            let lo = max(6, Int((Double(prev) / 2).rounded(.up)))
            counts.append(min(max(Int(target.rounded()), lo), prev * 2))
        }
        // Close the top: halve until 6 are left (a couple of rounds at most).
        var guardCount = 0
        while let last = counts.last, last > 6, last <= 24, guardCount < 3 {
            counts.append(max(6, last / 2 + last % 2))
            guardCount += 1
        }
        return counts
    }

    static func pattern(for counts: [Int]) -> GeneratedPattern {
        guard let first = counts.first else { return GeneratedPattern(counts: [], rows: []) }
        var rows: [String] = ["R1: \(first) sc in a magic ring. (\(first))"]
        let peak = counts.max() ?? first
        let peakIndex = counts.firstIndex(of: peak) ?? 0
        var stuffed = false
        var i = 1
        while i < counts.count {
            let prev = counts[i - 1], c = counts[i]
            if !stuffed, i > peakIndex, c < peak / 2, peak >= 18 {
                rows.append("Stuff firmly, and keep adding stuffing as you go.")
                stuffed = true
            }
            if c == prev {
                // Group straight rounds: "R6–10: Sc in every stitch. (30)"
                var j = i
                while j + 1 < counts.count, counts[j + 1] == c { j += 1 }
                let label = j > i ? "R\(i + 1)–\(j + 1)" : "R\(i + 1)"
                rows.append("\(label): Sc in every stitch. (\(c))")
                i = j + 1
                continue
            }
            let how = EvenlyCalculator.instructions(stitches: prev, change: c - prev, craft: .crochet) ?? "Sc in every stitch"
            rows.append("R\(i + 1): \(how). (\(c))")
            i += 1
        }
        if let last = counts.last, last <= 12 {
            rows.append("Fasten off, leaving a tail. Weave it through the front loops of the last round, pull tight and hide the end inside.")
        } else {
            rows.append("Fasten off, leaving a long tail to sew this piece on.")
        }
        return GeneratedPattern(counts: counts, rows: rows)
    }
}

// MARK: - Pattern → shape

enum PatternToShape {
    private static func regex(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }
    private static let label = regex(#"^\s*(?:rnds?|rounds?|rows?|r)\s*(\d+)(?:\s*(?:[-–—]|to)\s*(?:r|rnd|round|row)?\s*(\d+))?\b"#)
    private static let trailingCount = regex(#"[\(\[]\s*(\d+)\s*(?:sts?|stitches|sc)?\s*[\)\]]\s*\.?\s*$"#)
    private static let ring = regex(#"(\d+)\s*sc\s*(?:in|into)\s*(?:a|the)?\s*(?:magic|mr|ring|adjustable)"#)
    private static let repeatGroup = regex(#"[\*\(]\s*(?:sc\s*(\d+)\s*,\s*)?(inc|dec)\s*[\*\)]\s*(?:x\s*)?(\d+)"#)
    private static let countedShaping = regex(#"\b(inc|dec)\s*(?:x\s*)?(\d+)\b|\b(\d+)\s*(inc|dec)\b"#)

    /// Stitch count of every round, if the rows look like a round-by-round (amigurumi) pattern.
    static func roundCounts(from rows: [String]) -> [Int]? {
        var counts: [Int] = []
        for line in rows {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let m = label.firstMatch(in: line, range: range) else { continue }
            let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let b = m.range(at: 2).location != NSNotFound ? (Int(ns.substring(with: m.range(at: 2))) ?? a) : a
            let times = max(1, min(200, b - a + 1))
            guard let c = count(of: line, prev: counts.last), c > 0, c < 2000 else { continue }
            counts.append(contentsOf: Array(repeating: c, count: times))
        }
        guard counts.count >= 3, let first = counts.first, first <= 12 else { return nil }
        return counts
    }

    private static func count(of line: String, prev: Int?) -> Int? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let m = trailingCount.firstMatch(in: line, range: range) {
            return Int(ns.substring(with: m.range(at: 1)))
        }
        if let m = ring.firstMatch(in: line, range: range) {
            return Int(ns.substring(with: m.range(at: 1)))
        }
        guard let prev else { return nil }
        let lower = line.lowercased()
        let groups = repeatGroup.matches(in: line, range: range)
        if !groups.isEmpty {
            var c = prev
            for g in groups {
                let n = Int(ns.substring(with: g.range(at: 3))) ?? 0
                c += ns.substring(with: g.range(at: 2)).lowercased() == "inc" ? n : -n
            }
            return c
        }
        let everywhere = lower.contains("every") || lower.contains("each") || lower.contains("around") || lower.contains("all ")
        if lower.contains("inc"), everywhere { return prev * 2 }
        if lower.contains("dec"), everywhere { return max(1, prev / 2) }
        if let m = countedShaping.firstMatch(in: line, range: range) {
            let word = (m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range(at: 4))).lowercased()
            let num = Int(m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ns.substring(with: m.range(at: 3))) ?? 0
            return word == "inc" ? prev + num : prev - num
        }
        if lower.contains("sc"), everywhere { return prev }
        return nil
    }
}

// MARK: - What the crocheted piece will look like

/// One band per round: from the edge of the previous round to the edge of this one.
struct StitchModel: Equatable {
    struct Band: Equatable {
        var bottom: SIMD2<Double>   // (radius, height)
        var top: SIMD2<Double>
        var stitches: Int
    }
    var bands: [Band]

    var height: Double { bands.map { max($0.top.y, $0.bottom.y) }.max() ?? 0 }
    var maxRadius: Double { bands.map { max($0.top.x, $0.bottom.x) }.max() ?? 0 }
    var totalStitches: Int { bands.dropLast(closedTop ? 1 : 0).reduce(0) { $0 + $1.stitches } }
    var closedTop = false

    /// Each round's circumference sets its radius; each round adds one row height along the
    /// surface, so increases flatten it out and decreases pull it in, like real fabric.
    static func from(counts: [Int], gauge: Gauge) -> StitchModel {
        var bands: [Band] = []
        var p = SIMD2<Double>(0, 0)
        for c in counts {
            let r = Double(c) * gauge.w / (2 * Double.pi)
            let dr = r - p.x
            let ds = max(gauge.h, abs(dr))
            let dz = sqrt(max(0, ds * ds - dr * dr))
            let next = SIMD2(r, p.y + dz)
            bands.append(Band(bottom: p, top: next, stitches: c))
            p = next
        }
        var model = StitchModel(bands: bands)
        if let last = counts.last, last <= 8 {
            model.bands.append(Band(bottom: p, top: SIMD2(0, p.y + gauge.h * 0.3), stitches: last))
            model.closedTop = true
        }
        return model
    }
}
