import SwiftUI

struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    CountersSection()
                } header: {
                    Text("Counters")
                } footer: {
                    Text("The first counter also appears under the video in the Player.")
                }
                Section("Calculators") {
                    NavigationLink { IncreaseEvenlyView() } label: { Label("Increase / decrease evenly", systemImage: "arrow.up.and.down.text.horizontal") }
                    NavigationLink { GaugeView() } label: { Label("Gauge calculator", systemImage: "ruler") }
                }
                Section("Charts") {
                    NavigationLink { HookSizesView() } label: { Label("Hook & needle sizes", systemImage: "pencil.and.ruler") }
                    NavigationLink { YarnWeightsView() } label: { Label("Yarn weights", systemImage: "scalemass") }
                    NavigationLink { TermsView() } label: { Label("US ↔ UK crochet terms", systemImage: "globe") }
                }
            }
            .navigationTitle("Tools")
        }
    }
}

// MARK: - Counters

struct CountersSection: View {
    @EnvironmentObject var store: Store
    @State private var renaming: StitchCounter?
    @State private var name = ""

    var body: some View {
        ForEach($store.counters) { $counter in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(counter.name).font(.headline)
                    Spacer()
                    Menu {
                        Button("Rename") { name = counter.name; renaming = counter }
                        Button("Reset to 0") { counter.count = 0 }
                        Button("Delete", role: .destructive) {
                            let id = counter.id
                            DispatchQueue.main.async { store.counters.removeAll { $0.id == id } }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                HStack(spacing: 14) {
                    Button { if counter.count > 0 { counter.count -= 1 } } label: {
                        Image(systemName: "minus").font(.title2.weight(.bold)).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    Text("\(counter.count)")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(minWidth: 90)
                        .contentTransition(.numericText())
                    Button {
                        counter.count += 1
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "plus").font(.title2.weight(.bold)).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 6)
        }
        Button {
            store.counters.append(StitchCounter(name: "Counter \(store.counters.count + 1)"))
        } label: {
            Label("Add a counter", systemImage: "plus.circle")
        }
        .alert("Rename counter", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                if let target = renaming, let i = store.counters.firstIndex(where: { $0.id == target.id }) {
                    store.counters[i].name = name.isEmpty ? "Counter" : name
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

// MARK: - Increase / decrease evenly

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

struct IncreaseEvenlyView: View {
    @State private var stitches = 24
    @State private var change = 6
    @State private var craft: Craft = .crochet

    var body: some View {
        Form {
            Picker("Craft", selection: $craft) {
                Text("Crochet").tag(Craft.crochet)
                Text("Knitting").tag(Craft.knitting)
            }
            .pickerStyle(.segmented)
            Stepper(value: $stitches, in: 1...999) {
                LabeledContent("Stitches now", value: "\(stitches)")
            }
            Stepper(value: $change, in: -500...500) {
                LabeledContent(change >= 0 ? "Increase by" : "Decrease by", value: "\(abs(change))")
            }
            Section("Work this") {
                if let text = EvenlyCalculator.instructions(stitches: stitches, change: change, craft: craft) {
                    Text(text).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text("You'll end with \(stitches + change) stitches.").foregroundStyle(.secondary)
                } else {
                    Text("Pick a number to increase or decrease by.").foregroundStyle(.secondary)
                }
            }
            Section {
                Text(craft == .crochet
                     ? "inc = 2 sc in the same stitch. dec = sc2tog. Swap sc for hdc or dc if that's your stitch."
                     : "M1 = make one (lift the bar between stitches). k2tog = knit two together.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Increase evenly")
    }
}

// MARK: - Gauge

struct GaugeView: View {
    @State private var metric = false
    @State private var swatchStitches = 18.0
    @State private var swatchRows = 24.0
    @State private var width = 20.0
    @State private var height = 8.0

    private var swatchSize: Double { metric ? 10 : 4 }
    private var unit: String { metric ? "cm" : "in" }

    var body: some View {
        Form {
            Picker("Units", selection: $metric) {
                Text("Inches").tag(false)
                Text("Centimeters").tag(true)
            }
            .pickerStyle(.segmented)
            Section("Your swatch (per \(Int(swatchSize)) \(unit))") {
                numberRow("Stitches", value: $swatchStitches)
                numberRow("Rows", value: $swatchRows)
            }
            Section("Piece you want") {
                numberRow("Width (\(unit))", value: $width)
                numberRow("Height (\(unit))", value: $height)
            }
            Section("Result") {
                let sts = Int((swatchStitches / swatchSize * width).rounded())
                let rows = Int((swatchRows / swatchSize * height).rounded())
                LabeledContent("Stitches across", value: "\(sts)")
                LabeledContent("Rows", value: "\(rows)")
                Text("If the pattern needs a stitch multiple (like 4 + 2), round to the nearest one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gauge")
    }

    private func numberRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}

// MARK: - Charts

struct HookSizesView: View {
    private let hooks: [(String, String, String)] = [
        ("2.25 mm", "B-1", "13"), ("2.75 mm", "C-2", "12"), ("3.25 mm", "D-3", "10"), ("3.5 mm", "E-4", "9"),
        ("3.75 mm", "F-5", "9"), ("4 mm", "G-6", "8"), ("4.5 mm", "7", "7"), ("5 mm", "H-8", "6"),
        ("5.5 mm", "I-9", "5"), ("6 mm", "J-10", "4"), ("6.5 mm", "K-10½", "3"), ("8 mm", "L-11", "0"),
        ("9 mm", "M/N-13", "00"), ("10 mm", "N/P-15", "000"), ("15 mm", "P/Q", "–"), ("16 mm", "Q", "–"), ("19 mm", "S", "–"),
    ]
    private let needles: [(String, String)] = [
        ("2 mm", "0"), ("2.25 mm", "1"), ("2.75 mm", "2"), ("3.25 mm", "3"), ("3.5 mm", "4"), ("3.75 mm", "5"),
        ("4 mm", "6"), ("4.5 mm", "7"), ("5 mm", "8"), ("5.5 mm", "9"), ("6 mm", "10"), ("6.5 mm", "10½"),
        ("8 mm", "11"), ("9 mm", "13"), ("10 mm", "15"), ("12.75 mm", "17"), ("15 mm", "19"), ("19 mm", "35"), ("25 mm", "50"),
    ]

    var body: some View {
        List {
            Section("Crochet hooks") {
                row("Metric", "US", "Old UK", header: true)
                ForEach(hooks.indices, id: \.self) { i in row(hooks[i].0, hooks[i].1, hooks[i].2) }
            }
            Section("Knitting needles") {
                row("Metric", "US", "", header: true)
                ForEach(needles.indices, id: \.self) { i in row(needles[i].0, needles[i].1, "") }
            }
        }
        .navigationTitle("Hook & needle sizes")
    }

    private func row(_ a: String, _ b: String, _ c: String, header: Bool = false) -> some View {
        HStack {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(maxWidth: .infinity, alignment: .leading)
            Text(c).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(header ? .caption.weight(.semibold) : .body.monospacedDigit())
        .foregroundStyle(header ? Color.secondary : Color.primary)
    }
}

struct YarnWeightsView: View {
    private let weights: [(String, String, String, String, String)] = [
        ("0", "Lace", "Fingering, 10-count thread", "1.5–2.25 mm", "Steel 1.4 mm–2.25 mm"),
        ("1", "Super Fine", "Sock, fingering, baby", "2.25–3.25 mm (US 1–3)", "2.25–3.5 mm (B-1 to E-4)"),
        ("2", "Fine", "Sport, baby", "3.25–3.75 mm (US 3–5)", "3.5–4.5 mm (E-4 to 7)"),
        ("3", "Light", "DK, light worsted", "3.75–4.5 mm (US 5–7)", "4.5–5.5 mm (7 to I-9)"),
        ("4", "Medium", "Worsted, afghan, aran", "4.5–5.5 mm (US 7–9)", "5.5–6.5 mm (I-9 to K-10½)"),
        ("5", "Bulky", "Chunky, craft, rug", "5.5–8 mm (US 9–11)", "6.5–9 mm (K-10½ to M-13)"),
        ("6", "Super Bulky", "Super chunky, roving", "8–12.75 mm (US 11–17)", "9–15 mm (M-13 to Q)"),
        ("7", "Jumbo", "Jumbo, roving", "12.75 mm+ (US 17+)", "15 mm+ (Q+)"),
    ]

    var body: some View {
        List {
            ForEach(weights.indices, id: \.self) { i in
                let w = weights[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(w.0).font(.headline).frame(width: 28, height: 28).background(Circle().fill(Color.accentColor.opacity(0.2)))
                        Text(w.1).font(.headline)
                    }
                    Text(w.2).font(.callout).foregroundStyle(.secondary)
                    Label("Needles \(w.3)", systemImage: "line.diagonal").font(.caption)
                    Label("Hook \(w.4)", systemImage: "scribble").font(.caption)
                }
                .padding(.vertical, 2)
            }
            Text("From the Craft Yarn Council standard. The label on the yarn is the best guide.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Yarn weights")
    }
}

struct TermsView: View {
    private let terms: [(String, String)] = [
        ("slip stitch (sl st)", "slip stitch (ss)"),
        ("single crochet (sc)", "double crochet (dc)"),
        ("half double crochet (hdc)", "half treble (htr)"),
        ("double crochet (dc)", "treble (tr)"),
        ("treble (tr)", "double treble (dtr)"),
        ("double treble (dtr)", "triple treble (trtr)"),
        ("skip", "miss"),
        ("yarn over (yo)", "yarn round hook (yrh)"),
        ("gauge", "tension"),
    ]

    var body: some View {
        List {
            Section {
                HStack {
                    Text("US").frame(maxWidth: .infinity, alignment: .leading)
                    Text("UK").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(terms.indices, id: \.self) { i in
                    let t = terms[i]
                    HStack {
                        Text(t.0).frame(maxWidth: .infinity, alignment: .leading)
                        Text(t.1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } footer: {
                Text("Tip: if a pattern has 'double crochet' but never mentions 'single crochet', it's probably UK terms.")
            }
        }
        .navigationTitle("US ↔ UK terms")
    }
}
