import RiengtuKit
import SwiftUI

/// Apple Intelligence reading what's new in the inbox, in detail: how far it's got (`ReadingCard`),
/// and each transaction as it's read. Opened from the card on the Inbox tab.
struct ReadingView: View {
    /// Fewer than this are read as they come; more wait for the person to start them, since each
    /// takes a couple of seconds and they can go on in the background (`BackgroundReading`).
    static let minimumCount = 3

    @Environment(InboxStore.self) private var inbox
    @Environment(BackgroundReading.self) private var backgroundReading
    @Environment(\.dismiss) private var dismiss
    /// What's being read, from when the screen opened, and what arrives meanwhile.
    @State private var ids: [CapturedTransaction.ID] = []

    private var items: [CapturedTransaction] {
        ids.compactMap { id in inbox.items.first { $0.id == id } }
    }

    var body: some View {
        let items = items
        let done = items.count(where: \.wasRead)
        let isDone = !items.isEmpty && done == items.count
        NavigationStack {
            List {
                Section {
                    ReadingCard(done: done, total: items.count)
                }

                Section {
                    ForEach(items) { item in
                        ReadingRow(item: item, isCurrent: item.id == inbox.readingItemID, outcome: item.handledAt == nil ? nil : Outcome(item, in: inbox))
                    }
                }
            }
            .animation(.default, value: done)
            .navigationTitle(isDone ? Text("Ready to Check") : Text("Reading Transactions"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isDone {
                        Button("Review") { dismiss() }
                    } else {
                        Button("Hide") { dismiss() }
                    }
                }
            }
        }
        .privacyShield()
        .onAppear {
            TransactionReader.prewarm()
            // What's being read, or waits to be, and what this reading has read already.
            let read = inbox.isReading ? inbox.pending.filter(\.wasRead).suffix(inbox.readCount) : []
            ids = (read + inbox.pending.filter { !$0.wasRead }).reversed().map(\.id)
        }
        .onChange(of: inbox.unreadCount) {
            // Ones that arrive meanwhile join the end.
            let new = inbox.pending.filter { !$0.wasRead && !ids.contains($0.id) }.reversed().map(\.id)
            ids += new
        }
    }
}

/// How reading the inbox goes: what waits, about how long it takes, and a button to start; then
/// how far it's got and about how long is left; or why it stopped. On the Inbox tab, and atop the
/// reading screen.
struct ReadingCard: View {
    /// How many are read, and how many in all.
    let done: Int
    let total: Int
    /// Opens the reading screen, from the Inbox tab.
    var showsDetails: (() -> Void)?

    @Environment(InboxStore.self) private var inbox
    @Environment(BackgroundReading.self) private var backgroundReading

    var body: some View {
        let isDone = total > 0 && done == total
        VStack(alignment: .leading, spacing: 10) {
            if !inbox.isReading, !isDone, done == 0, !inbox.isWaitingForModel {
                Text("\(total) new to read")
                    .font(.headline)
                // About two seconds each, as measured on sample notices.
                Text("Apple Intelligence reads them on this device, in about \(Duration.seconds(max(10, total * 2)), format: .units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1)). The screen stays on until it’s done, so you can put your iPhone down.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    backgroundReading.start(inbox)
                } label: {
                    Text("Start Reading")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                HStack(alignment: .firstTextBaseline) {
                    Text("\(done) of \(total)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    status(isDone: isDone, left: total - done)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                Group {
                    if inbox.isWaitingForModel, !inbox.isReading {
                        Text("Apple Intelligence can’t read more just now. The rest are read when you try again or open Riêng Tư later.")
                    } else if isDone {
                        EmptyView()
                    } else if backgroundReading.isRunning {
                        Text("The screen stays on until it’s done. To turn it off, press the side button: Riêng Tư goes on reading, more slowly on battery, and shows how far it’s got on the Lock Screen.")
                    } else {
                        Text("The screen stays on until it’s done. Keep Riêng Tư open while it reads.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                HStack {
                    if inbox.isWaitingForModel, !inbox.isReading {
                        Button("Try Again") { backgroundReading.start(inbox) }
                            .buttonStyle(.bordered)
                    }
                    if let showsDetails, !isDone {
                        Button("Details", action: showsDetails)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .animation(.default, value: done)
    }

    /// Done, about how long is left from how long each took so far, or starting.
    @ViewBuilder private func status(isDone: Bool, left: Int) -> some View {
        if isDone {
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if let start = inbox.readingStartedAt, inbox.readCount > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // From how long each has taken so far.
                let each = context.date.timeIntervalSince(start) / Double(inbox.readCount)
                timeLeft(each * Double(left))
            }
        } else {
            // About two seconds each, as measured on sample notices, until the first is read.
            timeLeft(Double(left) * 2)
        }
    }
}

/// About how long is left, rounded up to 5 seconds, so it doesn't count down every second.
private func timeLeft(_ seconds: Double) -> Text {
    let seconds = max(5, Int((seconds / 5).rounded(.up)) * 5)
    return Text("About \(Duration.seconds(seconds), format: .units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 2)) left")
}

/// A transaction being read: waiting, being read, or read, with what was read from it.
private struct ReadingRow: View {
    let item: CapturedTransaction
    let isCurrent: Bool
    /// What became of it, once it's left out or handled.
    let outcome: Outcome?

    var body: some View {
        HStack(spacing: 12) {
            CapturedIcon(item: item)
            VStack(alignment: .leading, spacing: 2) {
                if item.wasRead {
                    CapturedTitle(item: item)
                        .lineLimit(2)
                } else {
                    Text(verbatim: firstLine)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Text(item.date, format: .dateTime.day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let outcome {
                outcome.name
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else if item.wasRead {
                CapturedAmount(item: item)
            } else if isCurrent {
                ProgressView()
            } else {
                Text("Waiting")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The message's first line, such as a notification's amount, until it's read.
    private var firstLine: String {
        item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

#Preview {
    ReadingView()
        .previewEnvironment()
}
