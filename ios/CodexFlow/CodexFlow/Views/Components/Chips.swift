import SwiftUI

struct CapsuleTag: View {
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .foregroundStyle(Palette.mutedInk)

      Text(value)
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(Palette.shell)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

struct StatusPill: View {
  let status: String
  let waiting: Bool
  let ended: Bool

  init(status: String, waiting: Bool, ended: Bool = false) {
    self.status = status
    self.waiting = waiting
    self.ended = ended
  }

  var body: some View {
    Text(label)
      .font(.system(.caption2, design: .rounded, weight: .bold))
      .foregroundStyle(tone)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(tone.opacity(0.14))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var label: String {
    if ended {
      return "已结束"
    }
    if waiting {
      return "待处理"
    }

    switch status {
    case "active", "inProgress":
      return "运行中"
    case "completed":
      return "已完成"
    case "notLoaded":
      return "未接管"
    case "failed", "systemError":
      return "失败"
    case "idle":
      return "空闲"
    default:
      return status
    }
  }

  private var tone: Color {
    if ended {
      return Palette.mutedInk
    }
    if waiting {
      return Palette.warning
    }

    switch status {
    case "active", "inProgress":
      return Palette.accent
    case "completed", "idle":
      return Palette.success
    case "notLoaded":
      return Palette.softBlue
    case "failed", "systemError":
      return Palette.danger
    default:
      return Palette.mutedInk
    }
  }
}

struct AgentStatusBadge: View {
  let connected: Bool

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(tone)
        .frame(width: 7, height: 7)

      Text(connected ? "在线" : "离线")
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .foregroundStyle(tone)
        .lineLimit(1)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(tone.opacity(0.10))
    .clipShape(Capsule())
    .fixedSize(horizontal: true, vertical: false)
  }

  private var tone: Color {
    connected ? Palette.accent : Palette.danger
  }
}
