import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
  private let baseURLKey = "codexflow.baseURL"
  private var consecutiveDashboardFailures = 0

  @Published var baseURLString: String
  @Published var dashboard: DashboardResponse
  @Published var sessionDetails: [String: SessionDetail]
  @Published var isRefreshing = false
  @Published var isBootstrapped = false
  @Published var isAgentOnline = false
  @Published var agentConnectionError = ""
  @Published var connectionError = ""
  @Published var operationNotice = ""
  @Published var operationNoticeIsError = false
  @Published var composerDraft = ""
  @Published var selectedStartAgentID = "codex"

  private var noticeTask: Task<Void, Never>?

  init() {
    let saved = UserDefaults.standard.string(forKey: baseURLKey) ?? "http://127.0.0.1:4318"
    baseURLString = saved
    dashboard = .placeholder
    sessionDetails = [:]
  }

  func bootstrap() async {
    guard !isBootstrapped else { return }
    isBootstrapped = true
    await refreshDashboard()
  }

  func refreshDashboard() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let client = try APIClient(baseURLString: baseURLString)
      let latestDashboard = try await client.dashboard()
      dashboard = latestDashboard
      syncSelectedAgent(with: latestDashboard)
      consecutiveDashboardFailures = 0
      isAgentOnline = latestDashboard.agent.connected
      agentConnectionError = ""
    } catch {
      consecutiveDashboardFailures += 1
      if consecutiveDashboardFailures >= 2 || !isAgentOnline {
        isAgentOnline = false
        agentConnectionError = error.localizedDescription
      }
    }
  }

  func approvals(for sessionID: String) -> [PendingRequestView] {
    guard supportsApprovals(forSessionID: sessionID) else { return [] }
    return dashboard.approvals
      .filter { $0.threadId == sessionID }
      .sorted { $0.createdAt < $1.createdAt }
  }

  func loadSession(_ session: SessionSummary) async {
    await loadSession(id: session.id)
  }

  func loadSession(id: String) async {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      let detail = try await client.sessionDetail(id: id)
      sessionDetails[id] = detail
      connectionError = ""
    } catch {
      connectionError = error.localizedDescription
    }
  }

  func startSession(cwd: String, prompt: String, agentID: String) async -> Bool {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      let createdSession = try await client.startSession(
        cwd: cwd.trimmingCharacters(in: .whitespacesAndNewlines),
        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
        agent: agentID
      )
      upsertSessionSummary(createdSession)
      connectionError = ""
      showNotice("会话已创建。")
      await refreshDashboard()
      await loadSession(id: createdSession.id)
      return true
    } catch {
      connectionError = error.localizedDescription
      showNotice("创建会话失败：\(error.localizedDescription)", isError: true)
      return false
    }
  }

  func resumeSession(_ session: SessionSummary) async {
    guard canResume(session) else {
      let message = session.resumeBlockedReason.isEmpty ? "这个会话当前不能重新接管。" : session.resumeBlockedReason
      connectionError = message
      showNotice(message, isError: true)
      return
    }
    do {
      let client = try APIClient(baseURLString: baseURLString)
      let updatedSession = try await client.resumeSession(id: session.id)
      upsertSessionSummary(updatedSession)
      connectionError = ""
      showNotice(resumeSuccessNotice(for: updatedSession))
      await refreshDashboard()
      await loadSession(id: session.id)
    } catch {
      connectionError = error.localizedDescription
      showNotice("接管失败：\(error.localizedDescription)", isError: true)
    }
  }

  func archiveSession(_ session: SessionSummary) async {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      try await client.archiveSession(id: session.id)
      sessionDetails.removeValue(forKey: session.id)
      await refreshDashboard()
    } catch {
      connectionError = error.localizedDescription
    }
  }

  func endSession(_ session: SessionSummary) async {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      try await client.endSession(id: session.id)
      await refreshDashboard()
      await loadSession(id: session.id)
    } catch {
      connectionError = error.localizedDescription
    }
  }

  func submitPrompt(for session: SessionSummary, prompt: String, imageUploadIDs: [String] = []) async -> Bool {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedPrompt.isEmpty && imageUploadIDs.isEmpty {
      return false
    }

    do {
      let client = try APIClient(baseURLString: baseURLString)
      if session.lastTurnStatus == "inProgress" && !session.lastTurnId.isEmpty {
        try await client.steerTurn(
          sessionID: session.id,
          turnID: session.lastTurnId,
          prompt: trimmedPrompt,
          imageUploadIDs: imageUploadIDs
        )
      } else {
        _ = try await client.startTurn(
          sessionID: session.id,
          prompt: trimmedPrompt,
          imageUploadIDs: imageUploadIDs
        )
      }
      await refreshDashboard()
      await loadSession(session)
      return true
    } catch {
      connectionError = error.localizedDescription
      return false
    }
  }

  func uploadImage(data: Data, fileName: String) async throws -> UploadedImageRef {
    let client = try APIClient(baseURLString: baseURLString)
    return try await client.uploadImage(data: data, fileName: fileName)
  }

  func interrupt(session: SessionSummary) async {
    guard !session.lastTurnId.isEmpty else { return }
    do {
      let client = try APIClient(baseURLString: baseURLString)
      try await client.interruptTurn(sessionID: session.id, turnID: session.lastTurnId)
      await refreshDashboard()
    } catch {
      connectionError = error.localizedDescription
    }
  }

  func resolve(approval: PendingRequestView, action: ApprovalAction) async {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      try await client.resolveApproval(id: approval.id, result: buildResult(for: approval, action: action))
      await refreshDashboard()
      if let session = dashboard.sessions.first(where: { $0.id == approval.threadId }) {
        await loadSession(session)
      }
    } catch {
      connectionError = error.localizedDescription
    }
  }

  func saveBaseURL() {
    UserDefaults.standard.set(baseURLString, forKey: baseURLKey)
  }

  private func showNotice(_ message: String, isError: Bool = false) {
    noticeTask?.cancel()
    operationNotice = message
    operationNoticeIsError = isError
    noticeTask = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled {
        operationNotice = ""
        operationNoticeIsError = false
      }
    }
  }

  private func buildResult(for approval: PendingRequestView, action: ApprovalAction) -> JSONValue {
    switch approval.kind {
    case "command", "fileChange":
      return .object(["decision": action.decisionValue])
    case "permissions":
      let choice = action.choiceValue
      let permissions: JSONValue
      switch choice {
      case "session", "turn":
        permissions = approval.params["permissions"] ?? .object([:])
      default:
        permissions = .object([
          "network": .null,
          "fileSystem": .null
        ])
      }

      let scope: JSONValue
      switch choice {
      case "session", "turn":
        scope = .string(choice)
      default:
        scope = .null
      }

      return .object([
        "permissions": permissions,
        "scope": scope
      ])
    case "userInput":
      let questionID = firstQuestionID(in: approval.params) ?? "reply"
      return .object([
        "answers": .object([
          questionID: .object([
            "answers": .array([.string(action.freeformText)])
          ])
        ])
      ])
    default:
      return .object(["decision": .string(action.choiceValue)])
    }
  }

  private func firstQuestionID(in params: [String: JSONValue]) -> String? {
    guard case .array(let questions)? = params["questions"] else {
      return nil
    }

    for question in questions {
      if case .object(let questionObject) = question, case .string(let id)? = questionObject["id"] {
        return id
      }
    }
    return nil
  }

  private func upsertSessionSummary(_ session: SessionSummary) {
    var sessions = dashboard.sessions

    if let existingIndex = sessions.firstIndex(where: { $0.id == session.id }) {
      sessions[existingIndex] = session
    } else {
      sessions.append(session)
    }

    sessions.sort {
      if $0.updatedAt == $1.updatedAt {
        return $0.id < $1.id
      }
      return $0.updatedAt > $1.updatedAt
    }

    dashboard = DashboardResponse(
      agent: dashboard.agent,
      agents: dashboard.agents,
      defaultAgent: dashboard.defaultAgent,
      stats: dashboard.stats,
      sessions: sessions,
      approvals: dashboard.approvals
    )
  }

  var startAgentOptions: [AgentOption] {
    dashboard.agents
  }

  var selectedAgentOption: AgentOption? {
    dashboard.agents.first(where: { $0.id == selectedStartAgentID })
  }

  var selectedAgentApprovals: [PendingRequestView] {
    let allowedSessionIDs = Set(
      dashboard.sessions
        .filter { $0.agentId == selectedStartAgentID }
        .map(\.id)
    )
    return dashboard.approvals.filter { allowedSessionIDs.contains($0.threadId) }
  }

  func supportsApprovals(forSessionID sessionID: String) -> Bool {
    guard let session = dashboard.sessions.first(where: { $0.id == sessionID }) else { return true }
    return capabilities(for: session).supportsApprovals
  }

  func supportsResume(for session: SessionSummary) -> Bool {
    canResume(session)
  }

  func supportsArchive(for session: SessionSummary) -> Bool {
    capabilities(for: session).supportsArchive
  }

  func supportsInterruptTurn(for session: SessionSummary) -> Bool {
    capabilities(for: session).supportsInterruptTurn
  }

  func capabilities(for session: SessionSummary) -> AgentCapabilities {
    if let option = dashboard.agents.first(where: { $0.id == session.agentId }) {
      return option.capabilities
    }
    return AgentCapabilities(
      supportsInterruptTurn: true,
      supportsApprovals: true,
      supportsArchive: true,
      supportsResume: true,
      supportsHistoryImport: false
    )
  }

  func canResume(_ session: SessionSummary) -> Bool {
    capabilities(for: session).supportsResume && session.canResume
  }

  private func resumeSuccessNotice(for session: SessionSummary) -> String {
    guard session.isClaudeSession else {
      return "会话已接管，可继续发消息。"
    }
    switch session.runtimeAttachMode {
    case "resumed_existing":
      return "已接入现有 Claude runtime。"
    case "opened_from_history":
      return "已为这条 Claude 历史会话打开新的 runtime。"
    case "new_session":
      return "已打开新的 Claude runtime。"
    default:
      return "Claude 会话已接管。"
    }
  }

  func setSelectedStartAgent(_ id: String) {
    let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return }
    guard dashboard.agents.contains(where: { $0.id == normalized && $0.available }) else { return }
    selectedStartAgentID = normalized
  }

  private func syncSelectedAgent(with dashboard: DashboardResponse) {
    let normalizedCurrent = selectedStartAgentID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let availableIDs = Set(dashboard.agents.filter(\.available).map(\.id))
    if availableIDs.contains(normalizedCurrent) {
      selectedStartAgentID = normalizedCurrent
      return
    }

    let normalizedDefault = dashboard.defaultAgent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if availableIDs.contains(normalizedDefault) {
      selectedStartAgentID = normalizedDefault
      return
    }

    selectedStartAgentID = availableIDs.contains("codex") ? "codex" : (availableIDs.first ?? "codex")
  }
}

enum ApprovalAction: Equatable {
  case choice(String)
  case decision(JSONValue)
  case submitText(String)

  var freeformText: String {
    switch self {
    case .submitText(let text):
      return text
    default:
      return ""
    }
  }

  var choiceValue: String {
    switch self {
    case .choice(let value):
      return value
    case .decision(let value):
      return value.stringValue ?? "accept"
    case .submitText:
      return "accept"
    }
  }

  var decisionValue: JSONValue {
    switch self {
    case .choice(let value):
      return .string(value)
    case .decision(let value):
      return value
    case .submitText:
      return .string("accept")
    }
  }
}
