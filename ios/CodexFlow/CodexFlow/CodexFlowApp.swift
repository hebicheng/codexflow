import SwiftUI
import UIKit

@main
struct CodexFlowApp: App {
  @StateObject private var model = AppModel()

  init() {
    let navigationAppearance = UINavigationBarAppearance()
    navigationAppearance.configureWithOpaqueBackground()
    navigationAppearance.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1)
    navigationAppearance.shadowColor = .clear
    navigationAppearance.titleTextAttributes = [
      .foregroundColor: UIColor(red: 0.11, green: 0.13, blue: 0.15, alpha: 1)
    ]
    navigationAppearance.largeTitleTextAttributes = [
      .foregroundColor: UIColor(red: 0.11, green: 0.13, blue: 0.15, alpha: 1)
    ]

    let navigationBar = UINavigationBar.appearance()
    navigationBar.standardAppearance = navigationAppearance
    navigationBar.scrollEdgeAppearance = navigationAppearance
    navigationBar.compactAppearance = navigationAppearance
    if #available(iOS 15.0, *) {
      navigationBar.compactScrollEdgeAppearance = navigationAppearance
    }
    navigationBar.tintColor = UIColor(red: 0.39, green: 0.42, blue: 0.44, alpha: 1)
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .task {
          await model.bootstrap()
        }
    }
  }
}
