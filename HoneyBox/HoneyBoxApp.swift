//
//  HoneyBoxApp.swift
//  HoneyBox
//
//  Created by Yahor Artsiomchyk on 06/04/2026.
//

import SwiftUI

@main
struct HoneyBoxApp: App {
    @StateObject private var lock = AppLockManager()
    @State private var env: HoneyBoxEnvironment?

    var body: some Scene {
        WindowGroup {
            Group {
                if let env {
                    MainTabView(env: env)
                        .environmentObject(lock)
                } else {
                    ProgressView("Starting HoneyBox…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                guard env == nil else { return }
                do {
                    lock.refreshLockStateForLaunch()
                    env = try await HoneyBoxEnvironment.bootstrap(lock: lock)
                } catch {
                }
            }
        }
    }
}
