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
    /// One crocheted piece in a pattern (a head, a body…), with each round's stitch count.
    struct Piece: Identifiable, Equatable {
        var id: Int
        var name: String
        var counts: [Int]
    }

    private static func regex(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }
    private static let roundWord = #"(?:rnds?|rounds?|rows?|rds?|r)"#
    /// "R1", "Rnd 6-10", "Round 3 to 5"
    private static let label = regex(#"^\s*"# + roundWord + #"\s*\.?\s*(\d+)(?:\s*(?:[-–—~]|to|thru|through)\s*"# + roundWord + #"?\s*\.?\s*(\d+))?(?![a-z])"#)
    /// "1.", "5-10:", "3)"
    private static let numbered = regex(#"^\s*(\d+)(?:\s*[-–—~]\s*(\d+))?\s*[\.\):]"#)
    /// Several rounds pasted on one line: split before each "R2:" / "Rnd 3." inside it.
    private static let inlineSplit = regex(#"(?<=[\.\)\]\}\s])(?=(?:rnds?|rounds?|r)\s?\d+(?:\s*[-–—]\s*\d+)?\s*[:\.\)\(])"#)
    private static let afterLabel = regex(#"^\s*[\(\[\{]\s*(\d+)\s*(?:sts?|stitches|sc)?\s*[\)\]\}]"#)
    private static let bracketCount = regex(#"[\(\[\{]\s*(\d+)\s*(?:sts?\.?|stitches|sc)?\s*(?:total|in total)?\s*[\)\]\}]"#)
    private static let dashCount = regex(#"(?:[-–—=:]|=>|→)\s*(\d+)\s*(?:sts?|stitches|sc)?\s*\.?\s*$"#)
    private static let stsCount = regex(#"(\d+)\s*(?:sts|stitches)\s*\.?\s*$"#)
    private static let ring = regex(#"(\d+)\s*(?:sc|dc|x)\s*(?:in|into)?\s*(?:a|the|an)?\s*(?:magic|mr|mc|ring|adjustable)"#)
    private static let ringAfter = regex(#"(?:magic ring|magic circle|mr|mc)\D{0,12}?(\d+)"#)
    private static let repeatGroup = regex(#"[\*\(\[]\s*(?:(?:sc|dc)\s*(\d+)|(\d+)\s*(?:sc|dc))?\s*,?\s*(inc|dec|sc2tog|invdec)\s*[\*\)\]]\s*(?:x|times|\*)?\s*(\d+)"#)
    private static let countedShaping = regex(#"\b(inc|dec|sc2tog|invdec)\s*(?:x\s*)?(\d+)\b|\b(\d+)\s*(inc|dec|sc2tog|invdec)\b"#)

    /// The stitch counts of the first round-by-round piece, if there is one.
    static func roundCounts(from rows: [String]) -> [Int]? { pieces(from: rows).first?.counts }

    /// Every round-by-round piece in the pattern. Round numbers starting over (R1 again)
    /// begin a new piece, named after the short heading line above it ("HEAD", "Body:").
    static func pieces(from rows: [String]) -> [Piece] {
        var out: [Piece] = []
        var current: [Int] = []
        var name: String?
        var lastNumber = 0
        var lastHeading: String?

        func close() {
            guard current.count >= 3, let first = current.first, first <= 24 else { return }
            var title = name ?? "Piece \(out.count + 1)"
            if out.contains(where: { $0.name == title }) { title += " \(out.count + 1)" }
            out.append(Piece(id: out.count, name: title, counts: current))
        }

        for line in split(rows) {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let m = label.firstMatch(in: line, range: range) ?? numbered.firstMatch(in: line, range: range) else {
                let heading = line.trimmingCharacters(in: CharacterSet(charactersIn: " :-*#\t"))
                if !heading.isEmpty, heading.count < 40 { lastHeading = heading }
                continue
            }
            let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let b = m.range(at: 2).location != NSNotFound ? (Int(ns.substring(with: m.range(at: 2))) ?? a) : a
            if !current.isEmpty, a <= lastNumber {
                close()
                current = []
            }
            if current.isEmpty { name = lastHeading }
            let rest = ns.substring(from: m.range.location + m.range.length)
            guard let c = count(rest: rest, line: line, prev: current.last), c > 0, c < 2000 else { continue }
            current.append(contentsOf: Array(repeating: c, count: max(1, min(200, b - a + 1))))
            lastNumber = max(a, b)
        }
        close()
        return out
    }

    private static func split(_ rows: [String]) -> [String] {
        var out: [String] = []
        for row in rows {
            let ns = row as NSString
            var start = 0
            for m in inlineSplit.matches(in: row, range: NSRange(location: 0, length: ns.length)) {
                let piece = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                out.append(piece)
                start = m.range.location
            }
            out.append(ns.substring(from: start))
        }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in ns: NSString) -> String? {
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }

    private static func count(rest: String, line: String, prev: Int?) -> Int? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        let restNS = rest as NSString
        if let m = afterLabel.firstMatch(in: rest, range: NSRange(location: 0, length: restNS.length)) {
            return Int(restNS.substring(with: m.range(at: 1)))
        }
        if let m = bracketCount.matches(in: line, range: range).last { return Int(ns.substring(with: m.range(at: 1))) }
        if let m = dashCount.firstMatch(in: line, range: range) ?? stsCount.firstMatch(in: line, range: range) {
            return Int(ns.substring(with: m.range(at: 1)))
        }
        if let m = ring.firstMatch(in: line, range: range) ?? (prev == nil ? ringAfter.firstMatch(in: line, range: range) : nil) {
            return Int(ns.substring(with: m.range(at: 1)))
        }
        guard let prev else { return nil }
        let lower = line.lowercased()
        let groups = repeatGroup.matches(in: line, range: range)
        if !groups.isEmpty {
            var c = prev
            for g in groups {
                let n = Int(group(g, 4, in: ns) ?? "0") ?? 0
                c += (group(g, 3, in: ns) ?? "").lowercased() == "inc" ? n : -n
            }
            return c
        }
        let everywhere = lower.contains("every") || lower.contains("each") || lower.contains("around") || lower.contains("all ")
        if lower.contains("inc"), everywhere { return prev * 2 }
        if lower.contains("dec") || lower.contains("sc2tog"), everywhere { return max(1, prev / 2) }
        if let m = countedShaping.firstMatch(in: line, range: range) {
            let word = (group(m, 1, in: ns) ?? group(m, 4, in: ns) ?? "").lowercased()
            let n = Int(group(m, 2, in: ns) ?? group(m, 3, in: ns) ?? "0") ?? 0
            return word == "inc" ? prev + n : prev - n
        }
        if lower.contains("sc") || lower.contains("dc"), everywhere { return prev }
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
