import Foundation
import SwiftUI

struct VideoMarker: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Double
    var label: String
}

struct SavedVideo: Codable, Identifiable, Hashable {
    var id: String               // YouTube video ID
    var title: String?
    var author: String?
    var lastPosition: Double = 0
    var lastOpened = Date()
    var favorite = false
    var markers: [VideoMarker] = []
    var fpsOverride: Double?

    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
    var displayTitle: String { title ?? "YouTube video \(id)" }
}

struct StitchCounter: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var count: Int = 0
    var target: Int?
}

enum Craft: String, Codable, CaseIterable, Identifiable {
    case crochet = "Crochet"
    case knitting = "Knitting"
    case other = "Other"
    var id: String { rawValue }
}

struct UserPattern: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var craft: Craft = .crochet
    var notes: String = ""
    /// One instruction per line; each becomes a check-off row.
    var body: String = ""
    var videoID: String?
    var created = Date()

    var rows: [String] {
        body.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct StoreData: Codable {
    var videos: [SavedVideo] = []
    var counters: [StitchCounter] = []
    var patterns: [UserPattern] = []
    /// Pattern ID → indices of finished rows.
    var progress: [String: [Int]] = [:]
    /// Pattern ID → its row counter.
    var patternCounters: [String: Int] = [:]
}

/// Everything the app remembers, saved as one small JSON file.
@MainActor
final class Store: ObservableObject {
    @Published var videos: [SavedVideo] = [] { didSet { scheduleSave() } }
    @Published var counters: [StitchCounter] = [] { didSet { scheduleSave() } }
    @Published var patterns: [UserPattern] = [] { didSet { scheduleSave() } }
    @Published var progress: [String: [Int]] = [:] { didSet { scheduleSave() } }
    @Published var patternCounters: [String: Int] = [:] { didSet { scheduleSave() } }

    private var saveTask: Task<Void, Never>?
    private var loading = false

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("precisiontube.json")
    }

    init() {
        loading = true
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(StoreData.self, from: data) {
            videos = decoded.videos
            counters = decoded.counters
            patterns = decoded.patterns
            progress = decoded.progress
            patternCounters = decoded.patternCounters
        }
        if counters.isEmpty {
            counters = [StitchCounter(name: "Rows"), StitchCounter(name: "Stitches")]
        }
        loading = false
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let data = StoreData(videos: videos, counters: counters, patterns: patterns,
                             progress: progress, patternCounters: patternCounters)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: Self.fileURL, options: .atomic)
        }
    }

    // MARK: Videos

    var recentVideos: [SavedVideo] { videos.sorted { $0.lastOpened > $1.lastOpened } }

    func video(_ id: String) -> SavedVideo? { videos.first { $0.id == id } }

    @discardableResult
    func touchVideo(id: String) -> SavedVideo {
        if let index = videos.firstIndex(where: { $0.id == id }) {
            videos[index].lastOpened = Date()
            return videos[index]
        }
        let video = SavedVideo(id: id)
        videos.append(video)
        return video
    }

    func updateVideo(_ id: String, _ change: (inout SavedVideo) -> Void) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        change(&videos[index])
    }

    func deleteVideo(_ id: String) { videos.removeAll { $0.id == id } }

    func fetchTitle(for id: String) async {
        guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        updateVideo(id) { video in
            video.title = json["title"] as? String
            video.author = json["author_name"] as? String
        }
    }

    // MARK: Pattern progress

    func isDone(pattern: String, row: Int) -> Bool { progress[pattern]?.contains(row) ?? false }

    func toggle(pattern: String, row: Int) {
        var done = Set(progress[pattern] ?? [])
        if done.contains(row) { done.remove(row) } else { done.insert(row) }
        progress[pattern] = done.sorted()
    }

    func resetProgress(pattern: String) {
        progress[pattern] = []
        patternCounters[pattern] = 0
    }
}
