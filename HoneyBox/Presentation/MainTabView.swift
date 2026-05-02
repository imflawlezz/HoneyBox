import Combine
import SwiftUI

struct MainTabView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    @EnvironmentObject private var lock: AppLockManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardVisible: Bool = false
    @State private var hasPromptedThisActiveCycle: Bool = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(env: env)
            }
            .tabItem {
                Label("Homepage", systemImage: "house.fill")
            }

            NavigationStack {
                ArtistsListView(env: env)
            }
            .tabItem {
                Label("Albums", systemImage: "photo.on.rectangle.angled")
            }
        }
        .tint(.accentColor)
        .simultaneousGesture(
            keyboardVisible
            ? TapGesture().onEnded { KeyboardDismiss.hide() }
            : nil
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .overlay {
            if lock.appLockEnabled && !lock.isUnlocked {
                lockOverlay
            }
        }
        .onAppear {
            lock.refreshLockStateForLaunch()
            if lock.appLockEnabled, !lock.isUnlocked {
                Task { await lock.authenticate() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard lock.appLockEnabled else { return }
            switch phase {
            case .active:
                guard !lock.isUnlocked else { return }
                guard !lock.isAuthenticating else { return }
                guard !hasPromptedThisActiveCycle else { return }
                hasPromptedThisActiveCycle = true
                lock.lockNow()
                Task { await lock.authenticate() }
            case .background:
                hasPromptedThisActiveCycle = false
                lock.lockNow()
            case .inactive:
                if !lock.isAuthenticating {
                    hasPromptedThisActiveCycle = false
                    lock.lockNow()
                }
            @unknown default:
                hasPromptedThisActiveCycle = false
                lock.lockNow()
            }
        }
    }

    private var lockOverlay: some View {
        Color.black.ignoresSafeArea()
    }
}
