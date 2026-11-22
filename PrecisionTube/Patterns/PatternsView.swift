import SwiftUI

struct PatternsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case patterns = "Patterns", stitches = "Stitches", guides = "Guides"
        var id: String { rawValue }
    }

    @EnvironmentObject var store: Store
    @State private var section: Section = .patterns
    @State private var craftFilter: Craft?
    @State private var search = ""
    @State private var editing: UserPattern?

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if section != .guides {
                    Picker("Craft", selection: $craftFilter) {
                        Text("All").tag(Craft?.none)
                        Text("Crochet").tag(Craft?.some(.crochet))
                        Text("Knitting").tag(Craft?.some(.knitting))
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }

                switch section {
                case .patterns: patternsList
                case .stitches: stitchesList
                case .guides: guidesList
                }
            }
            .searchable(text: $search, prompt: Text(verbatim: section == .stitches ? "Search stitches (e.g. hdc, ssk)" : "Search"))
            .navigationTitle("Patterns")
            .navigationDestination(for: PatternContent.self) { PatternDetailView(pattern: $0) }
            .navigationDestination(for: Guide.self) { GuideView(guide: $0) }
            .toolbar {
                NavigationLink { ShapeStudioView() } label: { Label("Shape Studio", systemImage: "cube.transparent") }
                if section == .patterns {
                    Button { editing = UserPattern(title: "") } label: { Label("New pattern", systemImage: "plus") }
                }
            }
            .sheet(item: $editing) { pattern in
                PatternEditor(pattern: pattern)
            }
        }
    }

    private func matches(_ text: String...) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return text.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private func craftOK(_ craft: Craft) -> Bool { craftFilter == nil || craftFilter == craft }

    @ViewBuilder
    private var patternsList: some View {
        let mine = store.patterns.filter { craftOK($0.craft) && matches($0.title, $0.body) }
        SwiftUI.Section("My patterns") {
            if mine.isEmpty {
                Text("Tap + to type or paste a pattern. Each line becomes a row you can tick off as you go.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(mine) { pattern in
                NavigationLink(value: pattern.content) {
                    PatternRow(title: pattern.title, craft: pattern.craft, detail: "\(pattern.rows.count) rows",
                               progress: progress(pattern.content))
                }
                .swipeActions {
                    Button(role: .destructive) { store.patterns.removeAll { $0.id == pattern.id } } label: { Label("Delete", systemImage: "trash") }
                    Button { editing = pattern } label: { Label("Edit", systemImage: "pencil") }
                }
            }
        }
        SwiftUI.Section("Starter patterns") {
            ForEach(PatternLibrary.all.filter { craftOK($0.craft) && matches($0.title, $0.summary ?? "") }) { pattern in
                NavigationLink(value: pattern) {
                    PatternRow(title: pattern.title, craft: pattern.craft, detail: pattern.level ?? "", progress: progress(pattern))
                }
            }
        }
    }

    private func progress(_ pattern: PatternContent) -> Double {
        let total = pattern.rowCount
        guard total > 0 else { return 0 }
        return Double(store.progress[pattern.id]?.count ?? 0) / Double(total)
    }

    @ViewBuilder
    private var stitchesList: some View {
        let stitches = StitchGlossary.all.filter { craftOK($0.craft) && matches($0.abbr, $0.name, $0.uk ?? "", $0.how) }
        if stitches.isEmpty { Text("No stitches match.").foregroundStyle(.secondary) }
        ForEach(stitches) { StitchRow(stitch: $0) }
    }

    @ViewBuilder
    private var guidesList: some View {
        ForEach(GuideLibrary.all.filter { matches($0.title, $0.paragraphs.joined(separator: " ")) }) { guide in
            NavigationLink(value: guide) { Label(guide.title, systemImage: guide.icon) }
        }
    }
}

struct PatternRow: View {
    let title: String
    let craft: Craft
    let detail: String
    let progress: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: craft == .knitting ? "line.3.crossed.swirl.circle" : "circle.hexagongrid")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title).font(.body.weight(.semibold))
                HStack {
                    Text(craft.rawValue)
                    if !detail.isEmpty { Text("· \(detail)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if progress > 0 {
                    ProgressView(value: progress).tint(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StitchRow: View {
    let stitch: Stitch
    @EnvironmentObject var app: AppState
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(stitch.how)
                if let uk = stitch.uk {
                    Text("UK: \(uk)").font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    app.searchYouTube("how to \(stitch.craft == .knitting ? "knit" : "crochet") \(stitch.name)")
                } label: {
                    Label("Find a video of this", systemImage: "play.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(stitch.abbr).font(.body.monospaced().weight(.bold)).frame(minWidth: 70, alignment: .leading)
                Text(stitch.name)
            }
        }
    }
}

struct GuideView: View {
    let guide: Guide
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(guide.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "circle.fill").font(.system(size: 6)).padding(.top, 8).foregroundStyle(Color.accentColor)
                        Text(paragraph)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Following a pattern

struct PatternDetailView: View {
    let pattern: PatternContent
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState
    @State private var editing: UserPattern?
    @State private var confirmReset = false
    @AppStorage("patternShow3D") private var show3D = true

    /// The latest version, if it's one of the user's own patterns that has been edited.
    private var current: PatternContent {
        if let id = pattern.userPatternID, let mine = store.patterns.first(where: { $0.id == id }) { return mine.content }
        return pattern
    }

    /// Every tickable row in order: (its ID for progress, its text).
    private func orderedRows(_ p: PatternContent) -> [(id: Int, text: String)] {
        var out: [(id: Int, text: String)] = []
        var start = 0
        for section in p.sections {
            for (offset, row) in section.rows.enumerated() {
                out.append((section.ids?[offset] ?? start + offset, row))
            }
            start += section.rows.count
        }
        return out
    }

    var body: some View {
        let p = current
        let rows = orderedRows(p)
        let next = rows.first { !store.isDone(pattern: p.id, row: $0.id) }
        let reading = PatternToShape.read(p.shapeLines)
        ScrollViewReader { proxy in
        List {
            if !reading.pieces.isEmpty {
                SwiftUI.Section {
                    if show3D {
                        // What you've made so far (ticked rounds), the next round glowing, to hold
                        // up against the real thing.
                        PatternPreview3D(reading: reading,
                                         lineVisible: { store.isDone(pattern: p.id, row: $0) },
                                         highlightLine: next?.id,
                                         emptyMessage: "Tick rounds as you make them and the piece builds up here.")
                            .frame(height: 260)
                            .listRowInsets(EdgeInsets())
                    }
                    progressCounters(p, reading: reading, next: next)
                } header: {
                    HStack {
                        Text("Made so far")
                        Spacer()
                        Button(show3D ? "Hide 3D" : "Show 3D") { withAnimation { show3D.toggle() } }
                            .font(.caption)
                    }
                }
            }
            if p.summary != nil || !p.materials.isEmpty || p.notes != nil {
                SwiftUI.Section {
                    if let summary = p.summary { Text(summary) }
                    if !p.materials.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You'll need").font(.subheadline.weight(.semibold))
                            ForEach(p.materials, id: \.self) { Text("• \($0)").font(.callout) }
                        }
                    }
                    if let notes = p.notes {
                        Text(notes).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            SwiftUI.Section {
                if reading.pieces.isEmpty { counter(p) }
                if let videoID = p.videoID {
                    Button { app.open(videoID: videoID, store: store) } label: {
                        Label("Watch the video", systemImage: "play.rectangle.fill")
                    }
                }
                let pieces = PatternToShape.pieces(from: p.shapeLines)
                if !pieces.isEmpty {
                    NavigationLink {
                        PatternShapeView(title: p.title, pieces: pieces)
                    } label: {
                        Label("See it in 3D (experimental)", systemImage: "cube.transparent")
                    }
                }
                if let query = p.videoSearch {
                    Button { app.searchYouTube(query) } label: {
                        Label("Find a video tutorial", systemImage: "magnifyingglass")
                    }
                }
            }

            ForEach(Array(p.sections.enumerated()), id: \.offset) { _, section in
                let start = rowStart(p, section: section)
                SwiftUI.Section {
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { offset, row in
                        let rowID = section.ids?[offset] ?? start + offset
                        RowCheck(text: row, done: store.isDone(pattern: p.id, row: rowID), current: rowID == next?.id) {
                            store.toggle(pattern: p.id, row: rowID)
                        }
                        .id(rowID)
                    }
                } header: {
                    HStack {
                        Text(section.title)
                        if let n = section.repeatCount, n > 1 {
                            Text("Make \(n)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            nextBar(p, rows: rows, next: next, proxy: proxy)
        }
        .onAppear {
            // Open where you left off.
            if let next, next.id != rows.first?.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo(next.id, anchor: .center) }
                }
            }
        }
        }
        .navigationTitle(p.title.isEmpty ? "Pattern" : p.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let id = p.userPatternID, let mine = store.patterns.first(where: { $0.id == id }) {
                    Button("Edit") { editing = mine }
                }
                Button { confirmReset = true } label: { Image(systemName: "arrow.counterclockwise") }
            }
        }
        .confirmationDialog("Start this pattern over?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Clear ticks and counter", role: .destructive) { store.resetProgress(pattern: p.id) }
        }
        .sheet(item: $editing) { PatternEditor(pattern: $0) }
    }

    /// Where you are in the piece: which round is next and how many stitches it should have,
    /// with the round counter, under the 3D.
    @ViewBuilder
    private func progressCounters(_ p: PatternContent, reading: PatternToShape.Reading,
                                  next: (id: Int, text: String)?) -> some View {
        if let next, let piece = reading.pieces.first(where: { $0.lines.contains(next.id) }),
           let round = piece.lines.firstIndex(of: next.id) {
            let doneRounds = piece.lines.prefix(round).count
            let stitchesSoFar = piece.counts.prefix(round).reduce(0, +)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(piece.name).font(.headline)
                    Text("round \(round + 1) of \(piece.counts.count)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(piece.counts[round]) st").font(.title2.monospacedDigit().weight(.bold))
                }
                HStack(spacing: 14) {
                    Label("\(doneRounds) rounds done", systemImage: "checkmark.circle")
                    Label("\(stitchesSoFar) stitches so far", systemImage: "number")
                    if piece.repeatCount > 1 { Label("make \(piece.repeatCount)", systemImage: "square.on.square") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if next == nil {
            Label("All done!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        }
        counter(p)
    }

    /// The next row to do, with a big Done button, always on screen.
    @ViewBuilder
    private func nextBar(_ p: PatternContent, rows: [(id: Int, text: String)], next: (id: Int, text: String)?,
                         proxy: ScrollViewProxy) -> some View {
        if !rows.isEmpty {
            HStack(spacing: 12) {
                if let next {
                    Button {
                        withAnimation { proxy.scrollTo(next.id, anchor: .center) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(next.text).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("All done!", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Undo: un-tick the last ticked row before the next one.
                if let last = lastDone(p, rows: rows, before: next?.id) {
                    Button {
                        store.toggle(pattern: p.id, row: last)
                        withAnimation { proxy.scrollTo(last, anchor: .center) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Undo")
                }
                if let next {
                    Button {
                        store.toggle(pattern: p.id, row: next.id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if let after = rows.drop(while: { $0.id != next.id }).dropFirst()
                            .first(where: { !store.isDone(pattern: p.id, row: $0.id) }) {
                            withAnimation { proxy.scrollTo(after.id, anchor: .center) }
                        }
                    } label: {
                        Label("Done", systemImage: "checkmark").font(.headline).frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func lastDone(_ p: PatternContent, rows: [(id: Int, text: String)], before nextID: Int?) -> Int? {
        let upTo = nextID.flatMap { id in rows.firstIndex { $0.id == id } } ?? rows.count
        return rows[..<upTo].last { store.isDone(pattern: p.id, row: $0.id) }?.id
    }

    private func rowStart(_ p: PatternContent, section: PatternSection) -> Int {
        var n = 0
        for s in p.sections {
            if s == section { return n }
            n += s.rows.count
        }
        return n
    }

    private func counter(_ p: PatternContent) -> some View {
        let value = store.patternCounters[p.id] ?? 0
        let done = orderedRows(p).filter { store.isDone(pattern: p.id, row: $0.id) }.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Row counter").font(.subheadline.weight(.semibold))
                Text("\(done) of \(p.rowCount) steps ticked").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.patternCounters[p.id] = max(0, value - 1) } label: {
                Image(systemName: "minus").frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            Text("\(value)").font(.title.monospacedDigit().weight(.bold)).frame(minWidth: 48)
            Button {
                store.patternCounters[p.id] = value + 1
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Image(systemName: "plus").frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct RowCheck: View {
    let text: String
    let done: Bool
    var current = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : (current ? "arrow.right.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : (current ? Color.accentColor : Color.secondary))
                Text(text)
                    .fontWeight(current ? .semibold : .regular)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .strikethrough(done, color: Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(current ? Color.accentColor.opacity(0.15) : nil)
    }
}

// MARK: - Writing your own

struct PatternEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var pattern: UserPattern
    /// The pattern as read so far (updated just after you stop typing).
    @State private var reading = PatternToShape.Reading(pieces: [], colorNames: ["main"])
    @State private var cursor = 0
    @State private var showPreview = true
    /// Show the whole pattern instead of following the cursor.
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if geo.size.width > 700 {
                    // iPad / landscape: the pattern and its shape side by side.
                    HStack(spacing: 0) {
                        form
                        Divider()
                        preview.frame(width: geo.size.width * 0.45)
                    }
                } else {
                    VStack(spacing: 0) {
                        if showPreview {
                            preview.frame(height: min(300, geo.size.height * 0.4))
                            Divider()
                        }
                        form
                    }
                }
            }
            .navigationTitle(pattern.title.isEmpty ? "New pattern" : pattern.title)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: pattern.body) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                reading = PatternToShape.read(pattern.rows)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Button { withAnimation { showPreview.toggle() } } label: {
                        Label(showPreview ? "Hide 3D" : "Show 3D", systemImage: "cube.transparent")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if pattern.title.trimmingCharacters(in: .whitespaces).isEmpty { pattern.title = "My pattern" }
                        if let i = store.patterns.firstIndex(where: { $0.id == pattern.id }) {
                            store.patterns[i] = pattern
                        } else {
                            store.patterns.append(pattern)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            SwiftUI.Section {
                TextField("Name", text: $pattern.title)
                Picker("Craft", selection: $pattern.craft) {
                    ForEach(Craft.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Video", selection: $pattern.videoID) {
                    Text("None").tag(String?.none)
                    ForEach(store.recentVideos) { video in
                        Text(video.displayTitle).lineLimit(1).tag(String?.some(video.id))
                    }
                }
            }
            SwiftUI.Section {
                PatternTextView(text: $pattern.body, cursor: $cursor)
                    .frame(minHeight: 320)
            } header: {
                Text("Rows")
            } footer: {
                Text("One row or step per line, e.g. \"3. Sc, inc (18)\". The 3D crochets along as you write, up to the line you're on. Headings like \"Ears x2 (green)\" start a new piece; \"Change to white\", \"Safety eyes between 6 & 7\", \"Sew ears between rounds 4 & 6 of head\" and \"Sew the hat on top of the head\" all show up in 3D.")
            }
            SwiftUI.Section("Notes") {
                TextEditor(text: $pattern.notes).frame(minHeight: 80)
            }
        }
    }

    private var preview: some View {
        let position = PatternTextView.line(in: pattern.body, cursor: cursor)
        let upTo = position.upTo
        return PatternPreview3D(reading: reading,
                                lineVisible: showAll ? nil : { $0 <= upTo },
                                highlightLine: showAll ? nil : position.current)
            .overlay(alignment: .topTrailing) {
                Picker("Show", selection: $showAll) {
                    Text("So far").tag(false)
                    Text("All").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .padding(8)
            }
    }
}
