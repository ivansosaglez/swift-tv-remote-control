import SwiftUI

/// Representaciones visuales reconocibles de cada servicio, dibujadas con vectores propios
/// (no se incluyen logotipos oficiales con derechos de marca).
struct StreamingAppIcon: View {
    let app: StreamingApp

    var body: some View {
        ZStack {
            switch app {
            case .netflix:
                Text("N")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.9, green: 0.04, blue: 0.08), Color(red: 0.6, green: 0, blue: 0.05)], startPoint: .top, endPoint: .bottom))
            case .prime:
                VStack(spacing: -2) {
                    Text("prime").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.0, green: 0.66, blue: 0.96))
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9)).rotationEffect(.degrees(-90))
                        .offset(x: 6)
                }
            case .max:
                Text("max").font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.3, blue: 1), Color(red: 0.25, green: 0.4, blue: 1)], startPoint: .leading, endPoint: .trailing))
            case .youtube:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 1, green: 0.0, blue: 0.0))
                    .frame(width: 34, height: 24)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white))
            case .twitch:
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(red: 0.57, green: 0.27, blue: 1.0))
                    .overlay(
                        HStack(spacing: 4) {
                            Capsule().fill(.white).frame(width: 2.5, height: 9)
                            Capsule().fill(.white).frame(width: 2.5, height: 9)
                        }.offset(y: -2)
                    )
            }
        }
    }
}
