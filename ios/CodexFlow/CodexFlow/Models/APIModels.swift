import Foundation

struct DashboardResponse: Codable, Hashable {
  let agent: AgentSnapshot
  let stats: DashboardStats
  let sessions: [SessionSummary]
  let approvals: [PendingRequestView]

  static let placeholder = DashboardResponse(
    agent: .init(connected: false, startedAt: Date(), listenAddr: "", codexBinaryPath: "codex"),
    stats: .init(totalSessions: 0, loadedSessions: 0, activeSessions: 0, pendingApprovals: 0),
    sessions: [],
    approvals: []
  )
}

struct AgentSnapshot: Codable, Hashable {
  let connected: Bool
  let startedAt: Date
  let listenAddr: String
  let codexBinaryPath: String
}

struct DashboardStats: Codable, Hashable {
  let totalSessions: Int
  let loadedSessions: Int
  let activeSessions: Int
  let pendingApprovals: Int
}

struct SessionSummary: Codable, Hashable, Identifiable {
  let id: String
  let name: String
  let preview: String
  let cwd: String
  let source: String
  let status: String
  let activeFlags: [String]
  let loaded: Bool
  let updatedAt: Int64
  let createdAt: Int64
  let modelProvider: String
  let branch: String
  let pendingApprovals: Int
  let lastTurnId: String
  let lastTurnStatus: String
  let agentNickname: String
  let agentRole: String
  let ended: Bool

  var displayName: String {
    if let explicitName = normalizedTitle(name) {
      return explicitName
    }
    if let nickname = normalizedTitle(agentNickname) {
      return nickname
    }
    if let directoryTitle = directoryName {
      return directoryTitle
    }
    if let previewTitle = previewTitle {
      return previewTitle
    }
    return "Session \(shortID)"
  }

  var previewSummary: String {
    normalizedPreview(preview)
  }

  var previewExcerpt: String {
    normalizedText(preview).headTailTruncated(maxLength: 220, head: 140, tail: 72)
  }

  var updatedAtDisplay: String {
    formattedTimestamp(updatedAt)
  }

  var isActive: Bool {
    status == "active"
  }

  var isEnded: Bool {
    ended
  }

  var hasWaitingState: Bool {
    activeFlags.contains("waitingOnApproval") || activeFlags.contains("waitingOnUserInput")
  }

  private var directoryName: String? {
    let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let component = URL(fileURLWithPath: trimmed).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    return component.isEmpty ? nil : component
  }

  private var previewTitle: String? {
    let cleaned = normalizedPreview(preview)
    guard !cleaned.isEmpty else { return nil }

    if cleaned.count <= 32 {
      return cleaned
    }

    let end = cleaned.index(cleaned.startIndex, offsetBy: 32)
    return "\(cleaned[..<end])…"
  }

  private var shortID: String {
    String(id.prefix(8))
  }

  private func normalizedTitle(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func normalizedPreview(_ value: String) -> String {
    value
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })?
      .replacingOccurrences(of: "\t", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private func normalizedText(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func formattedTimestamp(_ timestamp: Int64) -> String {
    guard timestamp > 0 else { return "未知" }

    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
      return "今天 \(Self.timeFormatter.string(from: date))"
    }

    if calendar.isDateInYesterday(date) {
      return "昨天 \(Self.timeFormatter.string(from: date))"
    }

    if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
      return Self.monthDayFormatter.string(from: date)
    }

    return Self.fullDateFormatter.string(from: date)
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static let monthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
  }()

  private static let fullDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()
}

extension String {
  func headTailTruncated(maxLength: Int, head: Int, tail: Int) -> String {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxLength else { return trimmed }

    let safeHead = min(head, trimmed.count)
    let safeTail = min(tail, max(0, trimmed.count - safeHead))
    guard safeHead > 0, safeTail > 0, safeHead + safeTail < trimmed.count else {
      return trimmed
    }

    let start = trimmed.index(trimmed.startIndex, offsetBy: safeHead)
    let end = trimmed.index(trimmed.endIndex, offsetBy: -safeTail)
    return "\(trimmed[..<start]) … \(trimmed[end...])"
  }
}

struct SessionDetail: Codable, Hashable {
  let summary: SessionSummary
  let turns: [TurnDetail]
}

struct TurnDetail: Codable, Hashable, Identifiable {
  let id: String
  let status: String
  let startedAt: Int64
  let completedAt: Int64
  let durationMs: Int64
  let error: String
  let diff: String
  let planExplanation: String
  let plan: [PlanStep]
  let items: [TurnItem]
}

struct PlanStep: Codable, Hashable, Identifiable {
  var id: String { "\(status)-\(step)" }
  let step: String
  let status: String
}

struct TurnItem: Codable, Hashable, Identifiable {
  let id: String
  let type: String
  let title: String
  let body: String
  let status: String
  let auxiliary: String
  let metadata: [String: String]
}

struct PendingRequestView: Codable, Hashable, Identifiable {
  let id: String
  let method: String
  let kind: String
  let threadId: String
  let turnId: String
  let itemId: String
  let reason: String
  let summary: String
  let choices: [String]
  let createdAt: Date
  let params: [String: JSONValue]
}

struct SessionListEnvelope: Codable {
  let data: [SessionSummary]
}

struct ApprovalListEnvelope: Codable {
  let data: [PendingRequestView]
}

enum JSONValue: Codable, Hashable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }

  func foundationValue() -> Any {
    switch self {
    case .string(let value):
      return value
    case .number(let value):
      return value
    case .bool(let value):
      return value
    case .object(let value):
      return value.mapValues { $0.foundationValue() }
    case .array(let value):
      return value.map { $0.foundationValue() }
    case .null:
      return NSNull()
    }
  }

  var stringValue: String? {
    if case .string(let value) = self {
      return value
    }
    return nil
  }
}
