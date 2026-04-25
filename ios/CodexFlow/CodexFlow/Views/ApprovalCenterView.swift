import SwiftUI

struct ApprovalCenterView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationStack {
      ZStack {
        AtmosphereBackground()

        ScrollView {
          VStack(spacing: 12) {
            PanelCard(compact: true) {
              Text("这里处理 Codex 发来的命令审批、文件变更审批、权限审批，以及需要你回答的问题。")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Palette.mutedInk)
            }

            if model.dashboard.approvals.isEmpty {
              PanelCard(compact: true) {
                Text("当前没有待处理审批。")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)
              }
            } else {
              ApprovalList(approvals: model.dashboard.approvals, showSessionLabel: true)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .contentShape(Rectangle())
          .onTapGesture {
            dismissKeyboard()
          }
        }
        .scrollDismissesKeyboard(.immediately)
      }
      .navigationTitle("审批")
      .navigationBarTitleDisplayMode(.inline)
      .refreshable {
        await model.refreshDashboard()
      }
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(2))
          await model.refreshDashboard()
        }
      }
    }
  }
}

struct ApprovalList: View {
  let approvals: [PendingRequestView]
  let showSessionLabel: Bool

  var body: some View {
    ForEach(approvals) { approval in
      ApprovalCard(approval: approval, showSessionLabel: showSessionLabel)
    }
  }
}

struct SessionApprovalSheet: View {
  let title: String
  let approvals: [PendingRequestView]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        AtmosphereBackground()

        ScrollView {
          VStack(spacing: 12) {
            if approvals.isEmpty {
              PanelCard(compact: true) {
                Text("当前没有待处理审批。")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)
              }
            } else {
              ApprovalList(approvals: approvals, showSessionLabel: false)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .contentShape(Rectangle())
          .onTapGesture {
            dismissKeyboard()
          }
        }
        .scrollDismissesKeyboard(.immediately)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("关闭") { dismiss() }
        }
      }
    }
  }
}

struct ApprovalCard: View {
  let approval: PendingRequestView
  let showSessionLabel: Bool

  var body: some View {
    PanelCard(compact: true) {
      ApprovalCardBody(approval: approval, showSessionLabel: showSessionLabel, embedded: false)
    }
  }
}

struct ApprovalCardBody: View {
  @EnvironmentObject private var model: AppModel
  let approval: PendingRequestView
  let showSessionLabel: Bool
  let embedded: Bool

  @State private var replyText = ""
  @FocusState private var isReplyFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text(kindTitle)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.ink)

          Text(approval.summary)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Palette.mutedInk)

          if showSessionLabel {
            Text(sessionLabel)
              .font(.system(.caption, design: .rounded, weight: .medium))
              .foregroundStyle(Palette.ink)
          }

          if !approval.reason.isEmpty {
            Text(approval.reason)
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(Palette.mutedInk)
          }

          if let question = firstQuestion {
            Text(question.question)
              .font(.system(.caption, design: .rounded, weight: .medium))
              .foregroundStyle(Palette.ink)
          }
        }

        Spacer()

        StatusPill(status: approval.kind, waiting: true)
      }

      if approval.kind == "userInput" {
        if !questionOptions.isEmpty {
          VStack(spacing: 10) {
            ForEach(questionOptions, id: \.label) { option in
              actionButton(title: option.label, background: Palette.softBlue.opacity(0.15), foreground: Palette.softBlue) {
                isReplyFocused = false
                dismissKeyboard()
                await model.resolve(approval: approval, action: .submitText(option.label))
              }
            }
          }
        }

        TextField("Reply", text: $replyText)
          .textInputAutocapitalization(.sentences)
          .focused($isReplyFocused)
          .foregroundColor(Palette.ink)
          .tint(Palette.softBlue)
          .padding(13)
          .background(Color.clear)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(isReplyFocused ? Palette.softBlue.opacity(0.35) : Palette.line, lineWidth: 1)
          }

        Button {
          isReplyFocused = false
          dismissKeyboard()
          Task {
            await model.resolve(approval: approval, action: .submitText(replyText))
          }
        } label: {
          Text("提交回复")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Palette.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      } else {
        VStack(spacing: 10) {
          ForEach(choiceButtons) { button in
            actionButton(title: button.title, background: button.background, foreground: button.foreground) {
              await model.resolve(approval: approval, action: button.action)
            }
          }
        }
      }
    }
    .padding(embedded ? 12 : 0)
    .background(embedded ? Palette.warning.opacity(0.07) : Color.clear)
    .overlay {
      if embedded {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Palette.warning.opacity(0.18), lineWidth: 1)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var sessionLabel: String {
    if let session = model.dashboard.sessions.first(where: { $0.id == approval.threadId }) {
      return "会话：\(session.displayName)"
    }
    return "会话：\(approval.threadId)"
  }

  private var kindTitle: String {
    switch approval.kind {
    case "command":
      return "命令审批"
    case "fileChange":
      return "文件变更审批"
    case "permissions":
      return "权限审批"
    case "userInput":
      return "需要你的回复"
    default:
      return "审批"
    }
  }

  private var firstQuestion: ApprovalQuestion? {
    approvalQuestions.first
  }

  private var questionOptions: [ApprovalQuestionOption] {
    firstQuestion?.options ?? []
  }

  private var approvalQuestions: [ApprovalQuestion] {
    guard case .array(let questions)? = approval.params["questions"] else {
      return []
    }

    return questions.compactMap { value in
      guard case .object(let object) = value else { return nil }
      let id = object["id"]?.stringValue ?? UUID().uuidString
      let question = object["question"]?.stringValue ?? object["prompt"]?.stringValue ?? object["title"]?.stringValue ?? ""

      let options: [ApprovalQuestionOption]
      if case .array(let rawOptions)? = object["options"] {
        options = rawOptions.compactMap { optionValue in
          guard case .object(let optionObject) = optionValue,
                let label = optionObject["label"]?.stringValue,
                !label.isEmpty else {
            return nil
          }
          let description = optionObject["description"]?.stringValue ?? ""
          return ApprovalQuestionOption(label: label, description: description)
        }
      } else {
        options = []
      }

      return ApprovalQuestion(id: id, question: question, options: options)
    }
  }

  private var choiceButtons: [ApprovalChoiceButton] {
    if approval.kind == "command", !availableDecisionButtons.isEmpty {
      return availableDecisionButtons
    }

    let effectiveChoices = approval.choices.isEmpty ? fallbackChoices : approval.choices
    return effectiveChoices.map { choice in
      switch choice {
      case "accept":
        return .init(id: choice, action: .choice(choice), title: "允许一次", background: Palette.accent, foreground: .white)
      case "acceptForSession":
        return .init(id: choice, action: .choice(choice), title: "本会话内允许", background: Palette.softBlue.opacity(0.15), foreground: Palette.softBlue)
      case "decline":
        return .init(id: choice, action: .choice(choice), title: "拒绝", background: Palette.danger.opacity(0.12), foreground: Palette.danger)
      case "cancel":
        return .init(id: choice, action: .choice(choice), title: "取消", background: Palette.shell, foreground: Palette.mutedInk)
      case "session":
        return .init(id: choice, action: .choice(choice), title: "授权到会话", background: Palette.softBlue, foreground: .white)
      case "turn":
        return .init(id: choice, action: .choice(choice), title: "仅本轮授权", background: Palette.accent, foreground: .white)
      default:
        return .init(id: choice, action: .choice(choice), title: choice, background: Palette.shell, foreground: Palette.ink)
      }
    }
  }

  private var availableDecisionButtons: [ApprovalChoiceButton] {
    guard case .array(let decisions)? = approval.params["availableDecisions"] else {
      return []
    }

    return decisions.compactMap(commandDecisionButton(for:))
  }

  private func commandDecisionButton(for decision: JSONValue) -> ApprovalChoiceButton? {
    switch decision {
    case .string(let raw):
      switch raw {
      case "accept":
        return .init(id: raw, action: .decision(.string(raw)), title: "允许一次", background: Palette.accent, foreground: .white)
      case "acceptForSession":
        return .init(id: raw, action: .decision(.string(raw)), title: "本会话内允许", background: Palette.softBlue.opacity(0.15), foreground: Palette.softBlue)
      case "decline":
        return .init(id: raw, action: .decision(.string(raw)), title: "拒绝", background: Palette.danger.opacity(0.12), foreground: Palette.danger)
      case "cancel":
        return .init(id: raw, action: .decision(.string(raw)), title: "取消并中断本轮", background: Palette.shell, foreground: Palette.mutedInk)
      default:
        return .init(id: raw, action: .decision(.string(raw)), title: raw, background: Palette.shell, foreground: Palette.ink)
      }

    case .object(let object):
      if let payload = object["acceptWithExecpolicyAmendment"] {
        return .init(
          id: "acceptWithExecpolicyAmendment",
          action: .decision(.object(["acceptWithExecpolicyAmendment": payload])),
          title: "允许并记住这类命令",
          background: Palette.softBlue,
          foreground: .white
        )
      }

      if case .object(let amendmentWrapper)? = object["applyNetworkPolicyAmendment"],
         case .object(let amendment)? = amendmentWrapper["network_policy_amendment"] {
        let host = amendment["host"]?.stringValue ?? "该主机"
        let action = amendment["action"]?.stringValue ?? ""
        let isAllow = action == "allow"
        return .init(
          id: "applyNetworkPolicyAmendment-\(action)-\(host)",
          action: .decision(.object(["applyNetworkPolicyAmendment": .object(["network_policy_amendment": .object(amendment)])])),
          title: isAllow ? "允许并记住 \(host)" : "拒绝并记住 \(host)",
          background: isAllow ? Palette.softBlue.opacity(0.15) : Palette.danger.opacity(0.12),
          foreground: isAllow ? Palette.softBlue : Palette.danger
        )
      }

      if let rawKey = object.keys.first {
        return .init(id: rawKey, action: .decision(.object(object)), title: rawKey, background: Palette.shell, foreground: Palette.ink)
      }

      return nil

    default:
      return nil
    }
  }

  private var fallbackChoices: [String] {
    switch approval.kind {
    case "command", "fileChange":
      return ["accept", "acceptForSession", "decline", "cancel"]
    case "permissions":
      return ["session", "turn", "decline"]
    default:
      return ["decline"]
    }
  }

  private func actionButton(title: String, background: Color, foreground: Color, action: @escaping @Sendable () async -> Void) -> some View {
    Button {
      dismissKeyboard()
      Task { await action() }
    } label: {
      Text(title)
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }
}

struct ApprovalChoiceButton: Identifiable {
  let id: String
  let action: ApprovalAction
  let title: String
  let background: Color
  let foreground: Color
}

struct ApprovalQuestion {
  let id: String
  let question: String
  let options: [ApprovalQuestionOption]
}

struct ApprovalQuestionOption {
  let label: String
  let description: String
}
