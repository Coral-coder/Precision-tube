import SwiftUI

/// A tape-style timeline: the playhead stays in the middle and you drag the tape under it.
/// Pinch (or use the zoom buttons) to change how many seconds fit across; zoomed in far
/// enough it draws one tick per video frame.
struct PrecisionTimeline: View {
    @EnvironmentObject var player: PlayerController
    @Binding var span: Double
    var markers: [VideoMarker]

    @State private var dragStartTime: Double?
    @State private var scrubTime: Double?
    @State private var pinchStartSpan: Double?

    private var displayTime: Double { scrubTime ?? player.currentTime }

    static let minSpan = 0.25
    private var maxSpan: Double { max(10, player.duration) }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchStartSpan == nil { pinchStartSpan = span }
                        let new = (pinchStartSpan ?? span) / Double(max(value.magnification, 0.05))
                        span = min(max(new, Self.minSpan), maxSpan)
                    }
                    .onEnded { _ in pinchStartSpan = nil }
            )
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Timeline")
        .accessibilityValue(TimeFormat.precise(displayTime))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartTime == nil {
                    dragStartTime = player.currentTime
                    if player.isPlaying { player.pause() }
                }
                let pps = Double(width) / span
                let t = clamp((dragStartTime ?? 0) - Double(value.translation.width) / pps)
                scrubTime = t
                player.seek(to: t)
            }
            .onEnded { value in
                let pps = Double(width) / span
                if abs(value.translation.width) < 3, abs(value.translation.height) < 3 {
                    // A tap: jump to where you tapped.
                    let t = clamp((dragStartTime ?? player.currentTime) + Double(value.location.x - width / 2) / pps)
                    player.seek(to: t)
                }
                dragStartTime = nil
                scrubTime = nil
            }
    }

    private func clamp(_ t: Double) -> Double {
        let upper = player.duration > 0 ? player.duration : .greatestFiniteMagnitude
        return min(max(0, t), upper)
    }

    // MARK: Drawing

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let pps = Double(w) / span
        let t0 = displayTime - span / 2
        let t1 = displayTime + span / 2
        func x(_ t: Double) -> CGFloat { CGFloat((t - t0) * pps) }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.secondarySystemBackground)))

        // Outside the video: darker.
        if t0 < 0 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: x(0), height: h)), with: .color(.black.opacity(0.25)))
        }
        if player.duration > 0, t1 > player.duration {
            let start = x(player.duration)
            ctx.fill(Path(CGRect(x: start, y: 0, width: w - start, height: h)), with: .color(.black.opacity(0.25)))
        }

        // Loop region.
        if let a = player.loopA {
            let b = player.loopB ?? a
            let rect = CGRect(x: x(a), y: 0, width: max(2, x(b) - x(a)), height: h)
            ctx.fill(Path(rect), with: .color(Color.green.opacity(player.loopOn ? 0.28 : 0.14)))
        }

        let fps = player.fps
        let frameWidth = pps / fps
        let tickColor = Color.primary.opacity(0.55)

        if frameWidth >= 5 {
            // One tick per frame, a tall tick on each whole second.
            let first = Int((max(0, t0) * fps).rounded(.down))
            let last = Int((t1 * fps).rounded(.up))
            if last - first < 3000 {
                for k in first...max(first, last) {
                    let t = Double(k) / fps
                    if player.duration > 0, t > player.duration { break }
                    let px = x(t)
                    let secondFrame = abs(t - t.rounded()) < 0.5 / fps
                    let tickH: CGFloat = secondFrame ? h * 0.5 : h * 0.22
                    ctx.fill(Path(CGRect(x: px - 0.5, y: h - tickH, width: 1, height: tickH)),
                             with: .color(secondFrame ? Color.primary : tickColor))
                    let label: String?
                    if secondFrame { label = TimeFormat.short(t.rounded()) }
                    else if frameWidth >= 34 { label = "\(k % Int(fps.rounded()))" }
                    else { label = nil }
                    if let label {
                        ctx.draw(Text(label).font(.system(size: secondFrame ? 11 : 9, weight: secondFrame ? .semibold : .regular).monospacedDigit())
                                    .foregroundColor(.secondary),
                                 at: CGPoint(x: px, y: h * 0.32))
                    }
                }
            }
        } else {
            let steps: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
            let minor = steps.first { $0 * pps >= 8 } ?? 3600
            let major = steps.first { $0 * pps >= 70 && $0 >= minor } ?? 3600
            var t = (max(0, t0) / minor).rounded(.down) * minor
            var count = 0
            while t <= t1, count < 3000 {
                if player.duration > 0, t > player.duration { break }
                let px = x(t)
                let isMajor = abs((t / major) - (t / major).rounded()) < 0.001
                let tickH: CGFloat = isMajor ? h * 0.5 : h * 0.22
                ctx.fill(Path(CGRect(x: px - 0.5, y: h - tickH, width: 1, height: tickH)),
                         with: .color(isMajor ? Color.primary : tickColor))
                if isMajor {
                    let label = major < 1 ? String(format: "%.2fs", t) : TimeFormat.short(t)
                    ctx.draw(Text(label).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundColor(.secondary),
                             at: CGPoint(x: px, y: h * 0.32))
                }
                t += minor
                count += 1
            }
        }

        // Markers.
        for marker in markers where marker.time >= t0 && marker.time <= t1 {
            let px = x(marker.time)
            ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: h)), with: .color(.orange))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 5, y: 2, width: 10, height: 10)), with: .color(.orange))
        }

        // Playhead.
        let mid = w / 2
        ctx.fill(Path(CGRect(x: mid - 1.25, y: 0, width: 2.5, height: h)), with: .color(.red))
        var tri = Path()
        tri.move(to: CGPoint(x: mid - 8, y: 0))
        tri.addLine(to: CGPoint(x: mid + 8, y: 0))
        tri.addLine(to: CGPoint(x: mid, y: 10))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(.red))
    }
}

/// The whole video at a glance: tap or drag anywhere to jump there.
struct OverviewBar: View {
    @EnvironmentObject var player: PlayerController
    var markers: [VideoMarker]
    var span: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let d = max(player.duration, 0.001)
            let x: (Double) -> CGFloat = { t in CGFloat(t / d) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(0, min(w, x(player.currentTime))))
                if let a = player.loopA {
                    Rectangle().fill(Color.green.opacity(0.5))
                        .frame(width: max(2, x(player.loopB ?? a) - x(a)))
                        .offset(x: x(a))
                }
                // The part the zoomed timeline shows.
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
                    .frame(width: max(4, min(w, x(span))))
                    .offset(x: max(0, x(player.currentTime - span / 2)))
                ForEach(markers) { marker in
                    Rectangle().fill(Color.orange).frame(width: 2).offset(x: x(marker.time) - 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if player.isPlaying { player.pause() }
                player.seek(to: Double(max(0, min(w, value.location.x)) / w) * d)
            })
        }
        .frame(height: 22)
    }
}
