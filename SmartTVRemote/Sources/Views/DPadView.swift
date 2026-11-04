import SwiftUI

/// Cruceta circular con botón central OK. Responde al tocar (no al soltar) y repite al mantener pulsada una flecha.
struct DPadView: View {
    @ObservedObject var viewModel: RemoteViewModel

    fileprivate enum Zone: CaseIterable { case up, right, down, left, ok
        var key: AndroidKey {
            switch self {
            case .up: return .dpadUp
            case .down: return .dpadDown
            case .left: return .dpadLeft
            case .right: return .dpadRight
            case .ok: return .dpadCenter
            }
        }
    }

    @State private var active: Zone?
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let okFraction: CGFloat = 0.38
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.dpadTop, Palette.dpadBottom], startPoint: .top, endPoint: .bottom))
                    .glassSurface(Circle())
                // Sectores
                ForEach([Zone.up, .right, .down, .left], id: \.self) { zone in
                    RingSector(zone: zone.angle, innerRatio: okFraction * 0.5 + 0.03)
                        .fill(active == zone ? Palette.surfacePressed : .clear)
                        .animation(.easeOut(duration: 0.12), value: active)
                    Image(systemName: zone.symbol)
                        .font(.system(size: size * 0.085, weight: .bold))
                        .foregroundStyle(Palette.primaryText.opacity(active == zone ? 1 : 0.8))
                        .offset(zone.offset(radius: size * 0.37))
                        .allowsHitTesting(false)
                }
                // OK
                Text("OK")
                    .font(.system(size: size * 0.085, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size * okFraction, height: size * okFraction)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Palette.accent.opacity(active == .ok ? 0.2 : 0.5), radius: active == .ok ? 4 : 14, y: 4)
                    .scaleEffect(active == .ok ? 0.93 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: active)
                    .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard active == nil else { return }
                        let zone = zone(at: value.startLocation, in: CGSize(width: size, height: size),
                                        origin: CGPoint(x: (geo.size.width - size) / 2, y: (geo.size.height - size) / 2),
                                        okFraction: okFraction)
                        guard let zone else { return }
                        begin(zone)
                    }
                    .onEnded { _ in end() }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cruceta de navegación")
        .accessibilityHint("Arriba, abajo, izquierda, derecha y OK")
        .accessibilityAdjustableAction { direction in
            viewModel.press(direction == .increment ? .dpadDown : .dpadUp)
        }
        .onDisappear { end() }
    }

    private func zone(at point: CGPoint, in size: CGSize, origin: CGPoint, okFraction: CGFloat) -> Zone? {
        let dx = point.x - origin.x - size.width / 2
        let dy = point.y - origin.y - size.height / 2
        let r = hypot(dx, dy)
        if r > size.width / 2 { return nil }
        if r < size.width * okFraction / 2 + size.width * 0.03 { return .ok }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func begin(_ zone: Zone) {
        active = zone
        viewModel.press(zone.key, strong: zone == .ok)
        guard zone != .ok else { return }
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            while !Task.isCancelled {
                viewModel.press(zone.key)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func end() {
        active = nil
        repeatTask?.cancel(); repeatTask = nil
    }
}

fileprivate extension DPadView.Zone {
    var angle: Double {
        switch self {
        case .up: return -90
        case .right: return 0
        case .down: return 90
        case .left: return 180
        case .ok: return 0
        }
    }
    var symbol: String {
        switch self {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .ok: return "circle"
        }
    }
    func offset(radius: CGFloat) -> CGSize {
        switch self {
        case .up: return CGSize(width: 0, height: -radius)
        case .down: return CGSize(width: 0, height: radius)
        case .left: return CGSize(width: -radius, height: 0)
        case .right: return CGSize(width: radius, height: 0)
        case .ok: return .zero
        }
    }
}

/// Sector de anillo de 90° centrado en `zone` grados.
private struct RingSector: Shape {
    let zone: Double
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 1
        let inner = outer * innerRatio * 1.9
        let start = Angle.degrees(zone - 43), end = Angle.degrees(zone + 43)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}
