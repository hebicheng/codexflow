import SwiftUI

struct SessionCard<Actions: View>: View {
  let session: SessionSummary
  let onOpen: (() -> Void)?
  let actions: Actions

  init(session: SessionSummary, onOpen: (() -> Void)? = nil, @ViewBuilder actions: () -> Actions) {
    self.session = session
    self.onOpen = onOpen
    self.actions = actions()
  }

  var body: some View {
    PanelCard(compact: true) {
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
              Text(session.displayName)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

              Text(session.cwd)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)

              Text("更新 \(session.updatedAtDisplay)")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.mutedInk)
            }

            Spacer()

            StatusPill(status: session.status, waiting: session.hasWaitingState, ended: session.isEnded)
          }

          if !previewText.isEmpty {
            Text(previewText)
              .font(.system(.footnote, design: .rounded))
              .foregroundStyle(Palette.mutedInk)
              .lineLimit(2)
          }

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              CapsuleTag(title: "来源", value: session.source)
              CapsuleTag(title: "分支", value: session.branch.isEmpty ? "未识别" : session.branch)
              if !session.lastTurnStatus.isEmpty {
                CapsuleTag(title: "最近一轮", value: lastTurnStatusLabel)
              }
            }
          }

          Text(actionHint)
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(hintTone)
        }
        .contentShape(Rectangle())
        .onTapGesture {
          onOpen?()
        }

        Rectangle()
          .fill(Palette.line)
          .frame(height: 1)

        actions
      }
    }
  }

  private var previewText: String {
    session.previewSummary
  }

  private var lastTurnStatusLabel: String {
    switch session.lastTurnStatus {
    case "inProgress":
      return "运行中"
    case "completed":
      return "已完成"
    case "failed":
      return "失败"
    default:
      return session.lastTurnStatus
    }
  }

  private var actionHint: String {
    if session.isEnded {
      return "这个会话已经在 CodexFlow 中结束。历史和 turn 会保留；如需继续，重新接管即可。"
    }
    if session.pendingApprovals > 0 {
      return "有 \(session.pendingApprovals) 个审批等待处理，先去审批页处理。"
    }
    if !session.loaded && session.lastTurnStatus == "inProgress" {
      return "这个会话还没被 CodexFlow 接管。先接管，之后才可以继续 steer 或中断。"
    }
    if session.lastTurnStatus == "inProgress" {
      return "点进去后可继续引导当前 turn，也可以中断。"
    }
    if session.loaded {
      return "点进去后可直接发送下一轮 prompt。"
    }
    return "这是历史会话。现在只能查看历史；接管后才可以开始下一轮。"
  }

  private var hintTone: Color {
    if session.isEnded {
      return Palette.mutedInk
    }
    if session.pendingApprovals > 0 {
      return Palette.warning
    }
    if session.lastTurnStatus == "inProgress" {
      return Palette.accent
    }
    if session.loaded {
      return Palette.success
    }
    return Palette.softBlue
  }
}
