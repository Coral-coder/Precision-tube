import SwiftUI
import WebKit

/// The mobile YouTube site, for searching. When a video page is open, a big button sends it
/// to the frame-by-frame player.
struct BrowseView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: Store
    @StateObject private var browser = BrowserModel()

    var body: some View {
        NavigationStack {
            BrowserSurface(webView: browser.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) {
                    if let id = browser.currentVideoID {
                        Button {
                            browser.pauseVideos()
                            app.open(videoID: id, store: store, start: browser.currentStart)
                        } label: {
                            Label("Open in frame-by-frame player", systemImage: "scope")
                                .font(.headline)
                                .padding(.horizontal, 20).padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .shadow(radius: 6)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: browser.currentVideoID)
                .navigationTitle("YouTube")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { browser.webView.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!browser.canGoBack)
                        Button { browser.webView.goForward() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!browser.canGoForward)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        Button { browser.load(BrowserModel.home) } label: { Image(systemName: "house") }
                    }
                }
        }
        .onAppear { consumeRequest() }
        .onChange(of: app.browseRequest) { _, _ in consumeRequest() }
        .onChange(of: app.tab) { _, tab in if tab != .browse { browser.pauseVideos() } }
    }

    private func consumeRequest() {
        if let url = app.browseRequest {
            browser.load(url)
            app.browseRequest = nil
        }
    }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    static let home = URL(string: "https://m.youtube.com/results?search_query=crochet+tutorial")!

    @Published var currentVideoID: String?
    @Published var currentStart: Double?
    @Published var canGoBack = false
    @Published var canGoForward = false

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var loadedOnce = false

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        // YouTube is a single-page app: video pages are pushState changes, not navigations,
        // so watch the URL itself.
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
        ]
        load(Self.home)
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func pauseVideos() {
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){v.pause()})", completionHandler: nil)
    }

    private func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        urlChanged(webView.url)
    }

    private func urlChanged(_ url: URL?) {
        guard let string = url?.absoluteString else { currentVideoID = nil; return }
        let path = url?.path ?? ""
        if path.hasPrefix("/watch") || path.hasPrefix("/shorts/") || path.hasPrefix("/live/") {
            currentVideoID = YouTube.videoID(from: string)
            currentStart = YouTube.startTime(from: string)
        } else {
            currentVideoID = nil
            currentStart = nil
        }
    }
}

struct BrowserSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
