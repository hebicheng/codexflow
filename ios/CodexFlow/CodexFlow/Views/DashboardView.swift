import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var model: AppModel
  @State private var showComposer = false

  private let metricsColumns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10)
  ]

  private var isConnected: Bool {
    model.isAgentOnline
  }

  private var managedSessions: [SessionSummary] {
    model.dashboard.sessions.filter { $0.loaded && !$0.isEnded }
  }

  private var endedSessions: [SessionSummary] {
    model.dashboard.sessions.filter { $0.isEnded }
  }

  private var historySessions: [SessionSummary] {
    model.dashboard.sessions.filter { !$0.loaded && !$0.isEnded }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AtmosphereBackground()

        ScrollView {
          VStack(spacing: 12) {
            dashboardStatusRow
            metrics
            if !isConnected && !model.agentConnectionError.isEmpty {
              connectionIssueBanner
            }
            if model.dashboard.stats.pendingApprovals > 0 {
              approvalsBanner
            }
            sessionSection
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("会话")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showComposer) {
        NewSessionSheet()
      }
      .refreshable {
        await model.refreshDashboard()
      }
    }
  }

  private var connectionIssueBanner: some View {
    Text(model.agentConnectionError)
      .font(.system(.caption, design: .rounded))
      .foregroundStyle(Palette.danger)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.danger.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var dashboardStatusRow: some View {
    HStack {
      Spacer()
      AgentStatusBadge(connected: isConnected)
    }
  }

  private var createSessionButton: some View {
    Button {
      showComposer = true
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "plus")
          .font(.system(size: 12, weight: .bold))

        Text("新建")
          .font(.system(.caption, design: .rounded, weight: .bold))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Palette.softBlue)
      .clipShape(Capsule())
    }
  }

  private var metrics: some View {
    LazyVGrid(columns: metricsColumns, spacing: 10) {
      MetricCard(title: "总会话", value: "\(model.dashboard.stats.totalSessions)", tone: Palette.softBlue)
      MetricCard(title: "已加载", value: "\(model.dashboard.stats.loadedSessions)", tone: Palette.accent)
      MetricCard(title: "运行中", value: "\(model.dashboard.stats.activeSessions)", tone: Palette.accent2)
      MetricCard(title: "待审批", value: "\(model.dashboard.stats.pendingApprovals)", tone: Palette.warning)
    }
  }

  private var approvalsBanner: some View {
    PanelCard(compact: true) {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(Palette.warning)

        Text("当前有 \(model.dashboard.stats.pendingApprovals) 个审批等待处理。")
          .font(.system(.footnote, design: .rounded, weight: .medium))
          .foregroundStyle(Palette.warning)
      }
    }
  }

  private var sessionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("列表")
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.ink)

          Text("\(model.dashboard.sessions.count)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.mutedInk)
        }

        Spacer()

        createSessionButton
      }

      if model.dashboard.sessions.isEmpty {
        PanelCard(compact: true) {
          Text("暂时没有会话。先确认 Agent 已连接，或者点上方“新建”。")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Palette.mutedInk)
        }
      } else {
        if !managedSessions.isEmpty {
          sessionGroup(
            title: "已接管",
            helper: "这些会话已经由 CodexFlow 后台托管，可以直接继续 steer、开始下一轮，或处理中断。", sessions: managedSessions
          )
        }

        if !endedSessions.isEmpty {
          sessionGroup(
            title: "已结束",
            helper: "这些会话的历史和 turns 仍然保留，但已经从 CodexFlow 托管态退出。需要继续时，再重新接管。", sessions: endedSessions
          )
        }

        if !historySessions.isEmpty {
          sessionGroup(
            title: "历史会话",
            helper: "这些只是已发现的真实会话记录。先接管，才可以继续执行、处理中断和后续审批。", sessions: historySessions
          )
        }
      }
    }
  }

  private func sessionGroup(title: String, helper: String, sessions: [SessionSummary]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(.subheadline, design: .rounded, weight: .semibold))
          .foregroundStyle(Palette.ink)

        Text("\(sessions.count)")
          .font(.system(.caption, design: .rounded, weight: .semibold))
          .foregroundStyle(Palette.mutedInk)
      }

      Text(helper)
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(Palette.mutedInk)

      ForEach(sessions) { session in
        SessionRow(session: session)
      }
    }
  }
}

private struct SessionRow: View {
  @EnvironmentObject private var model: AppModel
  let session: SessionSummary
  @State private var showDetail = false
  @State private var showApprovals = false

  private var sessionApprovals: [PendingRequestView] {
    model.approvals(for: session.id)
  }

  var body: some View {
    SessionCard(session: session, onOpen: {
      showDetail = true
    }) {
      VStack(spacing: 10) {
        HStack(spacing: 10) {
          NavigationLink {
            SessionDetailView(sessionID: session.id)
          } label: {
            rowButtonLabel(
              (session.loaded && !session.isEnded) ? "查看并继续" : (session.isEnded ? "查看详情" : "查看历史"),
              background: Color.white,
              foreground: Palette.softBlue,
              border: Palette.softBlue.opacity(0.24)
            )
          }
          .buttonStyle(.plain)

          if session.isEnded {
            Button {
              Task { await model.resumeSession(session) }
            } label: {
              rowButtonLabel(
                "重新接管",
                background: Palette.softBlue,
                foreground: .white,
                border: .clear
              )
            }
            .buttonStyle(.plain)
          } else if !session.loaded {
            Button {
              Task { await model.resumeSession(session) }
            } label: {
              rowButtonLabel(
                "接管到 CodexFlow",
                background: Palette.softBlue,
                foreground: .white,
                border: .clear
              )
            }
            .buttonStyle(.plain)
          } else {
            Button {
              Task { await model.endSession(session) }
            } label: {
              rowButtonLabel(
                session.lastTurnStatus == "inProgress" ? "中断并结束" : "结束会话",
                background: Palette.danger.opacity(0.12),
                foreground: Palette.danger,
                border: Palette.danger.opacity(0.20)
              )
            }
            .buttonStyle(.plain)
          }
        }

        if session.pendingApprovals > 0 {
          Button {
            showApprovals = true
          } label: {
            rowButtonLabel(
              "快速处理审批 (\(session.pendingApprovals))",
              background: Palette.warning.opacity(0.14),
              foreground: Palette.warning,
              border: Palette.warning.opacity(0.22)
            )
          }
          .buttonStyle(.plain)
        }

        if !session.loaded || session.isEnded {
          Button {
            Task { await model.archiveSession(session) }
          } label: {
            rowButtonLabel(
              session.isEnded ? "归档已结束会话" : "从列表移除",
              background: Color.white,
              foreground: Palette.danger,
              border: Palette.danger.opacity(0.20)
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .navigationDestination(isPresented: $showDetail) {
      SessionDetailView(sessionID: session.id)
    }
    .sheet(isPresented: $showApprovals) {
      SessionApprovalSheet(title: session.displayName, approvals: sessionApprovals)
        .environmentObject(model)
    }
  }

  private func rowButtonLabel(_ title: String, background: Color, foreground: Color, border: Color) -> some View {
    Text(title)
      .font(.system(.caption, design: .rounded, weight: .semibold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 11)
      .background(background)
      .foregroundStyle(foreground)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(border, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct NewSessionSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var cwd = ""
  @State private var prompt = ""
  @State private var isCreating = false
  @State private var submitError = ""
  @FocusState private var focusedField: NewSessionField?

  private var trimmedCWD: String {
    cwd.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedPrompt: String {
    prompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canCreate: Bool {
    !trimmedCWD.isEmpty && !trimmedPrompt.isEmpty
  }

  private var promptPlaceholder: String {
    "例如：继续实现剩余部分，并补上验证。"
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AtmosphereBackground()

        ScrollView {
          VStack(spacing: 12) {
            PanelCard {
              VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Text("受控会话")
                      .font(.system(.caption2, design: .rounded, weight: .bold))
                      .foregroundStyle(Palette.softBlue)
                      .padding(.horizontal, 9)
                      .padding(.vertical, 6)
                      .background(Palette.softBlue.opacity(0.12))
                      .clipShape(Capsule())

                    Spacer()

                    Text("2 项必填")
                      .font(.system(.caption2, design: .rounded, weight: .bold))
                      .foregroundStyle(Palette.mutedInk)
                  }

                  Text("新建会话")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)

                  Text("填写目录和首条提示，CodexFlow 会立即建立一个可继续的会话。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.mutedInk)
                }

                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("工作目录")
                      .font(.system(.subheadline, design: .rounded, weight: .semibold))
                      .foregroundStyle(Palette.ink)

                    Spacer()

                    Text("绝对路径或 ~/repo")
                      .font(.system(.caption2, design: .rounded, weight: .medium))
                      .foregroundStyle(Palette.mutedInk)
                  }

                  TextField("/Users/hebicheng/workspace/aicoding-helper", text: $cwd)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .cwd)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Palette.ink)
                    .tint(Palette.softBlue)
                    .padding(13)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                      RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focusedField == .cwd ? Palette.softBlue.opacity(0.35) : Palette.line, lineWidth: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("首条提示")
                      .font(.system(.subheadline, design: .rounded, weight: .semibold))
                      .foregroundStyle(Palette.ink)

                    Spacer()

                    Text(trimmedPrompt.isEmpty ? "未填写" : "\(trimmedPrompt.count) 字")
                      .font(.system(.caption2, design: .rounded, weight: .medium))
                      .foregroundStyle(trimmedPrompt.isEmpty ? Palette.mutedInk : Palette.softBlue)
                  }

                  ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                      .fill(Color.clear)
                      .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                          .stroke(focusedField == .prompt ? Palette.softBlue.opacity(0.35) : Palette.line, lineWidth: 1)
                      }

                    if trimmedPrompt.isEmpty {
                      Text(promptPlaceholder)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Palette.mutedInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                    }

                    TextEditor(text: $prompt)
                      .frame(minHeight: 126)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 8)
                      .scrollContentBackground(.hidden)
                      .background(Color.clear)
                      .focused($focusedField, equals: .prompt)
                      .foregroundColor(Palette.ink)
                      .tint(Palette.softBlue)
                  }
                }

                HStack(spacing: 8) {
                  Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.softBlue)

                  Text("支持 `~/...` 路径，创建后会立即出现在会话列表。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Palette.mutedInk)
                }

                if !submitError.isEmpty {
                  Text(submitError)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                  guard !isCreating else { return }
                  focusedField = nil
                  Task {
                    isCreating = true
                    submitError = ""
                    if await model.startSession(cwd: trimmedCWD, prompt: trimmedPrompt) {
                      isCreating = false
                      dismiss()
                    } else {
                      isCreating = false
                      submitError = model.connectionError.isEmpty ? "创建会话失败，请检查 Agent 状态和输入内容。" : model.connectionError
                    }
                  }
                } label: {
                  HStack(spacing: 8) {
                    if isCreating {
                      ProgressView()
                        .tint(.white)
                    } else {
                      Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    }

                    Text(isCreating ? "创建中…" : "创建会话")
                      .font(.system(.subheadline, design: .rounded, weight: .semibold))
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 14)
                  .background(Palette.accent)
                  .foregroundStyle(.white)
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canCreate || isCreating)
                .opacity((canCreate && !isCreating) ? 1 : 0.45)
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 20)
          .contentShape(Rectangle())
          .onTapGesture {
            focusedField = nil
          }
        }
        .scrollDismissesKeyboard(.immediately)
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("新建会话")
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundColor(Palette.ink)
        }

        ToolbarItem(placement: .cancellationAction) {
          Button("关闭") {
            dismiss()
          }
        }
      }
    }
  }
}

private enum NewSessionField: Hashable {
  case cwd
  case prompt
}
