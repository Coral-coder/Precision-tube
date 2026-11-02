import SwiftUI
import UIKit

/// The app's color, chosen in Tools → App color. Stored as a hex string.
enum Theme {
    static let storageKey = "themeColorHex"
    static let defaultHex = "#1F8A8F"

    struct Preset: Hashable {
        var name: String
        var hex: String
        init(_ name: String, _ hex: String) { self.name = name; self.hex = hex }
    }

    static let presets: [Preset] = [
        Preset("Teal", "#1F8A8F"), Preset("Ocean", "#2F6FD6"), Preset("Lavender", "#8A63D2"), Preset("Plum", "#9C3D8F"),
        Preset("Rose", "#D9487A"), Preset("Coral", "#E8664A"), Preset("Marigold", "#E0A21B"), Preset("Sage", "#5E9B5A"),
        Preset("Forest", "#2E7350"), Preset("Slate", "#53657A"), Preset("Cocoa", "#8A5A3C"), Preset("Charcoal", "#3A3A40"),
    ]

    static func color(hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return color(hex: defaultHex) }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

struct ThemeColorPicker: View {
    @AppStorage(Theme.storageKey) private var hex = Theme.defaultHex

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                ForEach(Theme.presets, id: \.hex) { preset in
                    Button { hex = preset.hex } label: {
                        Circle()
                            .fill(Theme.color(hex: preset.hex))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if preset.hex.caseInsensitiveCompare(hex) == .orderedSame {
                                    Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            ColorPicker("Any color", selection: Binding(get: { Theme.color(hex: hex) }, set: { hex = Theme.hex($0) }),
                        supportsOpacity: false)
        }
        .padding(.vertical, 4)
    }
}
