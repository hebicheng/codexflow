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
  @Published var composerDraft = ""

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
    dashboard.approvals
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

  func startSession(cwd: String, prompt: String) async -> Bool {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      _ = try await client.startSession(
        cwd: cwd.trimmingCharacters(in: .whitespacesAndNewlines),
        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      await refreshDashboard()
      return true
    } catch {
      connectionError = error.localizedDescription
      return false
    }
  }

  func resumeSession(_ session: SessionSummary) async {
    do {
      let client = try APIClient(baseURLString: baseURLString)
      let updatedSession = try await client.resumeSession(id: session.id)
      upsertSessionSummary(updatedSession)
      await refreshDashboard()
      await loadSession(id: session.id)
    } catch {
      connectionError = error.localizedDescription
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

  func submitPrompt(for session: SessionSummary, prompt: String) async {
    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    do {
      let client = try APIClient(baseURLString: baseURLString)
      if session.lastTurnStatus == "inProgress" && !session.lastTurnId.isEmpty {
        try await client.steerTurn(sessionID: session.id, turnID: session.lastTurnId, prompt: prompt)
      } else {
        _ = try await client.startTurn(sessionID: session.id, prompt: prompt)
      }
      await refreshDashboard()
      await loadSession(session)
    } catch {
      connectionError = error.localizedDescription
    }
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
      stats: dashboard.stats,
      sessions: sessions,
      approvals: dashboard.approvals
    )
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
