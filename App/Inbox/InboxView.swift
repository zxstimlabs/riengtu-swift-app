import PhotosUI
import RiengtuKit
import SwiftUI
import UniformTypeIdentifiers

/// What waits to be added to the ledger: bank notifications, emails and Apple Pay payments that
/// Shortcuts forwards, and transactions from screenshots of a bank app's history. Apple
/// Intelligence reads them (`ReadingView`), then the person checks them and taps Add All, or
/// opens one to change it.
struct InboxView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(InboxStore.self) private var inbox
    @Environment(BackgroundReading.self) private var backgroundReading
    @State private var editing: CapturedTransaction?
    /// One not read yet, or read without an amount, to see the message as it came and read it
    /// again (`CapturedMessageView`), and the one to open in the editor once that closes.
    @State private var viewing: CapturedTransaction?
    @State private var editsAfterViewing: CapturedTransaction?
    @State private var saveFailed = false
    @State private var showsSetup = false
    @State private var picksFiles = false
    @State private var picksScreenshots = false
    @State private var screenshots: [PhotosPickerItem] = []
    @State private var isImporting = false
    /// Reading what the person picked, which they can cancel.
    @State private var importTask: Task<Void, Never>?
    @State private var importResult: InboxStore.ImportResult?
    @State private var importFailed = false
    @State private var showsReading = false

    var body: some View {
        let pending = inbox.pending
        List {
            if inbox.isReading || (inbox.unreadCount > 0 && ExpenseTagger.availability == .available) {
                Section {
                    // This reading's, or what waits to be read.
                    let done = inbox.isReading ? inbox.readCount : 0
                    ReadingCard(done: done, total: done + inbox.unreadCount) { showsReading = true }
                }
            }
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { item in
                        Button {
                            // A payment without an amount is typed in: Wallet didn't pass it.
                            if item.wasRead, item.amount != nil || item.source == .payment {
                                editing = item
                            } else {
                                viewing = item
                            }
                        } label: {
                            CapturedRow(item: item, isReading: inbox.isReading, isCurrent: item.id == inbox.readingItemID)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Dismiss", systemImage: "xmark", role: .destructive) {
                                dismiss(item)
                            }
                        }
                    }
                } footer: {
                    if inbox.isReading {
                        Text("Reading new messages…")
                    } else if pending.contains(where: \.isTransfer) {
                        Text("Add All adds what’s ready. Tap a transfer to choose its accounts, or swipe to dismiss one.")
                    } else {
                        Text("Check them, then tap Add All, or tap one to change it. Swipe to dismiss one.")
                    }
                }
            }
        }
        .overlay {
            if pending.isEmpty, !isImporting {
                ContentUnavailableView {
                    Label("Nothing Waiting", systemImage: "tray")
                } description: {
                    Text("Your bank’s notifications and emails, and your Apple Pay payments, wait here once Shortcuts sends them, for you to check and add. You can add past transactions from screenshots too.")
                } actions: {
                    addMenu {
                        Text("Add from Photos or Files")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    Button("Set Up Shortcuts") { showsSetup = true }
                }
            }
        }
        .overlay {
            if isImporting {
                VStack(spacing: 16) {
                    ProgressView("Reading screenshots…")
                    Button("Cancel", role: .cancel) { importTask?.cancel() }
                        .buttonStyle(.bordered)
                }
                .padding(24)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .navigationTitle("Inbox")
        .settingsButton()
        .toolbar {
            if pending.contains(where: \.isReadyToAdd) {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add All", action: addAll)
                        .fontWeight(.semibold)
                        .disabled(inbox.isReading)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                addMenu {
                    Label("Add", systemImage: "plus")
                }
                .disabled(isImporting)
            }
        }
        .navigationDestination(isPresented: $showsSetup) { CaptureHelpView() }
        .photosPicker(isPresented: $picksScreenshots, selection: $screenshots, maxSelectionCount: 30, matching: .images)
        .fileImporter(isPresented: $picksFiles, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            importTask = Task { await importFiles(urls) }
        }
        .onChange(of: screenshots) { _, items in
            guard !items.isEmpty else { return }
            screenshots = []
            importTask = Task { await importScreenshots(items) }
        }
        .alert(
            importResult?.added == 0 ? Text("No New Transactions") : Text("Added to the Inbox"),
            isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } }),
            presenting: importResult
        ) { _ in
            Button("OK") {}
        } message: { result in
            if result.added > 0, result.alreadyThere > 0 {
                Text("Added \(result.added) transactions to the inbox.") + Text(verbatim: " ") + Text("\(result.alreadyThere) were already there.")
            } else if result.added > 0 {
                Text("Added \(result.added) transactions to the inbox.")
            } else if result.alreadyThere > 0 {
                Text("They were all in the inbox or its history already.")
            } else {
                Text("Riêng Tư found no transactions in them. Choose screenshots of your bank app’s transaction history, with each transaction whole, or a file of transactions, such as a bank’s export.")
            }
        }
        .alert("Couldn’t Read Them", isPresented: $importFailed) {
            Button("OK") {}
        } message: {
            Text("Riêng Tư couldn’t read what you chose. Try again.")
        }
        .sheet(isPresented: $showsReading) {
            ReadingView()
        }
        .sheet(item: $editing) { item in
            EntryEditor(capturing: item, currencyCode: preferredCurrencyCode)
        }
        .sheet(item: $viewing, onDismiss: {
            guard let item = editsAfterViewing else { return }
            editsAfterViewing = nil
            editing = item
        }) { item in
            CapturedMessageView(id: item.id) { editsAfterViewing = $0 }
        }
        .alert("Couldn’t Save", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
        }
    }

    /// What can be added to the inbox: screenshots and photos of a bank app's history, and files
    /// such as a bank's or another app's export.
    private func addMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Button("From Photos", systemImage: "photo.on.rectangle.angled") { picksScreenshots = true }
            Button("From Files", systemImage: "doc") { picksFiles = true }
        } label: {
            label()
        }
    }

    /// Tables, JSON, text, and images of a bank app's history.
    private static let fileTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .json, .plainText, .text, .image]

    private var preferredCurrencyCode: String {
        store.ledger.preferredCurrencyCode(fallback: Currencies.code(for: .autoupdatingCurrent))
    }

    private func dismiss(_ item: CapturedTransaction) {
        do {
            try inbox.dismiss(id: item.id)
        } catch {
            saveFailed = true
        }
    }

    /// Reads screenshots of a bank app's history with Vision, on the device, and puts the
    /// transactions on them in the inbox, where they're read as forwarded messages are.
    private func importScreenshots(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }
        do {
            var found: [ScreenshotText.Transaction] = []
            for item in items {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let (lines, takenAt) = try await ScreenshotReader.read(data)
                found += ScreenshotText.transactions(in: lines, takenAt: takenAt ?? .now, timeZone: .current)
            }
            try Task.checkCancellation()
            importResult = try inbox.importScreenshots(found)
            // The person asked for them, so reading starts.
            if inbox.unreadCount > 0 { backgroundReading.start(inbox) }
        } catch is CancellationError {
            // Nothing's added.
        } catch {
            importFailed = true
        }
    }

    /// Reads files the person picked, one transaction for each row, object or paragraph
    /// (`FileText`), or for an image, each transaction on it, as a screenshot's, and puts them in
    /// the inbox, where they're read as forwarded messages are.
    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        do {
            var messages: [String] = []
            var found: [ScreenshotText.Transaction] = []
            for url in urls {
                try Task.checkCancellation()
                let isAllowed = url.startAccessingSecurityScopedResource()
                defer { if isAllowed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                    let (lines, takenAt) = try await ScreenshotReader.read(data)
                    found += ScreenshotText.transactions(in: lines, takenAt: takenAt ?? .now, timeZone: .current)
                } else {
                    messages += FileText.messages(in: data, fileExtension: url.pathExtension)
                }
            }
            try Task.checkCancellation()
            let fromFiles = try inbox.importFile(messages)
            let fromImages = try inbox.importScreenshots(found)
            importResult = InboxStore.ImportResult(
                added: fromFiles.added + fromImages.added, alreadyThere: fromFiles.alreadyThere + fromImages.alreadyThere
            )
            if inbox.unreadCount > 0 { backgroundReading.start(inbox) }
        } catch is CancellationError {
            // Nothing's added.
        } catch {
            importFailed = true
        }
    }

    /// Adds each item that's ready as its editor would open it (`Ledger.entry(adding:)`), and
    /// moves it to the inbox's history.
    private func addAll() {
        withAnimation {
            for item in inbox.pending where item.isReadyToAdd {
                guard let entry = store.ledger.entry(adding: item, currencyCode: preferredCurrencyCode) else { continue }
                do {
                    try store.save(entry)
                } catch {
                    saveFailed = true
                    return
                }
                // The entry is saved either way. If this fails, the item stays in the inbox.
                try? inbox.markAdded(id: item.id, as: entry.id)
            }
        }
    }
}

/// A transaction waiting in the inbox: its category once it's been read, what it was for, when,
/// and how much, with a plus for money that came in.
private struct CapturedRow: View {
    let item: CapturedTransaction
    let isReading: Bool
    /// Whether it's the one being read now.
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            CapturedIcon(item: item)
            VStack(alignment: .leading, spacing: 2) {
                CapturedTitle(item: item)
                    .lineLimit(2)
                Text(item.date, format: .dateTime.day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !item.wasRead, isCurrent {
                ProgressView()
            } else if !item.wasRead, isReading {
                Text("Waiting")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                CapturedAmount(item: item)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview("English") {
    NavigationStack {
        InboxView()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        InboxView()
    }
    .previewEnvironment(inbox: [])
}
