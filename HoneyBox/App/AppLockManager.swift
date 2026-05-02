import Combine
import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockManager: ObservableObject {
    @AppStorage("honeybox.appLockEnabled") var appLockEnabled: Bool = false
    @Published private(set) var isUnlocked: Bool = true
    @Published private(set) var authFailedMessage: String?
    @Published private(set) var isAuthenticating: Bool = false

    func refreshLockStateForLaunch() {
        if appLockEnabled {
            isUnlocked = false
        } else {
            isUnlocked = true
        }
    }

    func lockNow() {
        if appLockEnabled {
            isUnlocked = false
        }
    }

    func noteLockDisabled() {
        isUnlocked = true
        authFailedMessage = nil
    }

    func authenticate() async {
        guard appLockEnabled else {
            isUnlocked = true
            authFailedMessage = nil
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
                || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authFailedMessage = error?.localizedDescription ?? "Passcode not available."
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock HoneyBox"
            )
            isUnlocked = ok
            authFailedMessage = ok ? nil : "Unlock cancelled."
        } catch {
            authFailedMessage = error.localizedDescription
            isUnlocked = false
        }
    }
}
