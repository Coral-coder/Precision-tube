import SwiftUI
import UniformTypeIdentifiers

/// Turn a 3D shape into an amigurumi pattern, or a round-by-round pattern into a 3D preview.
struct ShapeStudioView: View {
    enum Source: String, CaseIterable, Identifiable {
        case shape = "Shape", file = "3D file", pattern = "Pattern"
        var id: String { rawValue }
    }

    @EnvironmentObject var store: Store
    @State private var source: Source = .shape
    @State private var primitive: ShapePrimitive = .ball
    @State private var width = 8.0
    @State private var height = 8.0
    @State private var gauge = Gauge()
    @State private var yarn = Color(red: 0.93, green: 0.55, blue: 0.68)
    @State private var showGhost = true

    // 3D file
    @State private var importing = false
    @State private var fileName: String?
    @State private var triangles: [SIMD3<Float>] = []
    @State private var axis: MeshAxis = .y
    @State private var meshProfile: Profile?          // height 1
    @State private var fileHeight = 10.0
    @State private var loadingFile = false
    @State private var fileError: String?

    // Pattern
    @State private var patternID: String?

    @State private var saved = false

    private struct StudioResult {
        var counts: [Int]
        var rows: [String]
        var ghost: Profile?
        var title: String
    }

    private var parseablePatterns: [PatternContent] {
        (store.patterns.map(\.content) + PatternLibrary.all).filter {
            PatternToShape.roundCounts(from: $0.sections.flatMap(\.rows)) != nil
        }
    }

    private var result: StudioResult? {
        switch source {
        case .shape:
            let profile = primitive.profile(width: width, height: height)
            let counts = ShapeToPattern.counts(for: profile, gauge: gauge)
            return StudioResult(counts: counts, rows: ShapeToPattern.pattern(for: counts).rows, ghost: profile,
                          title: "\(primitive.rawValue) \(format(width))×\(format(height)) cm")
        case .file:
            guard let meshProfile else { return nil }
            let profile = meshProfile.scaled(by: fileHeight)
            let counts = ShapeToPattern.counts(for: profile, gauge: gauge)
            return StudioResult(counts: counts, rows: ShapeToPattern.pattern(for: counts).rows, ghost: profile,
                          title: "\((fileName ?? "Model") as String) \(format(fileHeight)) cm")
        case .pattern:
            guard let id = patternID ?? parseablePatterns.first?.id,
                  let pattern = parseablePatterns.first(where: { $0.id == id }),
                  let counts = PatternToShape.roundCounts(from: pattern.sections.flatMap(\.rows)) else { return nil }
            return StudioResult(counts: counts, rows: [], ghost: nil, title: pattern.title)
        }
    }

    var body: some View {
        let res = result
        let model = res.map { StitchModel.from(counts: $0.counts, gauge: gauge) }
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let preview = previewPane(model: model, ghost: showGhost ? res?.ghost : nil)
            if wide {
                HStack(spacing: 0) {
                    preview.frame(width: geo.size.width * 0.55)
                    form(res, model: model)
                }
            } else {
                VStack(spacing: 0) {
                    preview.frame(height: geo.size.height * 0.42)
                    form(res, model: model)
                }
            }
        }
        .navigationTitle("Shape Studio")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.modelTypes) { picked in
            if case .success(let url) = picked { load(url) }
        }
        .onChange(of: axis) { _, _ in reslice() }
    }

    static let modelTypes: [UTType] = {
        var types: [UTType] = [.usdz, .usd, .threeDContent]
        for ext in ["obj", "stl", "ply", "abc"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }()

    @ViewBuilder
    private func previewPane(model: StitchModel?, ghost: Profile?) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let model, !model.bands.isEmpty {
                ShapeSceneView(model: model, ghost: ghost, yarn: UIColor(yarn))
            } else {
                Color(.secondarySystemBackground)
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent").font(.largeTitle)
                    Text(emptyMessage).multilineTextAlignment(.center).font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            if let model, !model.bands.isEmpty {
                Text("Drag to turn · pinch to zoom")
                    .font(.caption2)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
        }
    }

    private var emptyMessage: String {
        switch source {
        case .shape: return "Pick a shape."
        case .file: return loadingFile ? "Measuring the model…" : "Import a 3D model (USDZ, OBJ, STL or PLY) and it becomes a pattern."
        case .pattern: return "None of your patterns are written round by round with stitch counts like (18). Add one in Patterns, or try the Amigurumi Ball."
        }
    }

    private func form(_ res: StudioResult?, model: StitchModel?) -> some View {
        Form {
            Section {
                Picker("Start from", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch source {
                case .shape: shapeControls
                case .file: fileControls
                case .pattern: patternControls
                }
            }

            Section {
                Stepper(value: $gauge.stitchesPer10cm, in: 8...40, step: 1) {
                    LabeledContent("Stitches per 10 cm", value: format(gauge.stitchesPer10cm))
                }
                Stepper(value: $gauge.roundsPer10cm, in: 8...40, step: 1) {
                    LabeledContent("Rounds per 10 cm", value: format(gauge.roundsPer10cm))
                }
                ColorPicker("Yarn color", selection: $yarn, supportsOpacity: false)
                if source != .pattern { Toggle("Show the target shape", isOn: $showGhost) }
            } header: {
                Text("Your gauge (single crochet)")
            } footer: {
                Text("Worsted yarn with a 3.5–4 mm hook is about 20 × 20. Crochet a small swatch to check yours.")
            }

            if let res, let model, !res.counts.isEmpty {
                Section("Result") {
                    LabeledContent("Rounds", value: "\(res.counts.count)")
                    LabeledContent("Widest round", value: "\(res.counts.max() ?? 0) stitches")
                    LabeledContent("Finished size", value: "about \(format(model.maxRadius * 2)) × \(format(model.height)) cm")
                    LabeledContent("Total stitches", value: "\(model.totalStitches)")
                }
                if source != .pattern {
                    Section {
                        ForEach(Array(res.rows.enumerated()), id: \.offset) { _, row in
                            Text(row).font(.callout)
                        }
                        Button {
                            store.patterns.append(UserPattern(
                                title: res.title, craft: .crochet,
                                notes: "Made in Shape Studio for a gauge of \(format(gauge.stitchesPer10cm)) stitches × \(format(gauge.roundsPer10cm)) rounds per 10 cm. US terms, worked in a continuous spiral; use a stitch marker. inc = 2 sc in one stitch, dec = sc2tog (invisible decrease looks best).",
                                body: res.rows.joined(separator: "\n")))
                            saved = true
                        } label: {
                            Label(saved ? "Saved to My patterns" : "Save to My patterns", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        }
                        .disabled(saved)
                        ShareLink(item: ([res.title, ""] + res.rows).joined(separator: "\n")) {
                            Label("Share the pattern", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Pattern")
                    } footer: {
                        Text("Single crochet in a spiral. The preview shows each stitch as a patch, so you can see how the rounds will shape the piece.")
                    }
                } else {
                    Section {
                        Text("The preview is built from the stitch count of each round: increases flare the fabric out, decreases pull it in.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: res?.rows ?? []) { _, _ in saved = false }
    }

    @ViewBuilder
    private var shapeControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShapePrimitive.allCases) { p in
                    Button {
                        primitive = p
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: p.icon).font(.title2)
                            Text(p.rawValue).font(.caption)
                        }
                        .frame(width: 64, height: 56)
                    }
                    .buttonStyle(.bordered)
                    .tint(primitive == p ? Color.accentColor : Color.gray)
                }
            }
        }
        sizeSlider("Width", value: $width)
        sizeSlider("Height", value: $height)
    }

    @ViewBuilder
    private var fileControls: some View {
        Button { importing = true } label: {
            Label(fileName == nil ? "Import a 3D model" : "Choose a different model", systemImage: "square.and.arrow.down.on.square")
        }
        if let fileName { LabeledContent("Model", value: fileName) }
        if loadingFile { ProgressView("Measuring…") }
        if let fileError { Text(fileError).foregroundStyle(.red).font(.callout) }
        if !triangles.isEmpty {
            Picker("Which way is up", selection: $axis) {
                ForEach(MeshAxis.allCases) { Text($0.rawValue).tag($0) }
            }
            sizeSlider("Height", value: $fileHeight)
            Text("Works best with one rounded piece (a head, a body, a fruit). Make arms, legs and ears as separate pieces.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var patternControls: some View {
        if parseablePatterns.isEmpty {
            Text("No round-by-round patterns yet.").foregroundStyle(.secondary)
        } else {
            Picker("Pattern", selection: Binding(get: { patternID ?? parseablePatterns.first?.id ?? "" },
                                                 set: { patternID = $0 })) {
                ForEach(parseablePatterns) { Text($0.title).tag($0.id) }
            }
        }
    }

    private func sizeSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(label, value: "\(format(value.wrappedValue)) cm")
            Slider(value: value, in: 2...40, step: 0.5)
        }
    }

    private func format(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(0...1))) }

    // MARK: Loading a model

    private func load(_ url: URL) {
        fileError = nil
        loadingFile = true
        fileName = url.deletingPathExtension().lastPathComponent
        let axis = self.axis
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Swift.Result<([SIMD3<Float>], Profile?), Error> in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    // Model I/O wants a real file it can read next to its textures; copy it in.
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: copy)
                    try FileManager.default.copyItem(at: url, to: copy)
                    let tris = try MeshSlicer.triangles(from: copy)
                    return .success((tris, MeshSlicer.normalizedProfile(triangles: tris, axis: axis)))
                } catch {
                    return .failure(error)
                }
            }.value
            loadingFile = false
            switch outcome {
            case .success(let (tris, profile)):
                triangles = tris
                meshProfile = profile
                if profile == nil { fileError = "Couldn't measure that model." }
            case .failure(let error):
                triangles = []
                meshProfile = nil
                fileError = error.localizedDescription
            }
        }
    }

    private func reslice() {
        guard !triangles.isEmpty else { return }
        let tris = triangles, axis = self.axis
        loadingFile = true
        Task {
            let profile = await Task.detached(priority: .userInitiated) { () -> Profile? in
                MeshSlicer.normalizedProfile(triangles: tris, axis: axis)
            }.value
            meshProfile = profile
            loadingFile = false
        }
    }
}

/// The 3D preview for one pattern (from the pattern's page).
struct PatternShapeView: View {
    let title: String
    let counts: [Int]
    @State private var gauge = Gauge()
    @State private var yarn = Color(red: 0.93, green: 0.55, blue: 0.68)

    var body: some View {
        let model = StitchModel.from(counts: counts, gauge: gauge)
        VStack(spacing: 0) {
            ShapeSceneView(model: model, ghost: nil, yarn: UIColor(yarn))
            Form {
                LabeledContent("Rounds", value: "\(counts.count)")
                LabeledContent("Finished size", value: "about \(String(format: "%.1f", model.maxRadius * 2)) × \(String(format: "%.1f", model.height)) cm")
                Stepper(value: $gauge.stitchesPer10cm, in: 8...40) {
                    LabeledContent("Stitches per 10 cm", value: "\(Int(gauge.stitchesPer10cm))")
                }
                Stepper(value: $gauge.roundsPer10cm, in: 8...40) {
                    LabeledContent("Rounds per 10 cm", value: "\(Int(gauge.roundsPer10cm))")
                }
                ColorPicker("Yarn color", selection: $yarn, supportsOpacity: false)
            }
            .frame(maxHeight: 300)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
