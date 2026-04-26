import Foundation

enum APIError: LocalizedError {
  case invalidBaseURL
  case server(String)
  case invalidResponse
  case invalidDate(String)

  var errorDescription: String? {
    switch self {
    case .invalidBaseURL:
      return "The agent base URL is invalid."
    case .server(let message):
      return message
    case .invalidResponse:
      return "The agent returned an invalid response."
    case .invalidDate(let value):
      return "The agent returned an unsupported date: \(value)"
    }
  }
}

struct APIClient {
  let baseURL: URL
  private static let internetDateTimeFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  init(baseURLString: String) throws {
    guard let url = URL(string: baseURLString) else {
      throw APIError.invalidBaseURL
    }
    self.baseURL = url
  }

  func dashboard() async throws -> DashboardResponse {
    try await decode(path: "/api/v1/dashboard")
  }

  func sessionDetail(id: String) async throws -> SessionDetail {
    try await decode(path: "/api/v1/sessions/\(id)")
  }

  func refreshSessions() async throws {
    _ = try await sendJSON(path: "/api/v1/sessions", method: "POST", body: [
      "action": "refresh"
    ])
  }

  func startSession(cwd: String, prompt: String, agent: String) async throws -> SessionSummary {
    try await decode(
      path: "/api/v1/sessions",
      method: "POST",
      body: [
        "action": "start",
        "cwd": cwd,
        "prompt": prompt,
        "agent": agent
      ],
      timeoutInterval: 45
    )
  }

  func resumeSession(id: String) async throws -> SessionSummary {
    try await decode(path: "/api/v1/sessions/\(id)/resume", method: "POST", body: [:])
  }

  func endSession(id: String) async throws {
    _ = try await sendJSON(path: "/api/v1/sessions/\(id)/end", method: "POST", body: [:])
  }

  func archiveSession(id: String) async throws {
    _ = try await sendJSON(path: "/api/v1/sessions/\(id)/archive", method: "POST", body: [:])
  }

  func startTurn(sessionID: String, prompt: String) async throws -> TurnDetail {
    try await startTurn(sessionID: sessionID, prompt: prompt, imageUploadIDs: [])
  }

  func startTurn(sessionID: String, prompt: String, imageUploadIDs: [String]) async throws -> TurnDetail {
    try await decode(
      path: "/api/v1/sessions/\(sessionID)/turns/start",
      method: "POST",
      body: [
        "prompt": prompt,
        "inputs": buildInputs(prompt: prompt, imageUploadIDs: imageUploadIDs)
      ]
    )
  }

  func steerTurn(sessionID: String, turnID: String, prompt: String) async throws {
    try await steerTurn(sessionID: sessionID, turnID: turnID, prompt: prompt, imageUploadIDs: [])
  }

  func steerTurn(sessionID: String, turnID: String, prompt: String, imageUploadIDs: [String]) async throws {
    _ = try await sendJSON(
      path: "/api/v1/sessions/\(sessionID)/turns/steer",
      method: "POST",
      body: [
        "turnId": turnID,
        "prompt": prompt,
        "inputs": buildInputs(prompt: prompt, imageUploadIDs: imageUploadIDs)
      ]
    )
  }

  func interruptTurn(sessionID: String, turnID: String) async throws {
    _ = try await sendJSON(
      path: "/api/v1/sessions/\(sessionID)/turns/interrupt",
      method: "POST",
      body: ["turnId": turnID]
    )
  }

  func resolveApproval(id: String, result: JSONValue) async throws {
    _ = try await sendJSON(
      path: "/api/v1/approvals/\(id)/resolve",
      method: "POST",
      body: ["result": result.foundationValue()]
    )
  }

  func uploadImage(data: Data, fileName: String) async throws -> UploadedImageRef {
    let endpoint = baseURL.appending(path: "/api/v1/uploads/image")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 45

    let boundary = "CodexFlowBoundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body

    let (responseData, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if
        let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
        let message = json["error"] as? String
      {
        throw APIError.server(message)
      }
      throw APIError.server("Request failed with status \(http.statusCode)")
    }

    let decoder = JSONDecoder()
    return try decoder.decode(UploadedImageRef.self, from: responseData)
  }

  private func buildInputs(prompt: String, imageUploadIDs: [String]) -> [[String: Any]] {
    var inputs: [[String: Any]] = []
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedPrompt.isEmpty {
      inputs.append([
        "type": "text",
        "text": trimmedPrompt
      ])
    }
    for id in imageUploadIDs {
      let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        continue
      }
      inputs.append([
        "type": "image",
        "uploadId": trimmed
      ])
    }
    return inputs
  }

  private func decode<T: Decodable>(
    path: String,
    method: String = "GET",
    body: [String: Any] = [:],
    timeoutInterval: TimeInterval = 20
  ) async throws -> T {
    let data = try await sendJSON(
      path: path,
      method: method,
      body: body,
      allowEmptyBody: method == "GET",
      timeoutInterval: timeoutInterval
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)

      if let date = APIClient.fractionalSecondsFormatter.date(from: value) {
        return date
      }
      if let date = APIClient.internetDateTimeFormatter.date(from: value) {
        return date
      }

      throw APIError.invalidDate(value)
    }
    return try decoder.decode(T.self, from: data)
  }

  @discardableResult
  private func sendJSON(
    path: String,
    method: String,
    body: [String: Any],
    allowEmptyBody: Bool = false,
    timeoutInterval: TimeInterval = 20
  ) async throws -> Data {
    let endpoint = baseURL.appending(path: path)
    var request = URLRequest(url: endpoint)
    request.httpMethod = method
    request.timeoutInterval = timeoutInterval
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if method != "GET" || !allowEmptyBody {
      request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
      if
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let message = json["error"] as? String
      {
        throw APIError.server(message)
      }
      throw APIError.server("Request failed with status \(http.statusCode)")
    }

    return data
  }
}
