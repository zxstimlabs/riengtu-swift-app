import SwiftUI

extension View {
    /// Covers the view while Riengtu is locked, and whenever it isn't active, so amounts don't
    /// show in the app switcher.
    ///
    /// Apply it to the root view and to the root of every sheet, because a sheet shows above the
    /// view that presents it.
    func privacyShield() -> some View {
        modifier(PrivacyShield())
    }
}

private struct PrivacyShield: ViewModifier {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if lock.isLocked {
                LockScreen()
            } else if scenePhase != .active {
                Cover()
            }
        }
    }
}

private struct LockScreen: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentUnavailableView {
            Label("Riengtu Is Locked", systemImage: "lock.fill")
        } actions: {
            Button("Unlock") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task(id: scenePhase) {
            if scenePhase == .active {
                await lock.unlockAutomatically()
            }
        }
    }
}

private struct Cover: View {
    var body: some View {
        Image(systemName: "lock.shield.fill")
            .font(.system(size: 56))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .accessibilityHidden(true)
    }
}
