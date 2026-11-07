import RiengtuKit
import SwiftUI

/// An inbox item that isn't read, or was read without an amount, opened from the Inbox tab: how
/// its reading is going, and the message as it came, so the person can see what it is. They can
/// have it read again, adding what the message doesn't say clearly, add it themselves, or
/// dismiss it, such as when it isn't a transaction at all.
struct CapturedMessageView: View {
    let id: CapturedTransaction.ID
    /// Opens the editor for the item, once this sheet has closed.
    let addsItYourself: (CapturedTransaction) -> Void

    @Environment(InboxStore.self) private var inbox
    @Environment(BackgroundReading.self) private var backgroundReading
    @Environment(\.dismiss) private var dismiss
    @State private var hint = ""
    @FocusState private var isEditingHint: Bool
    @State private var saveFailed = false

    /// The item as it is now: it may be read, or left out as one of a pair, meanwhile.
    private var item: CapturedTransaction? {
        inbox.items.first { $0.id == id && $0.isPending }
    }

    var body: some View {
        let item = item
        NavigationStack {
            Form {
                if let item {
                    Section {
                        status(of: item)
                    }
                    message(of: item)
                    // A payment's amount comes from Wallet, not read from a message.
                    if item.source != .payment {
                        readAgainSection(item)
                    }
                    Section {
                        Button {
                            addsItYourself(item)
                            dismiss()
                        } label: {
                            if item.wasRead { Text("Check and Add") } else { Text("Add It Yourself") }
                        }
                        Button("Dismiss", role: .destructive) {
                            do {
                                try inbox.dismiss(id: item.id)
                                dismiss()
                            } catch {
                                saveFailed = true
                            }
                        }
                    }
                }
            }
            .animation(.default, value: item?.wasRead)
            .navigationTitle(title(of: item))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn’t Save", isPresented: $saveFailed) {
                Button("OK") {}
            } message: {
                Text("Riengtu couldn’t save your change. Try again.")
            }
        }
        .privacyShield()
        .onAppear {
            hint = item?.hint ?? ""
        }
        .onChange(of: item == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    /// Where reading has got with it.
    @ViewBuilder private func status(of item: CapturedTransaction) -> some View {
        if item.wasRead {
            if item.amount == nil {
                Label("Read, but no amount was found.", systemImage: "questionmark.circle")
            } else {
                Label("Read, and ready to check.", systemImage: "checkmark.circle.fill")
            }
        } else if item.id == inbox.readingItemID {
            HStack(spacing: 12) {
                ProgressView()
                Text("Apple Intelligence is reading it…")
            }
        } else if inbox.isReading {
            Label("Waiting to be read.", systemImage: "clock")
        } else if inbox.modelDidNotAnswer {
            Label("Apple Intelligence didn’t answer in time.", systemImage: "exclamationmark.triangle")
        } else if inbox.isWaitingForModel {
            Label("Apple Intelligence can’t read it just now.", systemImage: "pause.circle")
        } else {
            Label("Not read yet.", systemImage: "envelope")
        }
    }

    /// What came, word for word, and when.
    @ViewBuilder private func message(of item: CapturedTransaction) -> some View {
        Section {
            if item.text.isEmpty {
                // A payment from Wallet, whose amount was read as it came.
                HStack {
                    CapturedTitle(item: item)
                    Spacer(minLength: 8)
                    CapturedAmount(item: item)
                }
            } else {
                Text(verbatim: item.text)
                    .textSelection(.enabled)
            }
        } header: {
            switch item.source {
            case .bankMessage: Text("Message Received")
            case .payment: Text("Amount from Wallet")
            case .screenshot: Text("Text from the Screenshot")
            case .file: Text("From the File")
            }
        } footer: {
            Text("Received \(item.capturedAt, format: .dateTime.day().month().hour().minute())")
        }
    }

    /// Reads it again, first, as a transaction, with what the person adds, which Apple
    /// Intelligence reads with the message.
    @ViewBuilder private func readAgainSection(_ item: CapturedTransaction) -> some View {
        let usesModel = ExpenseTagger.availability == .available
        Section {
            if usesModel {
                TextField("Such as what it was for, or the amount", text: $hint, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isEditingHint)
            }
            Button("Read Again", systemImage: "arrow.clockwise") {
                isEditingHint = false
                do {
                    try inbox.readAgain(id: item.id, hint: usesModel ? hint : "")
                    backgroundReading.start(inbox)
                } catch {
                    saveFailed = true
                }
            }
        } header: {
            if usesModel { Text("Help Read It") }
        } footer: {
            if usesModel {
                Text("Apple Intelligence reads what you add with the message, on this device.")
            }
        }
    }

    private func title(of item: CapturedTransaction?) -> Text {
        switch item?.source {
        case .bankMessage, nil: Text("Bank Message")
        case .payment: Text("Payment")
        case .screenshot: Text("From a Screenshot")
        case .file: Text("From a File")
        }
    }
}

#Preview {
    let item = CapturedTransaction(
        source: .bankMessage, capturedAt: .now, date: .now, amount: nil, currencyCode: nil, description: "",
        text: "Techcombank\nTK 1234567890 GD tai SHOPEE luc 10:20 06/11/2026"
    )
    CapturedMessageView(id: item.id) { _ in }
        .previewEnvironment(inbox: [item])
}
