import SwiftUI

enum Palette {
  static let canvas = Color(red: 0.97, green: 0.97, blue: 0.96)
  static let shell = Color(red: 0.94, green: 0.94, blue: 0.92)
  static let ink = Color(red: 0.11, green: 0.13, blue: 0.15)
  static let mutedInk = Color(red: 0.39, green: 0.42, blue: 0.44)
  static let accent = Color(red: 0.15, green: 0.58, blue: 0.35)
  static let accent2 = Color(red: 0.88, green: 0.44, blue: 0.22)
  static let softBlue = Color(red: 0.22, green: 0.45, blue: 0.71)
  static let success = Color(red: 0.12, green: 0.57, blue: 0.34)
  static let warning = Color(red: 0.86, green: 0.48, blue: 0.17)
  static let danger = Color(red: 0.73, green: 0.22, blue: 0.22)
  static let panel = Color.white.opacity(0.88)
  static let panelStrong = Color.white.opacity(0.96)
  static let line = Color.black.opacity(0.07)

  static let dashboardGradient = LinearGradient(
    colors: [canvas, Color(red: 0.95, green: 0.96, blue: 0.94), shell],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}

struct AtmosphereBackground: View {
  var body: some View {
    ZStack {
      Palette.dashboardGradient
        .ignoresSafeArea()

      VStack(spacing: 0) {
        LinearGradient(
          colors: [Palette.softBlue.opacity(0.05), Color.clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 180)

        Spacer()
      }
      .ignoresSafeArea()

      Circle()
        .fill(Palette.accent.opacity(0.05))
        .frame(width: 160, height: 160)
        .blur(radius: 16)
        .offset(x: 150, y: -260)

      Circle()
        .fill(Palette.accent2.opacity(0.05))
        .frame(width: 140, height: 140)
        .blur(radius: 18)
        .offset(x: -140, y: -170)
    }
  }
}

struct PanelCard<Content: View>: View {
  let compact: Bool
  let content: Content

  init(compact: Bool = false, @ViewBuilder content: () -> Content) {
    self.compact = compact
    self.content = content()
  }

  var body: some View {
    content
      .padding(compact ? 14 : 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.panelStrong)
      .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
          .stroke(Palette.line, lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
  }
}
