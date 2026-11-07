import RiengtuKit
import SwiftUI

/// How long the inbox keeps what was added or dismissed, with the message as it came, before
/// deleting it. A setting, not data, so it lives in `UserDefaults`.
enum InboxHistoryDuration: Int, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case month = 30

    static let key = "inboxHistoryDays"
    static let standard = InboxHistoryDuration.week

    var id: Int { rawValue }

    var name: LocalizedStringResource {
        switch self {
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        }
    }

    /// What was handled before this is deleted.
    func cutoff(from now: Date) -> Date {
        now.addingTimeInterval(-Double(rawValue) * 86_400)
    }

    /// The person's choice, or the standard one.
    static func days(_ days: Int) -> InboxHistoryDuration {
        InboxHistoryDuration(rawValue: days) ?? standard
    }
}

/// What was added to the ledger or dismissed from the inbox, most recently first, with the
/// message as it came, so the person can check what was read from it. The app deletes each after
/// the time chosen in Settings.
struct InboxHistoryView: View {
    @Environment(InboxStore.self) private var inbox
    @State private var confirmsDeleting = false
    @State private var deleteFailed = false

    var body: some View {
        let history = inbox.history
        List {
            ForEach(history) { item in
                NavigationLink {
                    HistoryItemView(item: item)
                } label: {
                    HistoryRow(item: item, outcome: Outcome(item, in: inbox))
                }
            }
            .onDelete { offsets in
                delete(offsets.map { history[$0].id })
            }
        }
        .overlay {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("What you add or dismiss from the inbox stays here with its message for a while, then it’s deleted.")
                }
            }
        }
        .navigationTitle("Inbox History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete History", role: .destructive) { confirmsDeleting = true }
                    .disabled(history.isEmpty)
            }
        }
        .confirmationDialog("Delete the inbox’s history?", isPresented: $confirmsDeleting, titleVisibility: .visible) {
            Button("Delete History", role: .destructive) {
                do {
                    try inbox.deleteHistory()
                } catch {
                    deleteFailed = true
                }
            }
        } message: {
            Text("The messages are deleted. What you added stays in the ledger, and what waits in the inbox stays there.")
        }
        .alert("Couldn’t Delete", isPresented: $deleteFailed) {
            Button("OK") {}
        } message: {
            Text("Riêng Tư couldn’t delete the history. Try again.")
        }
    }

    private func delete(_ ids: [CapturedTransaction.ID]) {
        do {
            for id in ids { try inbox.remove(id: id) }
        } catch {
            deleteFailed = true
        }
    }
}

/// What became of an item in the history.
enum Outcome {
    case added, dismissed
    /// Left out as one side of a transfer between the person's own accounts.
    case betweenOwnAccounts
    /// Left out because the same transaction came in another message.
    case cameTwice
    /// Left out because it isn't about money that moved, such as an ad or a one-time code.
    case notTransaction

    init(_ item: CapturedTransaction, in inbox: InboxStore) {
        if item.entryID != nil {
            self = .added
        } else if item.isNotTransaction {
            self = .notTransaction
        } else if inbox.isOwnTransferSide(item) {
            self = .betweenOwnAccounts
        } else if item.pairedID != nil {
            self = .cameTwice
        } else {
            self = .dismissed
        }
    }

    var name: Text {
        switch self {
        case .added: Text("Added")
        case .dismissed: Text("Dismissed")
        case .betweenOwnAccounts: Text("Between Your Accounts")
        case .cameTwice: Text("Came Twice")
        case .notTransaction: Text("Not a Transaction")
        }
    }
}

/// What the money was, what became of it, and when.
private struct HistoryRow: View {
    let item: CapturedTransaction
    let outcome: Outcome

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CapturedTitle(item: item)
                    .lineLimit(2)
                Group {
                    let date = item.handledAt ?? item.capturedAt
                    switch outcome {
                    case .added: Text("Added \(date, format: .dateTime.day().month().hour().minute())")
                    case .dismissed: Text("Dismissed \(date, format: .dateTime.day().month().hour().minute())")
                    case .betweenOwnAccounts: Text("Between your accounts, \(date, format: .dateTime.day().month().hour().minute())")
                    case .cameTwice: Text("Came twice, \(date, format: .dateTime.day().month().hour().minute())")
                    case .notTransaction: Text("Not a transaction, \(date, format: .dateTime.day().month().hour().minute())")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            CapturedAmount(item: item)
        }
    }
}

/// One item from the history: what was read, the message as it came, and a button to put it
/// back in the inbox if it wasn't added.
private struct HistoryItemView: View {
    let item: CapturedTransaction

    @Environment(InboxStore.self) private var inbox
    @Environment(\.dismiss) private var dismiss
    @State private var putBackFailed = false

    var body: some View {
        let outcome = Outcome(item, in: inbox)
        Form {
            Section {
                LabeledContent("Received") {
                    Text(item.capturedAt, format: .dateTime.day().month().year().hour().minute())
                }
                if let handledAt = item.handledAt {
                    LabeledContent {
                        Text(handledAt, format: .dateTime.day().month().year().hour().minute())
                    } label: {
                        outcome.name
                    }
                }
                LabeledContent("Amount") {
                    CapturedAmount(item: item)
                }
            }
            if !item.text.isEmpty {
                Section {
                    Text(verbatim: item.text)
                        .font(.callout)
                        .textSelection(.enabled)
                } header: {
                    switch item.source {
                    case .bankMessage: Text("Bank Message")
                    // What Wallet passed as the amount, when it couldn't be read.
                    case .payment: Text("Amount from Wallet")
                    case .screenshot: Text("Text from the Screenshot")
                    case .file: Text("From the File")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if outcome != .added, item.handledAt != nil {
                VStack(spacing: 8) {
                    Button("Put Back in the Inbox") {
                        do {
                            try inbox.putBack(id: item.id)
                            dismiss()
                        } catch {
                            putBackFailed = true
                        }
                    }
                    .buttonStyle(.bordered)
                    switch outcome {
                    case .betweenOwnAccounts:
                        Text("It and the other side were left out, since a transfer between your accounts nets to zero. Putting it back puts both back, to add as an expense and income.")
                    case .cameTwice:
                        Text("It was left out, since the same transaction came in another message.")
                    case .notTransaction:
                        Text("It was left out, since it isn’t about money that moved, such as an ad or a one-time code. Put it back to read it again or add it yourself.")
                    default:
                        EmptyView()
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            }
        }
        .alert("Couldn’t Put It Back", isPresented: $putBackFailed) {
            Button("OK") {}
        } message: {
            Text("Riêng Tư couldn’t put it back in the inbox. Try again.")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                CapturedTitle(item: item)
                    .font(.headline)
                    .lineLimit(1)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        InboxHistoryView()
    }
    .previewEnvironment()
}
