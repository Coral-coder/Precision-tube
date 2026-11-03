import SwiftUI
import WebKit

struct PlayerScreen: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState

    @State private var span: Double = 4
    @State private var stepSize = 1
    @State private var interactWithYouTube = false
    @State private var focusMode = false
    @State private var renaming: VideoMarker?
    @State private var renameText = ""
    @State private var overlayVisible = true
    /// Landscape: frame buttons that stay on the left and right edges of the screen.
    @AppStorage("edgeFrameButtons") private var edgeButtons = false
    @State private var lastInteraction = Date()

    private var markers: [VideoMarker] {
        guard let id = player.videoID else { return [] }
        return (store.video(id)?.markers ?? []).sorted { $0.time < $1.time }
    }

    var body: some View {
        GeometryReader { outer in
            let landscape = player.videoID != nil && outer.size.width > outer.size.height
            NavigationStack {
                Group {
                    if player.videoID == nil {
                        EmptyPlayerView()
                    } else if landscape {
                        landscapePlayer
                    } else {
                        GeometryReader { geo in
                            VStack(spacing: 8) {
                                video
                                    .frame(maxHeight: geo.size.height * 0.45)
                                timelineBlock.padding(.horizontal, 10)
                                ScrollView { controls.padding(.horizontal, 10).padding(.bottom, 12) }
                            }
                        }
                    }
                }
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbar(landscape ? .hidden : .automatic, for: .navigationBar)
                .toolbar((focusMode || landscape) ? .hidden : .automatic, for: .tabBar)
                .statusBarHidden(landscape)
                .persistentSystemOverlays(landscape ? .hidden : .automatic)
                .background(keyboardShortcuts)
                .onChange(of: landscape) { _, _ in showOverlay() }
                .onChange(of: player.currentTime) { _, _ in if !player.isPlaying { lastInteraction = Date() } }
                .task(id: landscape) {
                    // Fade the landscape controls out after a few seconds without a touch.
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if landscape, overlayVisible, Date().timeIntervalSince(lastInteraction) > 3.5 {
                            withAnimation(.easeOut(duration: 0.35)) { overlayVisible = false }
                        }
                    }
                }
                .alert("Name this mark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("e.g. Start of row 3", text: $renameText)
                    Button("Save") {
                        if let marker = renaming, let id = player.videoID {
                            store.updateVideo(id) { video in
                                if let i = video.markers.firstIndex(where: { $0.id == marker.id }) { video.markers[i].label = renameText }
                            }
                        }
                        renaming = nil
                    }
                    Button("Cancel", role: .cancel) { renaming = nil }
                }
            }
        }
    }

    private func showOverlay() {
        lastInteraction = Date()
        if !overlayVisible { withAnimation(.easeIn(duration: 0.2)) { overlayVisible = true } }
    }

    // MARK: Landscape: full-screen video, controls float over it and fade away

    private var landscapePlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZoomableVideo(interactive: interactWithYouTube, onTap: {
                if overlayVisible {
                    withAnimation(.easeOut(duration: 0.25)) { overlayVisible = false }
                } else {
                    showOverlay()
                }
            })
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            errorOverlay
            if edgeButtons { edgeFrameButtons }
            if overlayVisible {
                landscapeControls
                    .transition(.opacity)
            }
        }
    }

    private var landscapeControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(navTitle).font(.headline).lineLimit(1)
                Spacer()
                if player.playlistID != nil {
                    Button { player.previousVideo() } label: { Image(systemName: "backward.end.fill") }
                        .disabled((player.playlistIndex ?? 0) == 0)
                    if let i = player.playlistIndex {
                        Text(player.playlistCount.map { "\(i + 1)/\($0)" } ?? "\(i + 1)").font(.caption.monospacedDigit())
                    }
                    Button { player.nextVideo() } label: { Image(systemName: "forward.end.fill") }
                }
                Button { edgeButtons.toggle() } label: {
                    Image(systemName: edgeButtons ? "arrow.left.and.right.circle.fill" : "arrow.left.and.right.circle")
                }
                .accessibilityLabel("Frame buttons on the edges")
                markButton
                optionsMenu.font(.title3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(TimeFormat.precise(player.currentTime))
                        .font(.system(.headline, design: .monospaced))
                    Text("frame \(player.currentFrame)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach([0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { r in
                            Button(r == 1 ? "1×" : "\(r.formatted())×") { player.setRate(r) }
                        }
                    } label: {
                        Label(player.rate == 1 ? "1×" : "\(player.rate.formatted())×", systemImage: "speedometer")
                            .font(.subheadline)
                    }
                    Button { span = max(PrecisionTimeline.minSpan, span / 2) } label: { Image(systemName: "plus.magnifyingglass") }
                    Button { span = min(max(10, player.duration), span * 2) } label: { Image(systemName: "minus.magnifyingglass") }
                    Toggle(isOn: $player.loopOn) { Image(systemName: "repeat") }
                        .toggleStyle(.button)
                        .disabled(player.loopA == nil || player.loopB == nil)
                }
                PrecisionTimeline(span: $span, markers: markers)
                    .frame(height: 64)
                HStack(spacing: 8) {
                    RepeatButton(action: { player.jump(seconds: -1) }, translucent: true) { Label("1s", systemImage: "chevron.backward.2") }
                    RepeatButton(action: { player.step(frames: -stepSize) }, translucent: true) {
                        Image(systemName: "backward.frame.fill").font(.title2)
                    }
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    RepeatButton(action: { player.step(frames: stepSize) }, translucent: true) {
                        Image(systemName: "forward.frame.fill").font(.title2)
                    }
                    RepeatButton(action: { player.jump(seconds: 1) }, translucent: true) { Label("1s", systemImage: "chevron.forward.2") }
                }
                .font(.subheadline)
            }
            .padding(12)
            .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .environment(\.colorScheme, .dark)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in lastInteraction = Date() })
    }

    /// See-through frame buttons hugging the left and right edges; they stay when the rest fades.
    private var edgeFrameButtons: some View {
        HStack {
            VStack(spacing: 10) {
                RepeatButton(action: { player.step(frames: -stepSize) }, translucent: true, fillHeight: true) {
                    Image(systemName: "backward.frame.fill").font(.title)
                }
                .frame(width: 78, height: 170)
                RepeatButton(action: { player.jump(seconds: -1) }, translucent: true) {
                    Text("−1s").font(.subheadline.weight(.semibold))
                }
                .frame(width: 78)
            }
            Spacer()
            VStack(spacing: 10) {
                RepeatButton(action: { player.step(frames: stepSize) }, translucent: true, fillHeight: true) {
                    Image(systemName: "forward.frame.fill").font(.title)
                }
                .frame(width: 78, height: 170)
                RepeatButton(action: { player.jump(seconds: 1) }, translucent: true) {
                    Text("+1s").font(.subheadline.weight(.semibold))
                }
                .frame(width: 78)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, overlayVisible ? 170 : 0)
        .opacity(0.85)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: overlayVisible)
    }

    private var markButton: some View {
        Button {
            guard let id = player.videoID else { return }
            let t = player.currentTime
            store.updateVideo(id) { video in
                video.markers.append(VideoMarker(time: t, label: "Mark \(video.markers.count + 1)"))
            }
        } label: { Image(systemName: "bookmark.fill") }
    }

    private var navTitle: String {
        guard let id = player.videoID else { return "Player" }
        return store.video(id)?.displayTitle ?? "Player"
    }

    // MARK: Video

    private var video: some View {
        ZoomableVideo(interactive: interactWithYouTube)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .overlay(alignment: .center) { errorOverlay }
    }

    @ViewBuilder
    private var errorOverlay: some View {
                if let error = player.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text(error).multilineTextAlignment(.center)
                        if let id = player.videoID, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                            Link("Open in YouTube", destination: url).buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
    }

    // MARK: Timeline

    private var timelineBlock: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(TimeFormat.precise(player.currentTime))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                Text("frame \(player.currentFrame)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("/ \(TimeFormat.short(player.duration))")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            PrecisionTimeline(span: $span, markers: markers)
            OverviewBar(markers: markers, span: span)
            HStack(spacing: 6) {
                zoomChip("Frames", 0.6)
                zoomChip("3s", 3)
                zoomChip("15s", 15)
                zoomChip("1m", 60)
                zoomChip("All", max(player.duration, 10))
                Spacer(minLength: 0)
                Button { span = max(PrecisionTimeline.minSpan, span / 2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.bordered)
                Button { span = min(max(10, player.duration), span * 2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.bordered)
            }
            .font(.caption)
        }
    }

    private func zoomChip(_ title: String, _ seconds: Double) -> some View {
        Button(title) { withAnimation(.easeInOut(duration: 0.2)) { span = seconds } }
            .buttonStyle(.bordered)
            .tint(abs(span - seconds) < 0.01 ? Color.accentColor : Color.gray)
            .controlSize(.small)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            playlistBar
            transport
            stepAndSpeed
            loopSection
            markerSection
            RowCounterStrip()
            infoSection
        }
    }

    @ViewBuilder
    private var playlistBar: some View {
        if player.playlistID != nil {
            HStack(spacing: 10) {
                Button { player.previousVideo() } label: { Image(systemName: "backward.end.fill").frame(width: 34, height: 30) }
                    .buttonStyle(.bordered)
                    .disabled((player.playlistIndex ?? 0) == 0)
                VStack(spacing: 1) {
                    Text("Playlist").font(.caption.weight(.semibold))
                    if let i = player.playlistIndex {
                        Text(player.playlistCount.map { "Video \(i + 1) of \($0)" } ?? "Video \(i + 1)")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Plays on to the next video").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                Button { player.nextVideo() } label: { Image(systemName: "forward.end.fill").frame(width: 34, height: 30) }
                    .buttonStyle(.bordered)
            }
            .padding(8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var transport: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                RepeatButton(action: { player.step(frames: -stepSize) }) {
                    VStack(spacing: 2) {
                        Image(systemName: "backward.frame.fill").font(.title)
                        Text(stepSize == 1 ? "1 frame" : "\(stepSize) frames").font(.caption2)
                    }
                }
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                RepeatButton(action: { player.step(frames: stepSize) }) {
                    VStack(spacing: 2) {
                        Image(systemName: "forward.frame.fill").font(.title)
                        Text(stepSize == 1 ? "1 frame" : "\(stepSize) frames").font(.caption2)
                    }
                }
            }
            HStack(spacing: 8) {
                RepeatButton(action: { player.jump(seconds: -5) }) { Label("5s", systemImage: "gobackward.5") }
                RepeatButton(action: { player.jump(seconds: -1) }) { Label("1s", systemImage: "chevron.backward.2") }
                RepeatButton(action: { player.jump(seconds: 1) }) { Label("1s", systemImage: "chevron.forward.2") }
                RepeatButton(action: { player.jump(seconds: 5) }) { Label("5s", systemImage: "goforward.5") }
            }
            .font(.subheadline)
        }
    }

    private var stepAndSpeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step").font(.subheadline.weight(.semibold))
                Picker("Step", selection: $stepSize) {
                    Text("1").tag(1); Text("2").tag(2); Text("5").tag(5); Text("10").tag(10)
                }
                .pickerStyle(.segmented)
                Text("frames").font(.caption).foregroundStyle(.secondary)
            }
            Text("Speed").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { r in
                        Button(r == 1 ? "1×" : "\(r.formatted())×") { player.setRate(r) }
                            .buttonStyle(.bordered)
                            .tint(abs(player.rate - r) < 0.01 ? Color.accentColor : Color.gray)
                            .controlSize(.small)
                    }
                }
            }
            if !player.preciseMode && player.ready && player.rate > 0 {
                Text("Basic mode: slowest speed is 0.25×.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var loopSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat a section").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button { player.loopA = player.currentTime; if let b = player.loopB, b <= player.currentTime { player.loopB = nil } } label: {
                    Text(player.loopA.map { "A " + TimeFormat.short($0) } ?? "Set A").frame(maxWidth: .infinity)
                }
                Button { if let a = player.loopA, player.currentTime > a { player.loopB = player.currentTime; player.loopOn = true } } label: {
                    Text(player.loopB.map { "B " + TimeFormat.short($0) } ?? "Set B").frame(maxWidth: .infinity)
                }
                .disabled(player.loopA == nil)
                Toggle(isOn: $player.loopOn) { Image(systemName: "repeat") }
                    .toggleStyle(.button)
                    .disabled(player.loopA == nil || player.loopB == nil)
                Button { player.loopA = nil; player.loopB = nil; player.loopOn = false } label: { Image(systemName: "xmark") }
                    .disabled(player.loopA == nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private var markerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Marks").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    guard let id = player.videoID else { return }
                    let t = player.currentTime
                    store.updateVideo(id) { video in
                        video.markers.append(VideoMarker(time: t, label: "Mark \(video.markers.count + 1)"))
                    }
                } label: { Label("Mark this spot", systemImage: "bookmark.fill") }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if markers.isEmpty {
                Text("Mark the start of a stitch or row to jump back to it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(markers) { marker in
                HStack {
                    Button {
                        player.pause()
                        player.seek(to: marker.time)
                    } label: {
                        HStack {
                            Image(systemName: "bookmark").foregroundStyle(.orange)
                            Text(marker.label).lineLimit(1)
                            Spacer()
                            Text(TimeFormat.precise(marker.time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button("Rename") { renameText = marker.label; renaming = marker }
                        Button("Delete", role: .destructive) {
                            if let id = player.videoID {
                                store.updateVideo(id) { $0.markers.removeAll { $0.id == marker.id } }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle").padding(.leading, 6) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var infoSection: some View {
        HStack(spacing: 6) {
            Image(systemName: player.preciseMode ? "scope" : "circle.dotted")
            Text(player.preciseMode ? "Precise mode" : (player.ready ? "Basic mode" : "Loading…"))
            Text("·")
            Text(fpsLabel)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var fpsLabel: String {
        if let o = player.fpsOverride { return "\(o.formatted()) fps (set)" }
        if let d = player.detectedFPS { return "\(d.formatted()) fps (measured)" }
        return "30 fps (play a moment to measure)"
    }

    // MARK: Toolbar & keyboard

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if player.videoID != nil {
                Button { focusMode.toggle() } label: {
                    Image(systemName: focusMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                optionsMenu
            }
        }
    }

    private var optionsMenu: some View {
                Menu {
                    Picker("Frame rate", selection: $player.fpsOverride) {
                        Text("Auto (\(player.detectedFPS?.formatted() ?? "30"))").tag(Double?.none)
                        ForEach([24.0, 25, 29.97, 30, 50, 59.94, 60], id: \.self) { f in
                            Text("\(f.formatted()) fps").tag(Double?.some(f))
                        }
                    }
                    Toggle("Mute", isOn: $player.muted)
                    Toggle("Frame buttons on the edges (landscape)", isOn: $edgeButtons)
                    Toggle("Tap through to YouTube", isOn: $interactWithYouTube)
                    if let id = player.videoID {
                        Button {
                            store.updateVideo(id) { $0.favorite.toggle() }
                        } label: {
                            Label(store.video(id)?.favorite == true ? "Unfavorite" : "Favorite", systemImage: "star")
                        }
                        if let url = URL(string: "https://www.youtube.com/watch?v=\(id)&t=\(Int(player.currentTime))s") {
                            ShareLink(item: url) { Label("Share link at this time", systemImage: "square.and.arrow.up") }
                            Link(destination: url) { Label("Open in YouTube", systemImage: "arrow.up.right.square") }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
    }

    private var keyboardShortcuts: some View {
        ZStack {
            Button("Play/Pause") { player.togglePlay() }.keyboardShortcut(.space, modifiers: [])
            Button("Back a frame") { player.step(frames: -stepSize) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward a frame") { player.step(frames: stepSize) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Back 1s") { player.jump(seconds: -1) }.keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("Forward 1s") { player.jump(seconds: 1) }.keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("Zoom in") { span = max(PrecisionTimeline.minSpan, span / 2) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Zoom out") { span = min(max(10, player.duration), span * 2) }.keyboardShortcut(.downArrow, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Video with pinch-to-zoom

struct ZoomableVideo: View {
    @EnvironmentObject var player: PlayerController
    var interactive: Bool
    /// What a single tap does; plays/pauses by default.
    var onTap: (() -> Void)? = nil

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                VideoSurface(webView: player.webView)
                if !interactive {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = min(8, max(1, baseScale * value.magnification))
                                        offset = clamped(offset, size: geo.size)
                                        apply()
                                    }
                                    .onEnded { _ in baseScale = scale; baseOffset = offset },
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        guard scale > 1 else { return }
                                        offset = clamped(CGSize(width: baseOffset.width + value.translation.width,
                                                                height: baseOffset.height + value.translation.height), size: geo.size)
                                        apply()
                                    }
                                    .onEnded { _ in baseOffset = offset }
                            )
                        )
                        .onTapGesture(count: 2) { reset() }
                        .onTapGesture { if let onTap { onTap() } else { player.togglePlay() } }
                }
                if scale > 1.01 {
                    Button { reset() } label: {
                        Label(String(format: "%.1f×", scale), systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(8)
                }
            }
            .clipped()
        }
        .onChange(of: player.videoID) { _, _ in reset() }
    }

    private func clamped(_ o: CGSize, size: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2
        let maxY = (scale - 1) * size.height / 2
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }

    private func apply() { player.setZoom(scale: scale, offset: offset) }

    private func reset() {
        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
        apply()
    }
}

struct VideoSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Buttons that repeat while held

/// Tap to do it once; hold to keep doing it. Built on a real Button so a swipe that starts on
/// it still scrolls the page (a raw drag gesture would swallow the scroll).
struct RepeatButton<Content: View>: View {
    let action: @MainActor () -> Void
    var translucent = false
    var fillHeight = false
    @ViewBuilder let label: () -> Content

    @State private var repeatTask: Task<Void, Never>?
    @State private var repeated = false

    var body: some View {
        Button {
            // Released: a hold already did its work; a tap does it once.
            if repeated { repeated = false; return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            label()
        }
        .buttonStyle(RepeatPressStyle(translucent: translucent, fillHeight: fillHeight) { pressing in
            repeatTask?.cancel()
            repeatTask = nil
            guard pressing else { return }
            repeated = false
            repeatTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                repeated = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                while !Task.isCancelled {
                    action()
                    try? await Task.sleep(nanoseconds: 85_000_000)
                }
            }
        })
    }
}

private struct RepeatPressStyle: ButtonStyle {
    let translucent: Bool
    let fillHeight: Bool
    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: fillHeight ? .infinity : nil)
            .foregroundStyle(Color.accentColor)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(configuration.isPressed ? Color.accentColor.opacity(0.3)
                      : Color(.secondarySystemBackground).opacity(translucent ? 0.55 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: configuration.isPressed) { _, pressing in onPressingChanged(pressing) }
    }
}

// MARK: - Row counter under the video

struct RowCounterStrip: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let first = store.counters.first, let index = store.counters.firstIndex(of: first) {
            HStack(spacing: 10) {
                VStack(alignment: .leading) {
                    Text(first.name).font(.subheadline.weight(.semibold))
                    Text("Counter from the Tools tab").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { if store.counters[index].count > 0 { store.counters[index].count -= 1 } } label: {
                    Image(systemName: "minus").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                Text("\(first.count)").font(.title2.monospacedDigit().weight(.bold)).frame(minWidth: 44)
                Button {
                    store.counters[index].count += 1
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: "plus").frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Nothing loaded yet

struct EmptyPlayerView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("No video yet").font(.title2.weight(.semibold))
            Text("In the YouTube app tap Share → Copy Link, then paste it here. Or find a video in the YouTube tab.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            PasteLinkButton()
            Button { app.tab = .browse } label: { Label("Find a video on YouTube", systemImage: "magnifyingglass") }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

/// Paste a copied YouTube link (no clipboard permission prompt).
struct PasteLinkButton: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: Store
    @State private var failed = false

    var body: some View {
        VStack(spacing: 6) {
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    if let id = YouTube.videoID(from: text) {
                        failed = false
                        app.open(videoID: id, store: store, start: YouTube.startTime(from: text),
                                 playlist: YouTube.playlistID(from: text), index: YouTube.playlistIndex(from: text))
                    } else {
                        failed = true
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            if failed {
                Text("That isn't a YouTube link.").font(.caption).foregroundStyle(.red)
            }
        }
    }
}
