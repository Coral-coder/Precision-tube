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
        let t = line.trimmingCharacters(in: .whitespaces)
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

    static func multiplier(in text: String) -> Int? {
        let lower = text.lowercased()
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

