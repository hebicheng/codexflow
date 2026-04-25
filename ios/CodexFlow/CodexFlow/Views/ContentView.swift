import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TabView {
      DashboardView()
        .tabItem {
          Label("会话", systemImage: "square.grid.2x2")
        }

      ApprovalCenterView()
        .tabItem {
          Label("审批", systemImage: "checklist")
        }

      SettingsView()
        .tabItem {
          Label("设置", systemImage: "slider.horizontal.3")
        }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(8))
        await model.refreshDashboard()
      }
    }
  }
}
