import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState
    @State private var linkText = ""
    @State private var showFavoritesOnly = false
    @FocusState private var linkFocused: Bool

    private var videos: [SavedVideo] {
        let all = store.recentVideos
        return showFavoritesOnly ? all.filter(\.favorite) : all
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Open a YouTube video").font(.headline)
                        Text("In the YouTube app: Share → Copy Link, then tap Paste.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            PasteLinkButton()
                            Button { app.tab = .browse } label: {
                                Label("Search YouTube", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                        }
                        HStack {
                            TextField("…or type a link", text: $linkText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($linkFocused)
                                .onSubmit(openTyped)
                            Button("Open", action: openTyped)
                                .buttonStyle(.borderedProminent)
                                .disabled(YouTube.videoID(from: linkText) == nil)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if videos.isEmpty {
                        Text(showFavoritesOnly ? "No favorites yet. Star a video from the player's ⋯ menu." : "Videos you open show up here, and reopen where you left off.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(videos) { video in
                        Button { app.open(videoID: video.id, store: store) } label: { VideoRow(video: video) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.deleteVideo(video.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { store.updateVideo(video.id) { $0.favorite.toggle() } } label: {
                                    Label(video.favorite ? "Unstar" : "Star", systemImage: video.favorite ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                            }
                            .contextMenu {
                                Button { app.open(videoID: video.id, store: store, start: 0) } label: { Label("Play from the start", systemImage: "backward.end") }
                                Button { store.updateVideo(video.id) { $0.favorite.toggle() } } label: { Label(video.favorite ? "Unstar" : "Star", systemImage: "star") }
                                Button(role: .destructive) { store.deleteVideo(video.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Text(showFavoritesOnly ? "Favorites" : "Recent")
                        Spacer()
                        Picker("Show", selection: $showFavoritesOnly) {
                            Text("All").tag(false)
                            Image(systemName: "star.fill").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                }
            }
            .navigationTitle("Videos")
        }
    }

    private func openTyped() {
        guard let id = YouTube.videoID(from: linkText) else { return }
        let start = YouTube.startTime(from: linkText)
        linkText = ""
        linkFocused = false
        app.open(videoID: id, store: store, start: start)
    }
}

struct VideoRow: View {
    let video: SavedVideo

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                Color(.tertiarySystemFill)
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                if video.lastPosition > 1 {
                    Text(TimeFormat.short(video.lastPosition))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(video.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if video.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                }
                if let author = video.author {
                    Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if !video.markers.isEmpty {
                    Label("\(video.markers.count) mark\(video.markers.count == 1 ? "" : "s")", systemImage: "bookmark.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
