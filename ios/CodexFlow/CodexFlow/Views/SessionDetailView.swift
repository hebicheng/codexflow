import SwiftUI

struct SessionDetailView: View {
  @EnvironmentObject private var model: AppModel
  let sessionID: String

  @State private var prompt = ""
  @FocusState private var isPromptFocused: Bool

  private var detail: SessionDetail? {
    model.sessionDetails[sessionID]
  }

  private var summary: SessionSummary? {
    detail?.summary ?? model.dashboard.sessions.first(where: { $0.id == sessionID })
  }

  private var trimmedPrompt: String {
    prompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var orderedTurns: [TurnDetail] {
    guard let detail else { return [] }
    return Array(detail.turns.reversed())
  }

  private var activeTurn: TurnDetail? {
    orderedTurns.first(where: { $0.status == "inProgress" })
  }

  private var recentTurns: [TurnDetail] {
    orderedTurns.filter { $0.id != activeTurn?.id }
  }

  private var refreshIntervalSeconds: Double? {
    guard let summary else { return nil }
    if summary.isEnded {
      return nil
    }
    if !sessionApprovals.isEmpty || summary.hasWaitingState || summary.lastTurnStatus == "inProgress" {
      return 1.5
    }
    if summary.loaded {
      return 4
    }
    return nil
  }

  private var sessionApprovals: [PendingRequestView] {
    model.approvals(for: sessionID)
  }

  private var activeTurnApprovals: [PendingRequestView] {
    guard let activeTurn else { return [] }
    return sessionApprovals.filter { $0.turnId == activeTurn.id }
  }

  private var remainingSessionApprovals: [PendingRequestView] {
    guard let activeTurn else { return sessionApprovals }
    return sessionApprovals.filter { $0.turnId != activeTurn.id }
  }

  var body: some View {
    ZStack {
      AtmosphereBackground()

      ScrollView {
        VStack(spacing: 12) {
          if let summary {
            summaryCard(summary)
            if !remainingSessionApprovals.isEmpty {
              sessionApprovalsSection(
                title: "当前会话待审批",
                approvals: remainingSessionApprovals
              )
            }
            if summary.isEnded {
              takeoverCard(summary)
            } else if summary.loaded {
              composerCard(summary)
            } else {
              takeoverCard(summary)
            }
          }

          if let detail {
            if detail.turns.isEmpty {
              PanelCard(compact: true) {
                Text(emptyStateMessage)
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)
              }
            } else {
              if let activeTurn {
                VStack(alignment: .leading, spacing: 10) {
                  Text("当前运行中")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                  ActiveTurnCard(turn: activeTurn, approvals: activeTurnApprovals)
                }
              }

              if !recentTurns.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                  Text("最近的 turn")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                  ForEach(recentTurns) { turn in
                    TurnCard(turn: turn)
                  }
                }
              }
            }
          } else {
            PanelCard(compact: true) {
              ProgressView("正在加载会话详情…")
                .tint(Palette.accent)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
          isPromptFocused = false
        }
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.immediately)
      .refreshable {
        await refreshSessionPage()
      }
    }
    .navigationTitle(summary?.displayName ?? "会话详情")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .task {
      await refreshSessionPage()

      while !Task.isCancelled {
        guard let interval = refreshIntervalSeconds else { break }
        try? await Task.sleep(for: .seconds(interval))
        if refreshIntervalSeconds != nil {
          await refreshSessionPage()
        }
      }
    }
  }

  private func summaryCard(_ summary: SessionSummary) -> some View {
    PanelCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 5) {
            Text(summary.displayName)
              .font(.system(.headline, design: .rounded, weight: .semibold))
              .foregroundStyle(Palette.ink)

            Text(summary.cwd)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(Palette.mutedInk)
              .lineLimit(2)
          }

          Spacer()

          StatusPill(status: summary.status, waiting: summary.hasWaitingState, ended: summary.isEnded)
        }

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            CapsuleTag(title: "来源", value: summary.source)
            CapsuleTag(title: "分支", value: summary.branch.isEmpty ? "未识别" : summary.branch)
            CapsuleTag(title: "模型", value: summary.modelProvider)
          }
        }

        if !summary.previewSummary.isEmpty && summary.previewSummary != summary.displayName {
          VStack(alignment: .leading, spacing: 4) {
            Text("首条消息")
              .font(.system(.caption, design: .rounded, weight: .semibold))
              .foregroundStyle(Palette.mutedInk)

            HeadTailExcerptBlock(
              raw: summary.preview,
              head: 170,
              tail: 110,
              font: .system(.footnote, design: .rounded),
              color: Palette.mutedInk
            )
          }
        }

        if summary.pendingApprovals > 0 {
          Text("这个会话当前有 \(summary.pendingApprovals) 个审批等待处理，你可以直接在下面处理，也可以去“审批”页集中处理。")
            .font(.system(.footnote, design: .rounded, weight: .medium))
            .foregroundStyle(Palette.warning)
        }

        stateBanner(for: summary)
      }
    }
  }

  private func sessionApprovalsSection(title: String, approvals: [PendingRequestView]) -> some View {
    PanelCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(title)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.ink)

          Text("\(approvals.count)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.mutedInk)
        }

        ApprovalList(approvals: approvals, showSessionLabel: false)
      }
    }
  }

  private func takeoverCard(_ summary: SessionSummary) -> some View {
    PanelCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: "arrow.trianglehead.clockwise")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.softBlue)

          Text(summary.isEnded ? "会话已结束" : "先接管，再继续")
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.ink)
        }

        Text(takeoverSummary(for: summary))
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(Palette.mutedInk)

        Button {
          Task {
            await model.resumeSession(summary)
            await refreshSessionPage()
          }
        } label: {
          Text(summary.isEnded ? "重新接管会话" : "Resume 并接管会话")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Palette.softBlue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
    }
  }

  private func composerCard(_ summary: SessionSummary) -> some View {
    let isSteering = summary.lastTurnStatus == "inProgress"
    let accentTone = isSteering ? Palette.accent2 : Palette.accent

    return PanelCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(isSteering ? "继续当前 turn" : "开始下一轮")
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.ink)

          Spacer()

          Text(isSteering ? "steer" : "new turn")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(accentTone)
        }

        Text(isSteering
             ? "补充调整方向或新增约束。"
             : "输入新的 prompt，继续这个会话。")
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(Palette.mutedInk)

        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.clear)
            .overlay {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPromptFocused ? accentTone.opacity(0.35) : Palette.line, lineWidth: 1)
            }

          if trimmedPrompt.isEmpty {
            Text(isSteering
                 ? "例如：先别改接口，优先把测试补齐。"
                 : "例如：继续实现剩余部分，并补上验证。")
              .font(.system(.footnote, design: .rounded))
              .foregroundStyle(Palette.mutedInk)
              .padding(.horizontal, 14)
              .padding(.vertical, 16)
              .allowsHitTesting(false)
          }

          TextEditor(text: $prompt)
            .frame(minHeight: 120)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($isPromptFocused)
            .foregroundColor(Palette.ink)
            .tint(accentTone)
        }

        Button {
          isPromptFocused = false
          dismissKeyboard()
          Task {
            await model.submitPrompt(for: summary, prompt: trimmedPrompt)
            prompt = ""
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: isSteering ? "arrow.triangle.branch" : "sparkles")
              .font(.system(size: 13, weight: .bold))

            Text(isSteering ? "发送 steer" : "开始这一轮")
              .font(.system(.subheadline, design: .rounded, weight: .semibold))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(accentTone)
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
          .disabled(trimmedPrompt.isEmpty)
        .opacity(trimmedPrompt.isEmpty ? 0.45 : 1)

        if isSteering {
          HStack(spacing: 10) {
            Button {
              isPromptFocused = false
              dismissKeyboard()
              Task { await model.interrupt(session: summary) }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "pause.fill")
                  .font(.system(size: 12, weight: .bold))

                Text("先中断本轮")
                  .font(.system(.subheadline, design: .rounded, weight: .semibold))
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
              .background(Palette.warning.opacity(0.12))
              .foregroundStyle(Palette.warning)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .stroke(Palette.warning.opacity(0.18), lineWidth: 1)
              }
            }

            Button {
              isPromptFocused = false
              dismissKeyboard()
              Task {
                await model.endSession(summary)
                await refreshSessionPage()
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                  .font(.system(size: 12, weight: .bold))

                Text("中断并结束")
                  .font(.system(.subheadline, design: .rounded, weight: .semibold))
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
              .background(Palette.danger.opacity(0.12))
              .foregroundStyle(Palette.danger)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .stroke(Palette.danger.opacity(0.18), lineWidth: 1)
              }
            }
          }
        } else {
          Button {
            isPromptFocused = false
            dismissKeyboard()
            Task {
              await model.endSession(summary)
              await refreshSessionPage()
            }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "stop.circle")
                .font(.system(size: 13, weight: .bold))

              Text("结束这个会话")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Palette.danger.opacity(0.10))
            .foregroundStyle(Palette.danger)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.danger.opacity(0.16), lineWidth: 1)
            }
          }
        }
      }
    }
  }

  private func actionSummary(for summary: SessionSummary) -> String {
    if summary.isEnded {
      return "这个会话已经在 CodexFlow 中结束。历史和 turn 会保留，但不再由 CodexFlow 托管；如需继续，请重新接管。"
    }
    if !summary.loaded && summary.lastTurnStatus == "inProgress" {
      return "这个会话当前还没被 CodexFlow 接管。现在只能查看历史；点下面“Resume 并接管会话”后，才可以继续 steer、处理中断和刷新运行状态。"
    }
    if summary.lastTurnStatus == "inProgress" {
      return "当前有一轮正在运行。这个页面会自动刷新最近 turn 的内容；你也可以继续 steer 或中断。"
    }
    if summary.loaded {
      return "当前没有运行中的 turn。你可以直接输入新的 prompt，开始下一轮。"
    }
    return "这个会话当前未接管。你可以查看历史；如果需要继续执行，先接管到 CodexFlow 后台。"
  }

  @ViewBuilder
  private func stateBanner(for summary: SessionSummary) -> some View {
    let tone: Color = summary.isEnded ? Palette.mutedInk : (summary.pendingApprovals > 0 ? Palette.warning : (summary.loaded ? Palette.success : Palette.softBlue))

    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(tone)
        .frame(width: 4)

      Text(actionSummary(for: summary))
        .font(.system(.footnote, design: .rounded, weight: .medium))
        .foregroundStyle(tone)
    }
    .padding(10)
    .background(tone.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func takeoverSummary(for summary: SessionSummary) -> String {
    if summary.isEnded {
      return "这个会话已经在 CodexFlow 中结束了。历史记录仍然可看；如果你想继续发 prompt 或重新托管审批/状态刷新，先重新接管。"
    }
    if summary.lastTurnStatus == "inProgress" {
      return "这个会话可能仍在别处运行，但当前不在 CodexFlow 里托管。先接管后，CodexFlow 才能继续刷新状态、处理审批，并允许你继续 steer 或中断。"
    }
    return "这个会话现在只是历史记录，还没有被 CodexFlow 接管。接管后，这个页面才会出现“开始下一轮”或“继续引导当前 turn”的操作。"
  }

  private var emptyStateMessage: String {
    if let summary, summary.isEnded {
      return "这个会话已经结束。当前没有更多 turn 可展示；如果要继续执行，先重新接管。"
    }
    if summary?.loaded == true {
      return "这个会话还没有 turn。你可以直接在上面输入，开始第一轮。"
    }
    return "这个会话当前没有可展示的 turn 历史。先接管后，才能继续在 CodexFlow 里执行。"
  }

  private func refreshSessionPage() async {
    await model.refreshDashboard()
    await model.loadSession(id: sessionID)
  }
}

private struct HeadTailExcerptBlock: View {
  let raw: String
  let head: Int
  let tail: Int
  let font: Font
  let color: Color

  private var excerpt: (head: String, tail: String?) {
    headTailExcerpt(from: raw, head: head, tail: tail)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(excerpt.head)
        .font(font)
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)

      if let tail = excerpt.tail {
        Text("…")
          .font(font)
          .foregroundStyle(color)

        Text(tail)
          .font(font)
          .foregroundStyle(color)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private func headTailExcerpt(from raw: String, head: Int, tail: Int) -> (head: String, tail: String?) {
  let normalized = normalizedDisplayText(from: raw)

  guard normalized.count > head + tail + 12 else {
    return (normalized, nil)
  }

  let safeHead = min(head, normalized.count)
  let safeTail = min(tail, max(0, normalized.count - safeHead))
  guard safeHead > 0, safeTail > 0, safeHead + safeTail < normalized.count else {
    return (normalized, nil)
  }

  let headEnd = normalized.index(normalized.startIndex, offsetBy: safeHead)
  let tailStart = normalized.index(normalized.endIndex, offsetBy: -safeTail)
  return (String(normalized[..<headEnd]), String(normalized[tailStart...]))
}

private func normalizedDisplayText(from raw: String) -> String {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return "" }

  if let attributed = try? AttributedString(markdown: trimmed) {
    let markdownStripped = String(attributed.characters)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !markdownStripped.isEmpty {
      return markdownStripped
    }
  }

  return trimmed
    .components(separatedBy: .whitespacesAndNewlines)
    .filter { !$0.isEmpty }
    .joined(separator: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct TurnCard: View {
  let turn: TurnDetail
  var isLive: Bool = false

  var body: some View {
    PanelCard(compact: true) {
      TurnCardBody(turn: turn, isLive: isLive)
    }
    .overlay {
      if isLive {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Palette.warning.opacity(0.35), lineWidth: 1.5)
      }
    }
  }
}

private struct ActiveTurnCard: View {
  let turn: TurnDetail
  let approvals: [PendingRequestView]

  var body: some View {
    PanelCard(compact: true) {
      VStack(alignment: .leading, spacing: 12) {
        if !approvals.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Label("当前 turn 待审批", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.warning)

              Text("\(approvals.count)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.warning)

              Spacer()
            }

            ForEach(approvals) { approval in
              ApprovalCardBody(approval: approval, showSessionLabel: false, embedded: true)
            }
          }

          Rectangle()
            .fill(Palette.line)
            .frame(height: 1)
        }

        TurnCardBody(turn: turn, isLive: true)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Palette.warning.opacity(0.35), lineWidth: 1.5)
    }
  }
}

private struct TurnCardBody: View {
  let turn: TurnDetail
  var isLive: Bool = false
  @State private var showDetail = false

  private var firstUserItem: TurnItem? {
    turn.items.first(where: { $0.type == "userMessage" && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }

  private var lastAgentItem: TurnItem? {
    turn.items.last(where: { $0.type == "agentMessage" && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }

  private var visibleTimelineItemCount: Int {
    turn.items.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(turnStatusLabel)
              .font(.system(.subheadline, design: .rounded, weight: .semibold))
              .foregroundStyle(statusTone)

            if isLive {
              Label("实时更新", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.warning)
            }
          }

          Text(turn.id)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Palette.mutedInk)
            .lineLimit(1)
        }

        Spacer()

        if turn.durationMs > 0 {
          Text("\(turn.durationMs / 1000)s")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.mutedInk)
        }
      }

      if !turn.error.isEmpty {
        Text(turn.error)
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(Palette.danger)
      }

      if firstUserItem != nil || lastAgentItem != nil {
        VStack(alignment: .leading, spacing: 8) {
          Text("本轮摘要")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.ink)

          if let firstUserItem {
            ExcerptSummaryCard(
              title: "用户提示",
              symbol: "person.crop.circle",
              tone: Palette.softBlue,
              raw: firstUserItem.body,
              head: 170,
              tail: 110
            )
          }

          if let lastAgentItem {
            ExcerptSummaryCard(
              title: "Agent 输出",
              symbol: "sparkles.rectangle.stack",
              tone: Palette.accent,
              raw: lastAgentItem.body,
              head: 210,
              tail: 140
            )
          }
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          if !turn.plan.isEmpty {
            CapsuleTag(title: "计划", value: "\(turn.plan.count) 步")
          }
          if !turn.diff.isEmpty {
            CapsuleTag(title: "Diff", value: "可查看")
          }
          if visibleTimelineItemCount > 0 {
            CapsuleTag(title: "时间线", value: "\(visibleTimelineItemCount) 项")
          }
        }
      }

      Button {
        showDetail = true
      } label: {
        HStack {
          Text("查看详情")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Palette.shell)
        .foregroundStyle(Palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
    .sheet(isPresented: $showDetail) {
      TurnDetailSheet(turn: turn)
    }
  }

  private var turnStatusLabel: String {
    switch turn.status {
    case "completed":
      return "已完成"
    case "failed":
      return "失败"
    case "inProgress":
      return "运行中"
    default:
      return turn.status
    }
  }

  private var statusTone: Color {
    switch turn.status {
    case "completed":
      return Palette.success
    case "failed":
      return Palette.danger
    case "inProgress":
      return Palette.warning
    default:
      return Palette.mutedInk
    }
  }

}

private struct ExcerptSummaryCard: View {
  let title: String
  let symbol: String
  let tone: Color
  let raw: String
  let head: Int
  let tail: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(tone)

        Text(title)
          .font(.system(.caption2, design: .rounded, weight: .semibold))
          .foregroundStyle(tone)
      }

      HeadTailExcerptBlock(
        raw: raw,
        head: head,
        tail: tail,
        font: .system(.caption, design: .rounded),
        color: Palette.ink
      )
    }
    .padding(12)
    .background(tone.opacity(0.10))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(tone.opacity(0.18), lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct TurnDetailSheet: View {
  let turn: TurnDetail
  @Environment(\.dismiss) private var dismiss
  @State private var showPlan = true
  @State private var showDiff = false
  @State private var showTimeline = false

  var body: some View {
    NavigationStack {
      ZStack {
        AtmosphereBackground()

        ScrollView {
          VStack(spacing: 12) {
            PanelCard {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Text(turnStatusLabel)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(statusTone)

                  Spacer()

                  if turn.durationMs > 0 {
                    Text("\(turn.durationMs / 1000)s")
                      .font(.system(.caption, design: .rounded, weight: .semibold))
                      .foregroundStyle(Palette.mutedInk)
                  }
                }

                Text(turn.id)
                  .font(.system(.caption, design: .monospaced))
                  .foregroundStyle(Palette.mutedInk)
              }
            }

            if !turn.planExplanation.isEmpty || !turn.plan.isEmpty {
              DisclosureSection(title: "计划", isExpanded: $showPlan) {
                if !turn.planExplanation.isEmpty {
                  Text(turn.planExplanation)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.mutedInk)
                }

                ForEach(turn.plan) { step in
                  HStack(alignment: .top, spacing: 8) {
                    Circle()
                      .fill(color(for: step.status))
                      .frame(width: 6, height: 6)
                      .padding(.top, 5)

                    Text("\(step.step) · \(stepStatusLabel(step.status))")
                      .font(.system(.caption, design: .rounded))
                      .foregroundStyle(Palette.mutedInk)
                  }
                }
              }
            }

            if !turn.diff.isEmpty {
              DisclosureSection(title: "Diff", isExpanded: $showDiff) {
                DiffBlock(diff: turn.diff)
              }
            }

            if !turn.items.isEmpty {
              DisclosureSection(title: "时间线", isExpanded: $showTimeline) {
                ForEach(turn.items) { item in
                  TimelineEntryView(item: item, bodyPreview: bodyPreview(for: item))
                }
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
      }
      .navigationTitle("Turn 详情")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("关闭") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }

  private var turnStatusLabel: String {
    switch turn.status {
    case "completed":
      return "已完成"
    case "failed":
      return "失败"
    case "inProgress":
      return "运行中"
    default:
      return turn.status
    }
  }

  private var statusTone: Color {
    switch turn.status {
    case "completed":
      return Palette.success
    case "failed":
      return Palette.danger
    case "inProgress":
      return Palette.warning
    default:
      return Palette.mutedInk
    }
  }

  private func color(for status: String) -> Color {
    switch status {
    case "completed":
      return Palette.success
    case "in_progress":
      return Palette.warning
    default:
      return Palette.line
    }
  }

  private func stepStatusLabel(_ status: String) -> String {
    switch status {
    case "completed":
      return "已完成"
    case "in_progress":
      return "进行中"
    default:
      return "待处理"
    }
  }

  private func bodyPreview(for item: TurnItem) -> String {
    let normalized = item.body
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    return normalized.headTailTruncated(maxLength: 220, head: 140, tail: 72)
  }
}

private struct DisclosureSection<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  let content: Content

  init(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
    self.title = title
    self._isExpanded = isExpanded
    self.content = content()
  }

  var body: some View {
    PanelCard(compact: true) {
      DisclosureGroup(isExpanded: $isExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          content
        }
        .padding(.top, 8)
      } label: {
        Text(title)
          .font(.system(.caption, design: .rounded, weight: .semibold))
          .foregroundStyle(Palette.ink)
      }
      .tint(Palette.ink)
    }
  }
}

private struct TimelineTypeTag: View {
  let item: TurnItem

  var body: some View {
    Text(label)
      .font(.system(.caption2, design: .rounded, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(color.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var label: String {
    switch item.type {
    case "userMessage":
      return "用户"
    case "agentMessage":
      return "Agent"
    case "fileChange":
      return "文件变更"
    default:
      return item.title
    }
  }

  private var color: Color {
    switch item.type {
    case "userMessage":
      return Palette.softBlue
    case "agentMessage":
      return Palette.accent
    case "fileChange":
      return Palette.accent2
    case "commandExecution":
      return Palette.warning
    default:
      return Palette.mutedInk
    }
  }
}

private struct TimelineEntryView: View {
  let item: TurnItem
  let bodyPreview: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        TimelineTypeTag(item: item)

        Spacer()

        if !item.status.isEmpty {
          Text(item.status)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.mutedInk)
        }
      }

      switch item.type {
      case "userMessage", "agentMessage":
        if item.type == "agentMessage" {
          MarkdownBodyBlock(raw: item.body)
        } else {
          HeadTailExcerptBlock(
            raw: item.body,
            head: 170,
            tail: 110,
            font: .system(.caption, design: .rounded),
            color: Palette.mutedInk
          )
        }
      case "fileChange":
        FileChangeBlock(item: item)
      case "commandExecution":
        CommandExecutionBlock(item: item)
      default:
        if !bodyPreview.isEmpty {
          Text(bodyPreview)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Palette.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !item.auxiliary.isEmpty {
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10)
        }
      }
    }
    .padding(12)
    .background(Color.white.opacity(0.65))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Palette.line, lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct MarkdownBodyBlock: View {
  let raw: String

  private var blocks: [MarkdownRenderBlock] {
    parseMarkdownBlocks(raw)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        render(block)
      }
    }
  }

  @ViewBuilder
  private func render(_ block: MarkdownRenderBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      MarkdownInlineText(text: text, font: headingFont(level))
        .foregroundStyle(Palette.ink)
    case .paragraph(let text):
      MarkdownInlineText(text: text, font: .system(.caption, design: .rounded))
        .foregroundStyle(Palette.ink)
    case .bullet(let text):
      HStack(alignment: .top, spacing: 8) {
        Circle()
          .fill(Palette.accent)
          .frame(width: 5, height: 5)
          .padding(.top, 6)

        MarkdownInlineText(text: text, font: .system(.caption, design: .rounded))
          .foregroundStyle(Palette.ink)
      }
    case .quote(let text):
      HStack(alignment: .top, spacing: 8) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Palette.softBlue)
          .frame(width: 3)

        MarkdownInlineText(text: text, font: .system(.caption, design: .rounded))
          .foregroundStyle(Palette.mutedInk)
      }
      .padding(.vertical, 2)
    case .code(let text):
      MarkdownCodeBlock(text: text)
    case .divider:
      Rectangle()
        .fill(Palette.line)
        .frame(height: 1)
    }
  }

  private func headingFont(_ level: Int) -> Font {
    switch level {
    case 1:
      return .system(size: 17, weight: .bold, design: .rounded)
    case 2:
      return .system(size: 16, weight: .semibold, design: .rounded)
    default:
      return .system(size: 14, weight: .semibold, design: .rounded)
    }
  }
}

private struct MarkdownInlineText: View {
  let text: String
  let font: Font

  private var attributed: AttributedString? {
    try? AttributedString(
      markdown: text,
      options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )
  }

  var body: some View {
    Group {
      if let attributed {
        Text(attributed)
      } else {
        Text(text)
      }
    }
    .font(font)
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct MarkdownCodeBlock: View {
  let text: String

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Text(text)
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(Color(red: 0.90, green: 0.92, blue: 0.93))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(red: 0.12, green: 0.14, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

private enum MarkdownRenderBlock {
  case heading(level: Int, text: String)
  case paragraph(String)
  case bullet(String)
  case quote(String)
  case code(String)
  case divider
}

private func parseMarkdownBlocks(_ raw: String) -> [MarkdownRenderBlock] {
  let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
  var blocks: [MarkdownRenderBlock] = []
  var paragraphBuffer: [String] = []
  var codeBuffer: [String] = []
  var isInCodeBlock = false

  func flushParagraph() {
    guard !paragraphBuffer.isEmpty else { return }
    let text = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
      blocks.append(.paragraph(text))
    }
    paragraphBuffer.removeAll()
  }

  for line in lines {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("```") {
      if isInCodeBlock {
        blocks.append(.code(codeBuffer.joined(separator: "\n")))
        codeBuffer.removeAll()
        isInCodeBlock = false
      } else {
        flushParagraph()
        isInCodeBlock = true
      }
      continue
    }

    if isInCodeBlock {
      codeBuffer.append(line)
      continue
    }

    if trimmed.isEmpty {
      flushParagraph()
      continue
    }

    if trimmed == "---" || trimmed == "***" {
      flushParagraph()
      blocks.append(.divider)
      continue
    }

    if let heading = parseMarkdownHeading(trimmed) {
      flushParagraph()
      blocks.append(.heading(level: heading.level, text: heading.text))
      continue
    }

    if let quote = parseMarkdownQuote(trimmed) {
      flushParagraph()
      blocks.append(.quote(quote))
      continue
    }

    if let bullet = parseMarkdownBullet(trimmed) {
      flushParagraph()
      blocks.append(.bullet(bullet))
      continue
    }

    paragraphBuffer.append(trimmed)
  }

  if isInCodeBlock, !codeBuffer.isEmpty {
    blocks.append(.code(codeBuffer.joined(separator: "\n")))
  }

  flushParagraph()
  return blocks.isEmpty ? [.paragraph(normalizedDisplayText(from: raw))] : blocks
}

private func parseMarkdownHeading(_ line: String) -> (level: Int, text: String)? {
  let hashes = line.prefix { $0 == "#" }
  let level = min(hashes.count, 6)
  guard level > 0 else { return nil }

  let remainder = line.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
  guard !remainder.isEmpty else { return nil }
  return (level, remainder)
}

private func parseMarkdownQuote(_ line: String) -> String? {
  guard line.hasPrefix(">") else { return nil }
  let text = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
  return text.isEmpty ? nil : text
}

private func parseMarkdownBullet(_ line: String) -> String? {
  if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
    let text = line.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  var digitCount = 0
  for character in line {
    if character.isNumber {
      digitCount += 1
      continue
    }
    break
  }

  guard digitCount > 0 else { return nil }
  let remainder = line.dropFirst(digitCount)
  guard remainder.hasPrefix(". ") else { return nil }
  let text = remainder.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
  return text.isEmpty ? nil : text
}

private struct FileChangeBlock: View {
  let item: TurnItem

  private var files: [String] {
    item.body
      .split(separator: "\n")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private var visibleFiles: [String] {
    Array(files.prefix(8))
  }

  private var hiddenCount: Int {
    max(0, files.count - visibleFiles.count)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if visibleFiles.isEmpty {
        if !item.body.isEmpty {
          Text(item.body)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Palette.mutedInk)
        }
      } else {
        ForEach(visibleFiles, id: \.self) { file in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Palette.accent2)
              .padding(.top, 2)

            Text(file)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(Palette.ink)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        if hiddenCount > 0 {
          Text("… 还有 \(hiddenCount) 个文件")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Palette.mutedInk)
        }
      }
    }
  }
}

private struct CommandExecutionBlock: View {
  let item: TurnItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let cwd = item.metadata["cwd"], !cwd.isEmpty {
        Text(cwd)
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(Palette.mutedInk)
      }

      if !item.body.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          Text(item.body)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Palette.ink)
            .padding(10)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
      }

      if !item.auxiliary.isEmpty {
        TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10)
      }
    }
  }
}

private struct TerminalOutputBlock: View {
  let text: String
  let maxVisibleLines: Int?

  init(text: String, maxVisibleLines: Int? = nil) {
    self.text = text
    self.maxVisibleLines = maxVisibleLines
  }

  private var lines: [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  private var visibleLines: [String] {
    guard let maxVisibleLines else { return lines }
    return Array(lines.prefix(maxVisibleLines))
  }

  private var hiddenLineCount: Int {
    lines.count - visibleLines.count
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
          Text(line.isEmpty ? " " : line)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color(red: 0.86, green: 0.89, blue: 0.90))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }

        if hiddenLineCount > 0 {
          Text("… 还有 \(hiddenLineCount) 行未显示")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color(red: 0.62, green: 0.68, blue: 0.70))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
      }
      .padding(.vertical, 8)
      .background(Color(red: 0.10, green: 0.13, blue: 0.15))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

private struct DiffBlock: View {
  let diff: String

  private var lines: [String] {
    diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line.isEmpty ? " " : line)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(foregroundColor(for: line))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(backgroundColor(for: line))
        }
      }
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.8))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Palette.line, lineWidth: 1)
      }
    }
  }

  private func backgroundColor(for line: String) -> Color {
    if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("@@") {
      return Palette.softBlue.opacity(0.10)
    }
    if line.hasPrefix("+") {
      return Palette.success.opacity(0.10)
    }
    if line.hasPrefix("-") {
      return Palette.danger.opacity(0.10)
    }
    return Color.clear
  }

  private func foregroundColor(for line: String) -> Color {
    if line.hasPrefix("+") && !line.hasPrefix("+++") {
      return Palette.success
    }
    if line.hasPrefix("-") && !line.hasPrefix("---") {
      return Palette.danger
    }
    if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("@@") {
      return Palette.softBlue
    }
    return Palette.ink
  }
}
