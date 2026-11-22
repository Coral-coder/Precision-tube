import Foundation

// Plain pattern logic with no UI, shared by the app and the Linux render test
// (tools/pattern-render).

enum Craft: String, Codable, CaseIterable, Identifiable {
    case crochet = "Crochet"
    case knitting = "Knitting"
    case other = "Other"
    var id: String { rawValue }
}

/// Tells a heading ("Collar", "Ears x2", "Body:") from a step in a pasted pattern.
enum PatternHeading {
    private static let stitchWords: Set<String> = [
        "sc", "hdc", "dc", "tr", "dtr", "inc", "dec", "ch", "sl", "st", "sts", "mr", "blo", "flo", "tlo",
        "sc2tog", "invdec", "bo", "fo", "k", "p", "k2tog", "ssk", "yo", "co", "rnd", "round", "row", "rows",
    ]
    private static let verbs: Set<String> = [
        "change", "sew", "stuff", "fasten", "attach", "use", "insert", "place", "cut", "weave", "repeat",
        "join", "turn", "work", "add", "leave", "pull", "embroider", "make", "crochet", "knit", "purl",
        "cast", "bind", "finish", "close", "tie", "glue", "secure", "continue", "skip", "start", "begin",
    ]

    static func isHeading(_ line: String) -> Bool {
        // "ARMS (make 2)", "Ears (pink)": the bracketed note doesn't stop it being a heading.
        let t = line.replacingOccurrences(of: #"\s*\((?:make\s+\w+|x\s?\d+|\d+\s?x|[a-z ]+)\)"#,
                                          with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 40, let first = t.first, !first.isNumber else { return false }
        if t.hasSuffix(":") { return true }
        if t.hasSuffix(".") || t.contains("(") { return false }
        let words = t.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty, words.count <= 4 else { return false }
        if words.first.map({ ["r", "rnd", "rnds", "round", "row"].contains($0) }) == true && words.count > 1,
           words[1].first?.isNumber == true { return false }
        if words.contains(where: { stitchWords.contains($0) || verbs.contains($0) }) { return false }
        // Numbers only as a multiplier ("x2", "2x").
        return words.allSatisfy { w in !w.contains(where: \.isNumber) || multiplier(in: w) != nil }
    }

    /// "Ears x2", "ARMS (make 2)", "legs × 4", "make two", "2 pieces".
    static func multiplier(in text: String) -> Int? {
        let lower = text.lowercased().replacingOccurrences(of: "×", with: "x")
        let words = ["two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "eight": 8]
        if let r = lower.range(of: #"\bmake\s+(\d+|two|three|four|five|six|eight)\b"#, options: .regularExpression) {
            let w = lower[r].split(separator: " ").last.map(String.init) ?? ""
            return Int(w) ?? words[w]
        }
        if let r = lower.range(of: #"\b(\d+)\s+(?:pieces|pcs|of them)\b"#, options: .regularExpression) {
            return Int(lower[r].filter(\.isNumber))
        }
        if let r = lower.range(of: #"(?:^|\s|\()x\s?(\d+)"#, options: .regularExpression) {
            return Int(lower[r].filter(\.isNumber))
        }
        if let r = lower.range(of: #"(\d+)\s?x(?:$|\s|\))"#, options: .regularExpression) {
            return Int(lower[r].filter(\.isNumber))
        }
        return nil
    }
}

/// A pattern ready to follow row by row: a built-in one or one you wrote.
enum EvenlyCalculator {
    /// Instructions to change `stitches` by `change` (positive: increase, negative: decrease),
    /// spreading the shaping as evenly as possible.
    static func instructions(stitches n: Int, change: Int, craft: Craft) -> String? {
        guard n > 0, change != 0 else { return nil }
        let k = abs(change)
        let knit = craft == .knitting
        let plain = knit ? "K" : "Sc"
        func part(_ count: Int, _ shaping: String, times: Int) -> String? {
            guard times > 0 else { return nil }
            let body = count > 0 ? "\(plain) \(count), \(shaping)" : shaping
            return times == 1 ? body : "*\(body)* \(times) times"
        }
        let base = n / k, extra = n % k
        if change > 0 {
            if knit {
                // M1 makes a stitch without using one: groups of `base` (or base+1) knits, then M1.
                guard k <= n else { return "That's more increases than stitches. Try a smaller number." }
                return [part(base + 1, "M1", times: extra), part(base, "M1", times: k - extra)]
                    .compactMap { $0 }.joined(separator: ", ")
            }
            guard k <= n else { return "That's more increases than stitches; work 2 or more stitches into some stitches instead." }
            // "inc" works 2 stitches into 1 stitch, so each group is (base - 1) plain + 1 inc.
            return [part(base, "inc", times: extra), part(base - 1, "inc", times: k - extra)]
                .compactMap { $0 }.joined(separator: ", ")
        } else {
            let dec = knit ? "k2tog" : "dec"
            guard 2 * k <= n else { return "You can decrease at most \(n / 2) stitches in one row." }
            // A decrease uses 2 stitches: each group is (base - 2) plain + 1 dec.
            return [part(base - 1, dec, times: extra), part(base - 2, dec, times: k - extra)]
                .compactMap { $0 }.joined(separator: ", ")
        }
    }
}


/// Yarn colour names a pattern might use, as RGB (0…1).
enum YarnColor {
    static let table: [(String, (Double, Double, Double))] = [
        ("white", (0.96, 0.96, 0.94)), ("cream", (0.96, 0.92, 0.82)), ("ivory", (0.97, 0.95, 0.87)),
        ("black", (0.10, 0.10, 0.11)), ("grey", (0.60, 0.60, 0.62)), ("gray", (0.60, 0.60, 0.62)),
        ("silver", (0.75, 0.76, 0.78)), ("charcoal", (0.25, 0.25, 0.27)),
        ("brown", (0.45, 0.30, 0.20)), ("tan", (0.78, 0.68, 0.52)), ("beige", (0.86, 0.80, 0.68)),
        ("khaki", (0.74, 0.69, 0.52)), ("camel", (0.76, 0.60, 0.42)), ("chocolate", (0.36, 0.22, 0.14)),
        ("green", (0.30, 0.65, 0.35)), ("mint", (0.60, 0.88, 0.78)), ("sage", (0.62, 0.71, 0.58)),
        ("olive", (0.50, 0.50, 0.22)), ("teal", (0.15, 0.55, 0.56)), ("lime", (0.68, 0.85, 0.30)),
        ("blue", (0.25, 0.45, 0.80)), ("navy", (0.12, 0.17, 0.38)), ("sky", (0.55, 0.78, 0.95)),
        ("turquoise", (0.25, 0.80, 0.78)), ("aqua", (0.45, 0.85, 0.88)),
        ("red", (0.82, 0.18, 0.18)), ("burgundy", (0.50, 0.10, 0.18)), ("pink", (0.95, 0.62, 0.72)),
        ("rose", (0.90, 0.50, 0.60)), ("coral", (0.96, 0.50, 0.42)), ("peach", (0.98, 0.76, 0.62)),
        ("orange", (0.95, 0.55, 0.15)), ("yellow", (0.98, 0.85, 0.25)), ("gold", (0.85, 0.68, 0.22)),
        ("mustard", (0.82, 0.65, 0.18)), ("purple", (0.52, 0.32, 0.68)), ("lavender", (0.75, 0.68, 0.90)),
        ("lilac", (0.78, 0.64, 0.86)), ("plum", (0.48, 0.22, 0.42)),
    ]

    /// The first colour word in a phrase ("light pink yarn" → "pink").
    static func colorWord(in phrase: String) -> String? {
        let words = phrase.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.first { w in table.contains { $0.0 == w } }
    }

    /// RGB for a colour phrase, lightened or darkened by "light"/"dark"/"pale".
    static func rgb(_ phrase: String) -> (Double, Double, Double)? {
        guard let word = colorWord(in: phrase), let entry = table.first(where: { $0.0 == word }) else { return nil }
        var (r, g, b) = entry.1
        let lower = phrase.lowercased()
        if lower.contains("light") || lower.contains("pale") || lower.contains("baby") {
            r += (1 - r) * 0.45; g += (1 - g) * 0.45; b += (1 - b) * 0.45
        } else if lower.contains("dark") || lower.contains("deep") {
            r *= 0.6; g *= 0.6; b *= 0.6
        }
        return (r, g, b)
    }

    /// Colours for unnamed yarns ("main", "color 2", "body color"), in order.
    static let defaults: [(Double, Double, Double)] = [
        (0.55, 0.85, 0.80), (0.78, 0.72, 0.62), (0.96, 0.95, 0.92), (0.95, 0.65, 0.75),
        (0.72, 0.68, 0.92), (0.98, 0.82, 0.45), (0.55, 0.72, 0.95),
    ]

    /// A colour for every yarn the pattern names.
    static func palette(for names: [String]) -> [(Double, Double, Double)] {
        var unnamed = 0
        return names.map { name in
            if let c = rgb(name) { return c }
            defer { unnamed += 1 }
            return defaults[unnamed % defaults.count]
        }
    }
}
