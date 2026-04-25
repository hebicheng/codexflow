import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @FocusState private var isBaseURLFocused: Bool

  var body: some View {
    NavigationStack {
      ZStack {
        AtmosphereBackground()

        ScrollView {
          VStack(spacing: 12) {
            PanelCard {
              VStack(alignment: .leading, spacing: 12) {
                Text("连接设置")
                  .font(.system(.headline, design: .rounded, weight: .semibold))
                  .foregroundStyle(Palette.ink)

                TextField("http://192.168.1.4:4318", text: $model.baseURLString)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .focused($isBaseURLFocused)
                  .foregroundColor(Palette.ink)
                  .tint(Palette.softBlue)
                  .padding(13)
                  .background(Color.clear)
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                  .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                      .stroke(isBaseURLFocused ? Palette.softBlue.opacity(0.35) : Palette.line, lineWidth: 1)
                  }

                Text("填写 Mac 可被手机访问到的局域网地址，例如 `http://192.168.1.4:4318`。不要填 `0.0.0.0`，真机上也不要填 `127.0.0.1`。")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)

                HStack(spacing: 10) {
                  Button("保存并刷新") {
                    isBaseURLFocused = false
                    dismissKeyboard()
                    Task {
                      model.saveBaseURL()
                      await model.refreshDashboard()
                    }
                  }
                  .font(.system(.subheadline, design: .rounded, weight: .semibold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 13)
                  .background(Palette.accent)
                  .foregroundStyle(.white)
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                  Button("重新连接") {
                    isBaseURLFocused = false
                    dismissKeyboard()
                    Task { await model.refreshDashboard() }
                  }
                  .font(.system(.subheadline, design: .rounded, weight: .semibold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 13)
                  .background(Palette.softBlue.opacity(0.14))
                  .foregroundStyle(Palette.softBlue)
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if model.dashboard.agent.connected && !model.dashboard.agent.listenAddr.isEmpty {
                  Text("Agent 当前监听：\(model.dashboard.agent.listenAddr)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Palette.mutedInk)
                }
              }
            }

            PanelCard(compact: true) {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Text("当前连接")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                  Spacer()

                  HStack(spacing: 6) {
                    Circle()
                      .fill(connectionTone)
                      .frame(width: 8, height: 8)

                    Text(model.isAgentOnline ? "在线" : "离线")
                      .font(.system(.caption, design: .rounded, weight: .bold))
                      .foregroundStyle(connectionTone)
                  }
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(connectionTone.opacity(0.12))
                  .clipShape(Capsule())
                }

                settingsInfoRow("入口地址", model.baseURLString)
                settingsInfoRow("监听地址", model.dashboard.agent.listenAddr.isEmpty ? "未发现" : model.dashboard.agent.listenAddr)
                settingsInfoRow("Codex 路径", model.dashboard.agent.codexBinaryPath)

                if !model.agentConnectionError.isEmpty {
                  Text(model.agentConnectionError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Palette.danger)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
              }
            }

            PanelCard(compact: true) {
              VStack(alignment: .leading, spacing: 8) {
                Text("使用说明")
                  .font(.system(.headline, design: .rounded, weight: .semibold))
                  .foregroundStyle(Palette.ink)

                Text("1. Mac 上先启动 Agent。")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)

                Text("2. 手机填 Mac 的局域网地址。")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)

                Text("3. 首页看会话，审批页处理授权。")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundStyle(Palette.mutedInk)
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .contentShape(Rectangle())
          .onTapGesture {
            isBaseURLFocused = false
            dismissKeyboard()
          }
        }
        .scrollDismissesKeyboard(.immediately)
      }
      .navigationTitle("设置")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var connectionTone: Color {
    model.isAgentOnline ? Palette.accent : Palette.danger
  }

  private func settingsInfoRow(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .foregroundStyle(Palette.mutedInk)

      Text(value)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Palette.shell)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
