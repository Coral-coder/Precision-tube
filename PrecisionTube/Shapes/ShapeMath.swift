import Foundation

@inline(__always) func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
    let d = a - b
    return (d.x * d.x + d.y * d.y).squareRoot()
}

/// Crochet gauge: how big one single crochet is.
struct Gauge: Equatable {
    var stitchesPer10cm: Double = 20
    /// Crochet rounds are a little shorter than a stitch is wide.
    var roundsPer10cm: Double = 24
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
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Radius at arc length `s` from the bottom pole.
    func radius(at s: Double) -> Double {
        var walked = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let d = distance(a, b)
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
        /// Height of each round in single-crochet rows (hdc ≈ 1.4, dc ≈ 2).
        var heights: [Double] = []
        /// Yarn colour of each round: 0 = first colour, 1 = after the first colour change…
        var colors: [Int] = []
        /// "Ears x2" → made twice.
        var repeatCount = 1
        /// Rings worked into the front loops of a round ("collar").
        var collars: [Collar] = []
        /// Sewn onto another piece (between rounds, or on top).
        var attach: Attach?
        /// The pattern line each round came from (an index into the lines read).
        var lines: [Int] = []
        /// Started at the top (e.g. a head begun at the crown): drawn magic ring up.
        var topDown = false
        /// "Safety eyes between 6 & 7, 3 st apart".
        var eyes: Eyes?

        struct Eyes: Equatable { var rounds: ClosedRange<Int>; var apart: Int }

        struct Collar: Equatable { var round: Int; var count: Int?; var line: Int = 0 }
        struct Attach: Equatable {
            var target: Int
            var rounds: ClosedRange<Int>?
            var place: Place = .between
            /// The pattern line that says to sew it on.
            var line: Int = 0
            enum Place: Equatable { case between, top, bottom }
        }
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
    private static let frontLoopsOf = regex(#"front\s+loops?\s+(?:from|of|in|on)\s+(?:the\s+)?(?:rounds?|rnds?|rows?|r)\s*(\d+)"#)
    private static let aroundCount = regex(#"(?:sc\s*(\d+)|(\d+)\s*(?:sc|sts|stitches))"#)
    private static let sewBetween = regex(#"\b(?:sew|attach|pin)\b.*?(?:rounds?|rnds?|rows?|r)\s*(\d+)\s*(?:&|and|-|–|to)\s*(?:rounds?|rnds?|rows?|r)?\s*(\d+)"#)
    private static let eyesBetween = regex(#"\beyes?\b.*?between\s*(?:rounds?|rnds?|rows?|r)?\s*(\d+)\s*(?:&|and|-|–|to)\s*(?:rounds?|rnds?|rows?|r)?\s*(\d+)"#)
    private static let stitchesApart = regex(#"(\d+)\s*(?:st|sts|stitch|stitches)\s*apart"#)
    private static let tallStitch: [(NSRegularExpression, Double)] = [
        (regex(#"\btr\b"#), 2.6), (regex(#"\bdc\b"#), 2.0), (regex(#"\bhdc\b"#), 1.4),
    ]

    /// Everything read from a pattern: its pieces and the yarn colours it names, in order of use.
    struct Reading: Equatable {
        var pieces: [Piece]
        /// "main", "white", "body color", "color b"… (index = the colour numbers in `Piece.colors`).
        var colorNames: [String]
    }

    /// Every round-by-round piece in the pattern.
    static func pieces(from rows: [String]) -> [Piece] { read(rows).pieces }

    private static let changeTo = regex(#"\b(?:change|switch)(?:\s+(?:yarn|colou?rs?))?\s+(?:back\s+)?(?:to|into)\s+([a-z][a-z ]{0,24}?)(?:\s+(?:yarn|colou?r))?\s*(?:[.,;:(!]|$|\s(?:and|then|for|in|on)\b)"#)
    private static let joinColor = regex(#"\b(?:join|attach|using|use|with)\s+(?:the\s+)?([a-z]+(?:\s[a-z]+)?)\s+(?:yarn|colou?r)\b"#)
    private static let onTopOf = regex(#"\b(?:sew|attach|place|put|stitch)\b.*?\b(?:on|onto|to|over)\s+(?:the\s+)?(top|bottom)\s+of\b"#)

    /// Every round-by-round piece in the pattern. Round numbers starting over (R1 again) begin a
    /// new piece, named after the short heading line above it ("HEAD", "Body:"). Also reads colour
    /// changes, taller stitches, collars, eyes, and where pieces are sewn on.
    static func read(_ rows: [String]) -> Reading {
        var out: [Piece] = []
        var current = Piece(id: 0, name: "", counts: [])
        var name: String?
        var lastNumber = 0
        var lastHeading: String?
        var colorNames: [String] = ["main"]
        var color = 0
        var sewLines: [(text: String, rounds: ClosedRange<Int>?, place: Piece.Attach.Place, line: Int)] = []

        func colorIndex(_ raw: String) -> Int {
            let name = raw.trimmingCharacters(in: .whitespaces)
            if let i = colorNames.firstIndex(of: name) { return i }
            colorNames.append(name)
            return colorNames.count - 1
        }

        /// A colour change anywhere in a line: "Change to white", "join pink yarn", "color change".
        func readColor(_ line: String) -> Int? {
            let lower = line.lowercased()
            let ns = lower as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = changeTo.firstMatch(in: lower, range: range) {
                return colorIndex(ns.substring(with: m.range(at: 1)))
            }
            if let m = joinColor.firstMatch(in: lower, range: range) {
                let phrase = ns.substring(with: m.range(at: 1))
                if YarnColor.rgb(phrase) != nil || phrase.hasPrefix("color") || phrase.hasPrefix("colour") {
                    return colorIndex(phrase)
                }
            }
            if (lower.contains("color") || lower.contains("colour")) && (lower.contains("change") || lower.contains("switch")) {
                return colorIndex("color \(colorNames.count + 1)")
            }
            return nil
        }

        func close() {
            guard current.counts.count >= 3, let first = current.counts.first, first <= 24 else { return }
            var title = name ?? "Piece \(out.count + 1)"
            if out.contains(where: { $0.name == title }) { title += " \(out.count + 1)" }
            current.id = out.count
            current.name = title
            current.repeatCount = max(1, PatternHeading.multiplier(in: title) ?? 1)
            current.topDown = title.lowercased().contains("head")
            out.append(current)
        }

        func readEyes(_ line: String) {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let e = eyesBetween.firstMatch(in: line, range: range) else { return }
            let a = Int(ns.substring(with: e.range(at: 1))) ?? 0
            let b = Int(ns.substring(with: e.range(at: 2))) ?? a
            var apart = 6
            if let s = stitchesApart.firstMatch(in: line, range: range) { apart = Int(ns.substring(with: s.range(at: 1))) ?? 6 }
            if a > 0 { current.eyes = .init(rounds: min(a, b)...max(a, b), apart: apart) }
        }

        for (lineIndex, line) in split(rows) {
            readEyes(line)
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let m = label.firstMatch(in: line, range: range) ?? numbered.firstMatch(in: line, range: range) else {
                let lower = line.lowercased()
                if let c = readColor(line) { color = c }
                if let f = frontLoopsOf.firstMatch(in: line, range: range), !current.counts.isEmpty {
                    let round = Int(ns.substring(with: f.range(at: 1))) ?? 0
                    var count: Int?
                    if let c = aroundCount.firstMatch(in: line, range: range) {
                        let g = c.range(at: 1).location != NSNotFound ? c.range(at: 1) : c.range(at: 2)
                        count = Int(ns.substring(with: g))
                    }
                    current.collars.append(.init(round: round, count: count, line: lineIndex))
                }
                if let sew = sewBetween.firstMatch(in: line, range: range) {
                    let a = Int(ns.substring(with: sew.range(at: 1))) ?? 0
                    let b = Int(ns.substring(with: sew.range(at: 2))) ?? a
                    if a > 0 { sewLines.append((lower, min(a, b)...max(a, b), .between, lineIndex)) }
                } else if let top = onTopOf.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)) {
                    let word = (lower as NSString).substring(with: top.range(at: 1))
                    sewLines.append((lower, nil, word == "top" ? .top : .bottom, lineIndex))
                }
                let heading = line.trimmingCharacters(in: CharacterSet(charactersIn: " :-*#\t"))
                if !heading.isEmpty, heading.count < 40 { lastHeading = heading }
                continue
            }
            let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let b = m.range(at: 2).location != NSNotFound ? (Int(ns.substring(with: m.range(at: 2))) ?? a) : a
            if !current.counts.isEmpty, a <= lastNumber {
                close()
                current = Piece(id: 0, name: "", counts: [])
                color = 0
            }
            if current.counts.isEmpty {
                name = lastHeading
                // "Hat (white)": a colour in the heading is the piece's colour.
                if let heading = lastHeading, YarnColor.rgb(heading) != nil, let word = YarnColor.colorWord(in: heading) {
                    color = colorIndex(word)
                }
            }
            // A change at the start of a round line ("8. Change to tan, sc around (24)").
            if let c = readColor(line) { color = c }
            let rest = ns.substring(from: m.range.location + m.range.length)
            guard let c = count(rest: rest, line: line, prev: current.counts.last), c > 0, c < 2000 else { continue }
            let times = max(1, min(200, b - a + 1))
            let height = tallStitch.first { $0.0.firstMatch(in: line, range: range) != nil }?.1 ?? 1
            current.counts.append(contentsOf: Array(repeating: c, count: times))
            current.heights.append(contentsOf: Array(repeating: height, count: times))
            current.colors.append(contentsOf: Array(repeating: color, count: times))
            current.lines.append(contentsOf: Array(repeating: lineIndex, count: times))
            lastNumber = max(a, b)
        }
        close()

        // "Sew on ears between rounds 4 & 6 of head", "Sew the hat on top of the head": the piece
        // named in the line goes onto the biggest piece (or the one named after "of").
        if let main = out.indices.max(by: { out[$0].counts.reduce(0, +) < out[$1].counts.reduce(0, +) }) {
            func key(_ name: String) -> String {
                let word = name.lowercased().split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
                return word.hasSuffix("s") ? String(word.dropLast()) : word
            }
            for sew in sewLines {
                guard let source = out.indices.first(where: { $0 != main && !key(out[$0].name).isEmpty
                                                              && sew.text.contains(key(out[$0].name)) }) else { continue }
                var target = main
                if let ofRange = sew.text.range(of: " of ", options: .backwards) {
                    let after = String(sew.text[ofRange.upperBound...])
                    if let t = out.indices.first(where: { $0 != source && !key(out[$0].name).isEmpty && after.contains(key(out[$0].name)) }) {
                        target = t
                    }
                    if after.contains("head") {
                        if sew.place == .between { out[target].topDown = true }
                        if out[target].name.hasPrefix("Piece ") { out[target].name = "Head" }
                    }
                }
                out[source].attach = .init(target: target, rounds: sew.rounds, place: sew.place, line: sew.line)
            }
        }
        return Reading(pieces: out, colorNames: colorNames)
    }

    /// Lines with their index in `rows`; several rounds pasted on one line are split apart.
    private static func split(_ rows: [String]) -> [(Int, String)] {
        var out: [(Int, String)] = []
        for (index, row) in rows.enumerated() {
            let ns = row as NSString
            var start = 0
            for m in inlineSplit.matches(in: row, range: NSRange(location: 0, length: ns.length)) {
                out.append((index, ns.substring(with: NSRange(location: start, length: m.range.location - start))))
                start = m.range.location
            }
            out.append((index, ns.substring(from: start)))
        }
        return out.map { ($0.0, $0.1.trimmingCharacters(in: .whitespaces)) }.filter { !$0.1.isEmpty }
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
    /// Colour index of each band (same order as bands); empty = all the first colour.
    var bandColors: [Int] = []

    var height: Double { bands.map { max($0.top.y, $0.bottom.y) }.max() ?? 0 }
    var maxRadius: Double { bands.map { max($0.top.x, $0.bottom.x) }.max() ?? 0 }
    var totalStitches: Int { bands.prefix(roundCount).reduce(0) { $0 + $1.stitches } }
    var closedTop = false
    /// Bands that are rounds (not the closing cap or collars).
    var roundCount = 0

    /// Each round's circumference sets its radius; each round adds one row height along the
    /// surface, so increases flatten it out and decreases pull it in, like real fabric.
    static func from(counts: [Int], gauge: Gauge, heights: [Double] = [], colors: [Int] = [],
                     collars: [PatternToShape.Piece.Collar] = [], puff: Double = 0,
                     closeEnd: Bool = true) -> StitchModel {
        let n = counts.count
        guard n > 0 else { return StitchModel(bands: []) }
        let radius = counts.map { Double($0) * gauge.w / (2 * Double.pi) }
        let rowH = (0..<n).map { gauge.h * ($0 < heights.count ? heights[$0] : 1) }
        let closed = closeEnd && counts[n - 1] <= 12

        // Flat fabric: each round adds one row height along the surface, so increases lie flat
        // and straight rounds go straight up. z[i] = height of round i's top edge.
        var z = [Double](repeating: 0, count: n)
        var prevR = 0.0, prevZ = 0.0
        for i in 0..<n {
            let dr = radius[i] - prevR
            let ds = max(rowH[i], abs(dr))
            let dz = max(sqrt(max(0, ds * ds - dr * dr)), puff * rowH[i] * 0.5)
            z[i] = prevZ + dz
            prevR = radius[i]; prevZ = z[i]
        }
        var capZ = prevZ + gauge.h * 0.3

        // Stuffed: the increases at the start and the decreases at the end round out into domes
        // instead of lying flat.
        if puff > 0 {
            // The opening dome runs up to the first widest round (rounds may repeat on the way: 6, 6, 9, 12).
            var k = 0
            while k + 1 < n && counts[k + 1] >= counts[k] && counts[k] < (counts.max() ?? 0) { k += 1 }
            var m = n - 1
            while m - 1 >= 0 && counts[m - 1] > counts[m] { m -= 1 }
            if m < k { m = k }
            if k >= 1 {
                let R = radius[k]
                let D = rowH[0...k].reduce(0, +) * 0.85
                for i in 0...k {
                    let t = min(1, radius[i] / R)
                    z[i] = D * (1 - (1 - t * t).squareRoot())
                }
                // Keep the rounds after the dome where they were relative to it.
                var last = z[k]
                for i in (k + 1)..<max(k + 1, m + 1) where i < n {
                    let dr = radius[i] - radius[i - 1]
                    let ds = max(rowH[i], abs(dr))
                    last += max(sqrt(max(0, ds * ds - dr * dr)), puff * rowH[i] * 0.5)
                    z[i] = last
                }
            }
            if closed && m < n - 1 {
                let R2 = radius[m]
                let D2 = (rowH[(m + 1)..<n].reduce(0, +) + gauge.h * 0.3) * 0.85
                for i in (m + 1)..<n {
                    let t = min(1, radius[i] / R2)
                    z[i] = z[m] + D2 * (1 - t * t).squareRoot()
                }
                capZ = z[m] + D2
            } else if closed {
                capZ = z[n - 1] + gauge.h * 0.3
            }
        }

        // Stuffing also squashes a piece a little: wider than its rounds alone would say, less tall.
        var radii = radius
        if puff > 0 {
            let squash = 1 - 0.4 * min(1, puff)
            for i in 0..<n { z[i] *= squash }
            capZ *= squash

            // Stuffed yarn is a stiff balloon: no corners or flat walls. Smooth the outline (the
            // poles stay put) and let it bulge back out to its widest round.
            var pts = [SIMD2<Double>(0, 0)] + (0..<n).map { SIMD2(radius[$0], z[$0]) }
            if closed { pts.append(SIMD2(0, capZ)) }
            let widest = radius.max() ?? 0
            let passes = puff >= 0.5 ? 6 : 3
            for _ in 0..<passes where pts.count > 2 {
                var next = pts
                for j in 1..<(pts.count - 1) {
                    next[j] = pts[j] * 0.5 + (pts[j - 1] + pts[j + 1]) * 0.25
                }
                // The poles stay on the axis and only move up or down, toward their neighbour, so
                // the ends round over flat instead of coming to a point.
                next[0] = SIMD2(0, pts[0].y * 0.5 + pts[1].y * 0.5)
                let last = pts.count - 1
                if closed {
                    next[last] = SIMD2(0, pts[last].y * 0.5 + pts[last - 1].y * 0.5)
                } else {
                    // An open end (a piece still being made) keeps its last edge where it is.
                    next[last] = pts[last]
                }
                pts = next
            }
            // Keep the start at the floor.
            let floor = pts[0].y
            pts = pts.map { SIMD2($0.x, $0.y - floor) }
            let smoothedWidest = pts.map(\.x).max() ?? 0
            let inflate = smoothedWidest > 0 ? widest / smoothedWidest * (1 + 0.06 * min(1, puff)) : 1
            for i in 0..<n {
                radii[i] = pts[i + 1].x * inflate
                z[i] = pts[i + 1].y
            }
            if closed { capZ = pts[pts.count - 1].y }
        }

        var bands: [Band] = []
        var bandColors: [Int] = []
        var p = SIMD2<Double>(0, 0)
        for i in 0..<n {
            let next = SIMD2(radii[i], z[i])
            bands.append(Band(bottom: p, top: next, stitches: counts[i]))
            bandColors.append(i < colors.count ? colors[i] : 0)
            p = next
        }
        var model = StitchModel(bands: bands, bandColors: bandColors)
        model.roundCount = bands.count
        if closed {
            model.bands.append(Band(bottom: p, top: SIMD2(0, capZ), stitches: counts[n - 1]))
            model.bandColors.append(bandColors.last ?? 0)
            model.closedTop = true
        }
        // A collar: one round in the front loops of a round, rising back toward the start and
        // flaring a little, like a cup around the round before.
        for collar in collars where collar.round >= 1 && collar.round <= bands.count {
            let edge = bands[collar.round - 1].top
            let tip = SIMD2(edge.x + gauge.h * 1.2, max(0, edge.y - gauge.h * 1.1))
            model.bands.append(Band(bottom: edge, top: tip, stitches: collar.count ?? counts[collar.round - 1]))
            model.bandColors.append(bandColors[collar.round - 1])
        }
        return model
    }
}
