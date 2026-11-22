import SwiftUI
import UIKit

/// The 3D preview of a pattern, made as far as `lineVisible` says, with the round on
/// `highlightLine` glowing. Shows a dot for each yarn the pattern names (tap to change it) and Flip.
struct PatternPreview3D: View {
    let reading: PatternToShape.Reading
    var lineVisible: ((Int) -> Bool)?
    var highlightLine: Int?
    var emptyMessage = "Type rounds with their stitch counts, like \"1. 6 sc in MR (6)\", and the piece takes shape here."

    @State private var flip: Bool?
    @State private var overrides: [Int: Color] = [:]

    private var palette: [Color] {
        YarnColor.palette(for: reading.colorNames).enumerated().map { i, c in
            overrides[i] ?? Color(red: c.0, green: c.1, blue: c.2)
        }
    }

    var body: some View {
        let assembly = Assembly.build(pieces: reading.pieces, gauge: Gauge(), flip: flip,
                                      lineVisible: lineVisible, highlightLine: highlightLine)
        ZStack(alignment: .bottom) {
            if assembly.parts.isEmpty {
                Color(.secondarySystemBackground)
                VStack(spacing: 6) {
                    Image(systemName: "cube.transparent").font(.title)
                    Text(emptyMessage).font(.footnote).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AssemblySceneView(assembly: assembly, palette: palette.map { UIColor($0) })
                HStack(spacing: 6) {
                    // One dot per yarn the pattern uses (the first, "main", only if something's in it).
                    ForEach(usedColors, id: \.self) { i in
                        ColorPicker(selection: Binding(get: { palette[i] }, set: { overrides[i] = $0 }), supportsOpacity: false) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .accessibilityLabel("Colour \(reading.colorNames[i])")
                    }
                    Spacer()
                    Text("experimental").font(.caption2).foregroundStyle(.secondary)
                    Button { flip = !assembly.mainTopDown } label: {
                        Label("Flip", systemImage: "arrow.up.arrow.down").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(6)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var usedColors: [Int] {
        let used = Set(reading.pieces.flatMap(\.colors))
        return reading.colorNames.indices.filter { used.contains($0) }.prefix(6).map { $0 }
    }
}

/// A plain-text editor that reports which line the cursor is on, so the 3D preview can follow it.
struct PatternTextView: UIViewRepresentable {
    @Binding var text: String
    /// Cursor position (UTF-16 offset).
    @Binding var cursor: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.text = text
        view.delegate = context.coordinator
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PatternTextView
        init(_ parent: PatternTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.cursor = textView.selectedRange.location
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.cursor = textView.selectedRange.location
        }
    }

    /// Which pattern line (index among the non-blank lines, as the pattern reader numbers them)
    /// the cursor is on; nil on a blank line. `upTo` is the last line at or before the cursor.
    static func line(in text: String, cursor: Int) -> (current: Int?, upTo: Int) {
        let ns = text as NSString
        let offset = min(max(0, cursor), ns.length)
        let before = ns.substring(to: offset)
        let lineStart = (before as NSString).range(of: "\n", options: .backwards).location
        let fullLinesBefore = lineStart == NSNotFound ? "" : (before as NSString).substring(to: lineStart)
        let index = fullLinesBefore.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let lineEnd = ns.range(of: "\n", options: [], range: NSRange(location: offset, length: ns.length - offset)).location
        let start = lineStart == NSNotFound ? 0 : lineStart + 1
        let end = lineEnd == NSNotFound ? ns.length : lineEnd
        let currentText = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
        let blank = currentText.trimmingCharacters(in: .whitespaces).isEmpty
        return (blank ? nil : index, blank ? index - 1 : index)
    }
}
