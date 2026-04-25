import SwiftUI

struct MetricCard: View {
  let title: String
  let value: String
  let tone: Color

  var body: some View {
    PanelCard(compact: true) {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.system(.caption, design: .rounded, weight: .semibold))
          .foregroundStyle(Palette.mutedInk)

        Text(value)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundStyle(Palette.ink)

        Capsule()
          .fill(tone.opacity(0.16))
          .frame(height: 6)
          .overlay(alignment: .leading) {
            Capsule()
              .fill(tone)
              .frame(width: 28, height: 6)
          }
      }
    }
  }
}
