import Foundation

enum YouTube {
    /// Pulls a video ID out of anything that looks like a YouTube link (watch, youtu.be,
    /// shorts, embed, live, m./music. hosts) or a bare 11-character ID.
    static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isID(trimmed) { return trimmed }

        // Find the first URL-ish token in the text (shared text often has words around it).
        let candidates = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for candidate in candidates {
            var string = candidate
            if !string.contains("://") { string = "https://" + string }
            guard let comps = URLComponents(string: string), let host = comps.host?.lowercased() else { continue }
            if host == "youtu.be" {
                let id = comps.path.split(separator: "/").first.map(String.init) ?? ""
                if isID(id) { return id }
            }
            guard host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else { continue }
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, isID(v) { return v }
            let parts = comps.path.split(separator: "/").map(String.init)
            if parts.count >= 2, ["shorts", "embed", "live", "v", "e"].contains(parts[0]), isID(parts[1]) {
                return parts[1]
            }
        }
        return nil
    }

    /// Start time from a `t=` / `start=` parameter, if any (seconds or 1h2m3s).
    static func startTime(from text: String) -> Double? {
        guard let comps = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let value = comps.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value
        else { return nil }
        if let seconds = Double(value.replacingOccurrences(of: "s", with: "")) { return seconds }
        var total = 0.0, number = ""
        for ch in value {
            if ch.isNumber { number.append(ch); continue }
            let n = Double(number) ?? 0
            switch ch {
            case "h": total += n * 3600
            case "m": total += n * 60
            case "s": total += n
            default: break
            }
            number = ""
        }
        return total > 0 ? total : nil
    }

    private static func isID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } && s.allSatisfy { $0.isASCII }
    }
}

enum TimeFormat {
    /// 1:02:03.456 / 2:03.456
    static func precise(_ t: Double) -> String {
        let t = max(0, t)
        let ms = Int((t * 1000).rounded()) % 1000
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d.%03d", h, m, s, ms) }
        return String(format: "%d:%02d.%03d", m, s, ms)
    }

    static func short(_ t: Double) -> String {
        let total = Int(max(0, t))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
