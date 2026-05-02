import SwiftUI
import UIKit

extension View {
    func disablesIdleTimerWhilePresented() -> some View {
        modifier(DisableIdleTimerWhilePresentedModifier())
    }
}

private struct DisableIdleTimerWhilePresentedModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}
