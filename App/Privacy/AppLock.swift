import LocalAuthentication
import SwiftUI

/// Locks Riengtu behind Face ID, Touch ID or the device passcode, when the person turns it on.
///
/// Once on, Riengtu locks each time it goes to the background, and when it launches.
@Observable
final class AppLock {
    /// How the device can unlock Riengtu.
    enum Method {
        case faceID, touchID, opticID, passcode
        /// The device has no passcode, so there's nothing to lock with.
        case unavailable
    }

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isAuthenticating = false
    /// Whether to ask right away the next time the lock screen shows, which is only once after
    /// each lock, so cancelling doesn't ask again.
    @ObservationIgnored private var promptsAutomatically: Bool

    private static let enabledKey = "appLockEnabled"

    init(defaults: UserDefaults = .standard) {
        let enabled = defaults.bool(forKey: Self.enabledKey)
        self.defaults = defaults
        isEnabled = enabled
        isLocked = enabled
        promptsAutomatically = enabled
    }

    var method: Method {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        return switch context.biometryType {
        case .faceID: .faceID
        case .touchID: .touchID
        case .opticID: .opticID
        default: .passcode
        }
    }

    func lock() {
        guard isEnabled, !isLocked else { return }
        isLocked = true
        promptsAutomatically = true
        #if os(iOS)
        // Put the keyboard away, so nothing can be typed behind the lock screen.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    func unlock() async {
        guard isLocked else { return }
        if method == .unavailable {
            // The passcode was turned off, so there's nothing to unlock with. Staying locked would
            // lock the person out of their own data.
            isLocked = false
            return
        }
        if await authenticate() {
            isLocked = false
        }
    }

    /// Unlocks if the lock screen hasn't asked yet since Riengtu locked.
    func unlockAutomatically() async {
        guard promptsAutomatically else { return }
        promptsAutomatically = false
        await unlock()
    }

    /// Turning the lock on asks for Face ID or the passcode first, so no one can turn on a lock
    /// they can't open.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard method != .unavailable, await authenticate() else { return }
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    private func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            return try await LAContext().evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock Riengtu to see your spending and assets.")
            )
        } catch {
            return false
        }
    }
}
