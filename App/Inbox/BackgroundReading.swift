#if os(iOS)
import BackgroundTasks
#endif
import os
import RiengtuKit
import SwiftUI

/// Starts reading the inbox, and lets it go on when the person locks their iPhone or leaves the
/// app: iOS 26's continued processing, for work the person started, with its progress shown on
/// the Lock Screen. Reading with Apple Intelligence needs iOS 26 too, so before it reading is the
/// rules', which take no time.
///
/// What the Lock Screen shows is only how many are read, never amounts or names. The inbox's
/// database can be written while the device is locked, and reading needs nothing else. iOS
/// limits the model for apps in the background, especially on battery; what it doesn't read
/// waits until the app is open (`InboxStore.isWaitingForModel`).
@MainActor
@Observable
final class BackgroundReading {
    /// In `BGTaskSchedulerPermittedIdentifiers` (`project.yml`).
    static let identifier = "vn.riengtu.reading"

    /// Whether iOS is letting reading go on in the background.
    private(set) var isRunning = false

    @ObservationIgnored private var isRegistered = false
    private static let logger = Logger(subsystem: "vn.riengtu", category: "BackgroundReading")

    /// Starts reading what's new, when the person asks, and asks iOS to let it go on in the
    /// background.
    func start(_ inbox: InboxStore) {
        let wasReading = inbox.isReading
        inbox.startReading()
        guard !wasReading, !isRunning else { return }
        #if os(iOS)
        if #available(iOS 26.0, *) {
            submit(inbox)
        }
        #endif
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    private func submit(_ inbox: InboxStore) {
        if !isRegistered {
            isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak self] task in
                MainActor.assumeIsolated {
                    guard let task = task as? BGContinuedProcessingTask, let self else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self.run(task, inbox: inbox)
                }
            }
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier,
            title: String(localized: "Reading Transactions"),
            subtitle: String(localized: "Starting…")
        )
        // Only now, while the person waits: queued, it could start long after.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Reading goes on while the app is open, and stops when it isn't.
            Self.logger.error("Can't read in the background: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reports how far reading has got, as iOS needs, until it's done, or until iOS or the
    /// person stops it.
    @available(iOS 26.0, *)
    private func run(_ task: BGContinuedProcessingTask, inbox: InboxStore) {
        isRunning = true
        let progress = task.progress
        task.expirationHandler = {
            Task { @MainActor in inbox.stopReading() }
        }
        Task {
            while inbox.isReading {
                let done = inbox.readCount
                let total = done + inbox.unreadCount
                progress.totalUnitCount = Int64(total)
                progress.completedUnitCount = Int64(done)
                task.updateTitle(String(localized: "Reading Transactions"), subtitle: String(localized: "\(done) of \(total)"))
                try? await Task.sleep(for: .seconds(1))
            }
            progress.completedUnitCount = progress.totalUnitCount
            task.setTaskCompleted(success: inbox.unreadCount == 0)
            isRunning = false
        }
    }
    #endif
}
