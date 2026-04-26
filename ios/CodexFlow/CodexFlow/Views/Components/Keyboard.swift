import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

func dismissKeyboard() {
  #if canImport(UIKit)
  Task { @MainActor in
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
  #endif
}
