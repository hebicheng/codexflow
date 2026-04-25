import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
func dismissKeyboard() {
  #if canImport(UIKit)
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  #endif
}
