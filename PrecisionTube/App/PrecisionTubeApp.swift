import SwiftUI

@main
struct PrecisionTubeApp: App {
    @StateObject private var store = Store()
    @StateObject private var app = AppState()
    @AppStorage(Theme.storageKey) private var themeHex = Theme.defaultHex

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(app)
                .environmentObject(app.player)
                .tint(Theme.color(hex: themeHex))
                .accentColor(Theme.color(hex: themeHex))
                .onOpenURL { url in
                    if let id = YouTube.videoID(from: url.absoluteString) {
                        app.open(videoID: id, store: store)
                    }
                }
        }
    }
}

enum AppTab: Hashable {
    case videos, player, browse, patterns, tools
}

/// App-wide navigation and the one shared player (kept alive across tabs so a paused
/// video stays exactly where it was while you look at a pattern).
@MainActor
final class AppState: ObservableObject {
    @Published var tab: AppTab = .videos
    @Published var browseRequest: URL?
    let player = PlayerController()

    func open(videoID: String, store: Store, start: Double? = nil) {
        let video = store.touchVideo(id: videoID)
        player.load(videoID: videoID, start: start ?? video.lastPosition, fpsOverride: video.fpsOverride)
        tab = .player
        if video.title == nil {
            Task { await store.fetchTitle(for: videoID) }
        }
    }

    func searchYouTube(_ query: String) {
        var comps = URLComponents(string: "https://m.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        browseRequest = comps.url
        tab = .browse
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $app.tab) {
            LibraryView()
                .tabItem { Label("Videos", systemImage: "film.stack") }
                .tag(AppTab.videos)
            PlayerScreen()
                .tabItem { Label("Player", systemImage: "play.rectangle") }
                .tag(AppTab.player)
            BrowseView()
                .tabItem { Label("YouTube", systemImage: "magnifyingglass") }
                .tag(AppTab.browse)
            PatternsView()
                .tabItem { Label("Patterns", systemImage: "book") }
                .tag(AppTab.patterns)
            ToolsView()
                .tabItem { Label("Tools", systemImage: "plusminus.circle") }
                .tag(AppTab.tools)
        }
        .onAppear {
            let store = self.store
            app.player.onSavePosition = { id, time in
                store.updateVideo(id) { $0.lastPosition = time }
            }
            app.player.onSaveFPS = { id, fps in
                store.updateVideo(id) { $0.fpsOverride = fps }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                app.player.savePosition(force: true)
                store.saveNow()
            }
        }
    }
}
