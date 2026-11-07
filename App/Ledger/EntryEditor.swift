import PhotosUI
import RiengtuKit
import SwiftUI

/// Adds an entry, or edits one, in a sheet: an expense, income, or a transfer between the
/// person's own assets.
///
/// An expense can come from one of the person's accounts, and income go into one, which changes
/// its balance. A transfer takes from one asset and adds to another, by a quantity or a weight
/// for shares, fund units, coins and gold.
///
/// Where Apple Intelligence is available, the model on the device reads an expense's note as
/// it's typed and suggests tags, and a category until the person picks one.
///
/// An expense or income can have a receipt, scanned or chosen from Photos and read on the device
/// (`ReceiptReader`), which fills in what's still empty. The photo isn't kept.
struct EntryEditor: View {
    enum Mode: CaseIterable {
        case expense, income, transfer
    }

    /// The entry being edited, or `nil` for a new one. Never an adjustment: those are edited in
    /// the asset's editor.
    private let original: Entry?
    /// The transaction from the inbox this entry starts from, which leaves the inbox once it's
    /// saved.
    private let captured: CapturedTransaction?

    @Environment(LedgerStore.self) private var store
    @Environment(InboxStore.self) private var inbox
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var expenseCategory: ExpenseCategory
    @State private var incomeCategory: IncomeCategory
    /// The account an expense came from, or income went to.
    @State private var account: Asset.ID?
    @State private var fromAsset: Asset.ID?
    @State private var toAsset: Asset.ID?
    /// How many shares, units or coins, or how much gold, left `fromAsset`, when it isn't valued
    /// by an amount.
    @State private var fromChangeText: String
    /// What `toAsset` gained when that isn't the amount: shares, units, coins or gold, or money in
    /// its own currency.
    @State private var toChangeText: String
    @State private var date: Date
    /// Who the money came from or went to. Not for a transfer, between the person's own assets.
    @State private var party: String
    @State private var note: String
    @State private var tags: [String]
    @State private var suggestion: TagSuggestion?
    /// Whether the person picked the category, so a suggestion doesn't change it.
    @State private var categoryWasPicked: Bool
    @State private var categoryWasSuggested = false
    /// Whether the suggested category came from the receipt, rather than the note.
    @State private var categoryIsFromReceipt = false
    /// Whether the person set the date, or it came from the inbox, so a receipt doesn't change it.
    @State private var dateWasPicked: Bool
    @State private var receipt: Receipt?
    @State private var isReadingReceipt = false
    @State private var receiptTask: Task<Void, Never>?
    /// The receipt's photos, in memory while the editor is open, to read again without taking
    /// them again. Never saved: they're let go when the editor closes.
    @State private var receiptPhotos: [Data] = []
    /// Whether reading the receipt was stopped, or found nothing, so the person can try again.
    @State private var receiptWasStopped = false
    @State private var scansReceipt = false
    @State private var picksReceiptPhoto = false
    @State private var receiptPhoto: PhotosPickerItem?
    @State private var showsReceipt = false
    @State private var receiptFailed = false
    @State private var saveFailed = false
    @State private var savedCount = 0
    @FocusState private var amountIsFocused: Bool
    @AppStorage(SettingsView.suggestsTagsKey) private var suggestsTags = true

    init(editing entry: Entry?, currencyCode defaultCurrencyCode: String) {
        self.init(entry: entry, captured: nil, currencyCode: defaultCurrencyCode)
    }

    /// A new entry from the inbox, as it was read: a transfer, income, or an expense, in the
    /// category Apple Intelligence chose.
    init(capturing item: CapturedTransaction, currencyCode defaultCurrencyCode: String) {
        self.init(entry: nil, captured: item, currencyCode: defaultCurrencyCode)
    }

    private init(entry: Entry?, captured: CapturedTransaction?, currencyCode defaultCurrencyCode: String) {
        original = entry
        self.captured = captured
        let currencyCode = entry?.currencyCode ?? captured?.currencyCode ?? defaultCurrencyCode
        let amount = entry?.amount ?? captured?.amount
        _currencyCode = State(initialValue: currencyCode)
        _amountText = State(initialValue: amount.map {
            NumberField.text(for: $0, fractionDigits: Currencies.fractionDigits(for: currencyCode))
        } ?? "")
        _date = State(initialValue: entry?.date ?? captured?.date ?? .now)
        _party = State(initialValue: entry?.party ?? captured?.party ?? "")
        _note = State(initialValue: entry?.note ?? captured?.description ?? "")
        _tags = State(initialValue: entry?.tags ?? [])
        _receipt = State(initialValue: entry?.receipt)
        _categoryWasPicked = State(initialValue: entry != nil)
        _dateWasPicked = State(initialValue: entry != nil || captured != nil)

        var mode = captured?.isTransfer == true ? Mode.transfer : captured?.isMoneyIn == true ? .income : .expense
        // From the inbox, a category that wasn't chosen is "other", as Add All saves it. Money
        // that came in from the inbox is often someone paying back, not pay.
        var expenseCategory = captured.map { $0.expenseCategory ?? .other } ?? .food
        var incomeCategory = captured.map { $0.incomeCategory ?? .other } ?? .salary
        var account: Asset.ID?
        var from: Entry.Leg?, to: Entry.Leg?
        switch entry?.kind {
        case .expense(let category, let paidFrom):
            mode = .expense
            expenseCategory = category
            account = paidFrom
        case .income(let category, let paidInto):
            mode = .income
            incomeCategory = category
            account = paidInto
        case .transfer(let fromLeg, let toLeg):
            mode = .transfer
            from = fromLeg
            to = toLeg
        case .adjustment, nil:
            break
        }
        _mode = State(initialValue: mode)
        _expenseCategory = State(initialValue: expenseCategory)
        _incomeCategory = State(initialValue: incomeCategory)
        _account = State(initialValue: account)
        _fromAsset = State(initialValue: from?.asset)
        _toAsset = State(initialValue: to?.asset)
        // The changes' digits depend on the assets, which aren't known here. `onAppear` fills
        // them in.
        _fromChangeText = State(initialValue: "")
        _toChangeText = State(initialValue: "")
    }

    // MARK: Values

    /// The bank's message or payment the entry came from: the one being added, or for an entry
    /// added from the inbox, the one in the inbox's history, until that's deleted.
    private var message: CapturedTransaction? {
        captured ?? original.flatMap { inbox.item(forEntry: $0.id) }
    }

    private var amount: Decimal? {
        NumberField.number(in: amountText).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The accounts an expense can come from and income go into: cash, bank accounts, e-wallets
    /// and savings deposits.
    private var accounts: [Asset] {
        store.ledger.assetSections().first { $0.group == .money }?.assets ?? []
    }

    private func asset(_ id: Asset.ID?) -> Asset? {
        id.flatMap(store.ledger.asset(id:))
    }

    /// What a transfer's side changes by, in its own terms, when that isn't the amount.
    private enum ChangeField {
        /// Shares, units or coins, or a weight of gold.
        case quantity(Asset)
        /// Money in the asset's currency, which isn't the amount's.
        case money(Asset)
    }

    private var fromChangeField: ChangeField? {
        guard let from = asset(fromAsset), from.kind.valuation != .amount else { return nil }
        return .quantity(from)
    }

    private var toChangeField: ChangeField? {
        guard let to = asset(toAsset) else { return nil }
        if to.kind.valuation != .amount { return .quantity(to) }
        return to.currencyCode == currencyCode ? nil : .money(to)
    }

    private static func positive(_ text: String) -> Decimal? {
        NumberField.number(in: text).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The entry's kind as filled in, or `nil` while something it needs is missing.
    private var kind: Entry.Kind? {
        switch mode {
        case .expense:
            return .expense(expenseCategory, account: account)
        case .income:
            return .income(incomeCategory, account: account)
        case .transfer:
            guard let amount, let fromAsset, let toAsset, fromAsset != toAsset else { return nil }
            var fromChange = amount, toChange = amount
            if fromChangeField != nil {
                guard let change = Self.positive(fromChangeText) else { return nil }
                fromChange = change
            }
            if toChangeField != nil {
                guard let change = Self.positive(toChangeText) else { return nil }
                toChange = change
            }
            return .transfer(
                from: Entry.Leg(asset: fromAsset, change: fromChange),
                to: Entry.Leg(asset: toAsset, change: toChange)
            )
        }
    }

    // MARK: Views

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $mode) {
                        Text("Expense").tag(Mode.expense)
                        Text("Income").tag(Mode.income)
                        Text("Transfer").tag(Mode.transfer)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // One not read, being filled in by hand: what it says, to copy from, first.
                if let message, !message.wasRead, !message.text.isEmpty {
                    Section {
                        messageText(message)
                    } header: {
                        messageLabel(message)
                    }
                }

                amountSection

                switch mode {
                case .expense, .income:
                    categorySection
                    Section {
                        accountPicker
                        // When, who with, then what for.
                        DatePicker("Date", selection: pickedDate, displayedComponents: [.date, .hourAndMinute])
                        if mode == .income {
                            TextField("Received From", text: $party)
                        } else {
                            TextField("Paid To", text: $party)
                        }
                        TextField("Note", text: $note, axis: .vertical)
                    }
                    tagsSection
                    receiptSection
                case .transfer:
                    transferSections
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        TextField("Note", text: $note, axis: .vertical)
                    }
                }

                if let message, message.wasRead, !message.text.isEmpty {
                    Section {
                        DisclosureGroup {
                            messageText(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } label: {
                            messageLabel(message)
                        }
                    }
                }

                if let original {
                    Section {
                        Button("Delete Transaction", role: .destructive) {
                            delete(original)
                        }
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(amount == nil || kind == nil)
                }
            }
            .onAppear(perform: fillIn)
            .onChange(of: account) { _, account in
                // An account's money is in its currency.
                if let asset = asset(account) { currencyCode = asset.currencyCode }
            }
            .onChange(of: fromAsset) { _, from in
                if let asset = asset(from) { currencyCode = asset.currencyCode }
            }
            .onChange(of: currencyCode) { _, code in
                if mode != .transfer, let asset = asset(account), asset.currencyCode != code { account = nil }
            }
            .onChange(of: mode) { _, mode in
                if mode == .transfer, let from = asset(fromAsset) {
                    currencyCode = from.currencyCode
                } else if mode != .transfer, let asset = asset(account) {
                    currencyCode = asset.currencyCode
                }
            }
            .task(id: mode == .expense ? note : nil) {
                await suggest()
            }
            .alert("Couldn’t Save", isPresented: $saveFailed) {
                Button("OK") {}
            } message: {
                Text("Riengtu couldn’t save your change. Try again.")
            }
            .alert("Couldn’t Read the Receipt", isPresented: $receiptFailed) {
                Button("OK") {}
            } message: {
                Text("Riêng Tư found nothing to read on it. Try again with the whole receipt in the photo, in good light.")
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $scansReceipt) {
                ReceiptScanner { photos in
                    readReceipt(photos)
                }
                .ignoresSafeArea()
                .privacyShield()
            }
            #endif
            .photosPicker(isPresented: $picksReceiptPhoto, selection: $receiptPhoto, matching: .images)
            .onChange(of: receiptPhoto) { _, item in
                guard let item else { return }
                receiptPhoto = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        receiptFailed = true
                        return
                    }
                    readReceipt([data])
                }
            }
            .onDisappear {
                receiptTask?.cancel()
            }
            .sheet(isPresented: $showsReceipt) {
                if let receipt {
                    ReceiptSheet(receipt: receipt)
                }
            }
            .sensoryFeedback(.success, trigger: savedCount)
        }
        .privacyShield()
    }

    private var title: LocalizedStringKey {
        switch (mode, original == nil) {
        case (.expense, true): "New Expense"
        case (.expense, false): "Edit Expense"
        case (.income, true): "New Income"
        case (.income, false): "Edit Income"
        case (.transfer, true): "New Transfer"
        case (.transfer, false): "Edit Transfer"
        }
    }

    /// The bank's message or payment as it came.
    private func messageText(_ message: CapturedTransaction) -> some View {
        Text(verbatim: message.text)
            .textSelection(.enabled)
    }

    @ViewBuilder private func messageLabel(_ message: CapturedTransaction) -> some View {
        switch message.source {
        case .bankMessage: Text("Bank Message")
        // What Wallet passed as the amount, when it couldn't be read.
        case .payment: Text("Amount from Wallet")
        case .screenshot: Text("Text from the Screenshot")
        case .file: Text("From the File")
        }
    }

    private var amountSection: some View {
        Section {
            AmountWithSymbol(code: currencyCode) {
                NumberField(title: Text("Amount"), text: $amountText, fractionDigits: fractionDigits)
                    .focused($amountIsFocused)
            }
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .contentShape(.rect)
            .onTapGesture { amountIsFocused = true }

            // An account's or an asset's money is in its currency.
            if mode == .transfer ? fromAsset == nil : asset(account) == nil {
                NavigationLink {
                    CurrencyPicker(selection: $currencyCode, suggested: suggestedCurrencies)
                } label: {
                    LabeledContent("Currency", value: currencyCode)
                }
            }
        }
    }

    private var categorySection: some View {
        Section {
            if mode == .income {
                CategoryGrid(selection: Binding(
                    get: { incomeCategory },
                    set: { incomeCategory = $0 }
                ))
            } else {
                CategoryGrid(selection: Binding(
                    get: { expenseCategory },
                    set: { picked in
                        expenseCategory = picked
                        categoryWasPicked = true
                        categoryWasSuggested = false
                    }
                ))
            }
        } header: {
            Text("Category")
        } footer: {
            if mode == .expense, categoryWasSuggested {
                if categoryIsFromReceipt {
                    Label("Picked from the receipt by Apple Intelligence.", systemImage: "apple.intelligence")
                } else {
                    Label("Picked from your note by Apple Intelligence.", systemImage: "apple.intelligence")
                }
            }
        }
    }

    @ViewBuilder private var accountPicker: some View {
        let accounts = accounts
        if !accounts.isEmpty {
            Picker(selection: $account) {
                Text("None").tag(Asset.ID?.none)
                ForEach(accounts) { asset in
                    AssetLabel(asset: asset).tag(Optional(asset.id))
                }
            } label: {
                Text(mode == .income ? "Received In" : "Paid From")
            }
        }
    }

    /// The date, which a receipt doesn't change once the person has set it.
    private var pickedDate: Binding<Date> {
        Binding(get: { date }, set: { date = $0; dateWasPicked = true })
    }

    /// The receipt: to add, being read, or as it was read, to open whole.
    @ViewBuilder private var receiptSection: some View {
        Section {
            if isReadingReceipt {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading the receipt…")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    // When it seems stuck.
                    Button("Stop", action: stopReadingReceipt)
                        .buttonStyle(.borderless)
                }
            } else if receipt == nil, receiptWasStopped, !receiptPhotos.isEmpty {
                Text("The receipt wasn’t read.")
                    .foregroundStyle(.secondary)
                Button("Try Again", systemImage: "arrow.clockwise") { readReceipt(receiptPhotos) }
                if ExpenseTagger.availability == .available {
                    Button("Read Without Apple Intelligence") { readReceipt(receiptPhotos, usingModel: false) }
                }
                addReceiptMenu(Label("Use Another Photo", systemImage: "camera"))
            } else if let receipt {
                Button {
                    showsReceipt = true
                } label: {
                    ReceiptSummary(receipt: receipt)
                }
                .foregroundStyle(.primary)
                if let total = receipt.total, let amount, total != amount, receipt.currencyCode == currencyCode {
                    HStack {
                        Text("The receipt’s total is \(total.formatted(.money(code: receipt.currencyCode))).")
                            .font(.subheadline)
                        Spacer(minLength: 8)
                        Button("Use It") {
                            amountText = NumberField.text(for: total, fractionDigits: fractionDigits)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                // Not read well: again, from the photos taken in this editor.
                if !receiptPhotos.isEmpty {
                    Button("Read Again", systemImage: "arrow.clockwise") { readReceipt(receiptPhotos) }
                }
                Button("Remove Receipt", role: .destructive) {
                    withAnimation {
                        self.receipt = nil
                        receiptPhotos = []
                        receiptWasStopped = false
                    }
                }
            } else {
                addReceiptMenu(Label("Add Receipt", systemImage: "receipt"))
            }
        } header: {
            Text("Receipt")
        } footer: {
            if receipt == nil {
                Text("Riêng Tư reads the receipt on this device and doesn’t keep the photo.")
            }
        }
    }

    /// A photo of a receipt taken now, or one from the library.
    private func addReceiptMenu(_ label: Label<Text, Image>) -> some View {
        Menu {
            #if os(iOS)
            if ReceiptScanner.isSupported {
                Button("Take Photo", systemImage: "camera") { scansReceipt = true }
            }
            #endif
            Button("Choose from Photos", systemImage: "photo.on.rectangle") { picksReceiptPhoto = true }
        } label: {
            label
        }
    }

    private var tagsSection: some View {
        Section {
            TagPicker(selection: $tags, tags: store.ledger.tags, suggestion: mode == .expense ? suggestion : nil)
        } header: {
            Text("Tags")
        } footer: {
            if mode == .expense, let suggestion, !suggestion.tags.allSatisfy(tags.contains) || suggestion.newTag != nil {
                Label("Suggested by Apple Intelligence on this device. Tap to add.", systemImage: "apple.intelligence")
            }
        }
    }

    @ViewBuilder private var transferSections: some View {
        let sections = store.ledger.assetSections()
        Section {
            AssetPicker(title: Text("From"), selection: $fromAsset, sections: sections)
            if let field = fromChangeField {
                changeRow(field, text: $fromChangeText)
            }
        } footer: {
            if sections.isEmpty {
                Text("Add your accounts and other assets in Assets to move money between them.")
            }
        }
        Section {
            AssetPicker(title: Text("To"), selection: $toAsset, sections: sections)
            if let field = toChangeField {
                changeRow(field, text: $toChangeText)
            }
        } footer: {
            if fromAsset != nil, fromAsset == toAsset {
                Text("Choose two different assets.")
            }
        }
    }

    /// A field for a quantity, a weight, or money in another currency.
    @ViewBuilder private func changeRow(_ field: ChangeField, text: Binding<String>) -> some View {
        switch field {
        case .quantity(let asset):
            LabeledContent {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    NumberField(title: quantityTitle(asset), text: text, fractionDigits: asset.kind.quantityFractionDigits)
                        .multilineTextAlignment(.trailing)
                    if case .gold(_, let unit, _, _) = asset.value {
                        Text(unit.name)
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
            } label: {
                quantityTitle(asset)
            }
        case .money(let asset):
            LabeledContent {
                AmountWithSymbol(code: asset.currencyCode, spacing: 4) {
                    NumberField(title: Text("Received"), text: text, fractionDigits: Currencies.fractionDigits(for: asset.currencyCode))
                        .multilineTextAlignment(.trailing)
                }
                .monospacedDigit()
            } label: {
                Text("Received")
            }
        }
    }

    private func quantityTitle(_ asset: Asset) -> Text {
        asset.kind.valuation == .gold ? Text("Weight") : Text(asset.kind.quantityName)
    }

    private var fractionDigits: Int {
        Currencies.fractionDigits(for: currencyCode)
    }

    private var suggestedCurrencies: [String] {
        let recent = store.ledger.recentCurrencyCodes
        return recent.isEmpty ? [Currencies.code(for: NumberField.locale)] : recent
    }

    // MARK: Actions

    /// Fills in what needs the ledger: a new expense's or income's account, and a transfer's
    /// quantities.
    private func fillIn() {
        if original == nil, captured?.amount == nil { amountIsFocused = true }
        if original == nil, mode != .transfer,
           let last = asset(store.ledger.lastAccount(for: mode == .income ? .moneyIn : .moneyOut)),
           last.currencyCode == currencyCode {
            account = last.id
        }
        guard case .transfer(let from, let to)? = original?.kind else { return }
        if let from, fromChangeField != nil, let asset = asset(from.asset) {
            fromChangeText = NumberField.text(for: from.change, fractionDigits: asset.kind.quantityFractionDigits)
        }
        if let to, let field = toChangeField {
            switch field {
            case .quantity(let asset):
                toChangeText = NumberField.text(for: to.change, fractionDigits: asset.kind.quantityFractionDigits)
            case .money(let asset):
                toChangeText = NumberField.text(for: to.change, fractionDigits: Currencies.fractionDigits(for: asset.currencyCode))
            }
        }
    }

    /// Asks the model about an expense's note, once the person stops typing for a moment.
    /// Typing again cancels the question.
    private func suggest() async {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .expense, suggestsTags, note.count >= 2, note != original?.note,
              ExpenseTagger.availability == .available
        else {
            withAnimation { suggestion = nil }
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(600))
            let result = try await ExpenseTagger.suggest(
                note: note, amount: amount, currencyCode: currencyCode, tags: store.ledger.tags
            )
            try Task.checkCancellation()
            withAnimation {
                suggestion = result
                if !categoryWasPicked, let suggested = result.category {
                    expenseCategory = suggested
                    categoryWasSuggested = true
                    categoryIsFromReceipt = false
                }
            }
        } catch {
            // Cancelled by more typing, or the model couldn't answer, such as for a language it
            // doesn't support. Either way, no suggestion.
        }
    }

    /// Reads a receipt's photos on the device, with Apple Intelligence unless the person chose
    /// otherwise. The photos stay in memory to read again until the editor closes.
    private func readReceipt(_ photos: [Data], usingModel: Bool = true) {
        guard !photos.isEmpty else { return }
        receiptTask?.cancel()
        receiptPhotos = photos
        receiptWasStopped = false
        isReadingReceipt = true
        receiptTask = Task {
            do {
                let rows = try await ReceiptReader.rows(in: photos)
                try Task.checkCancellation()
                let read = await ReceiptReader.read(rows, usingModel: usingModel && ExpenseTagger.availability == .available)
                try Task.checkCancellation()
                isReadingReceipt = false
                guard !read.isEmpty else {
                    receiptWasStopped = true
                    receiptFailed = true
                    return
                }
                withAnimation { fill(from: read) }
                await suggestCategory(from: read)
            } catch is CancellationError {
                // Stopped: `stopReadingReceipt` shows how to go on.
            } catch {
                isReadingReceipt = false
                receiptWasStopped = true
                receiptFailed = true
            }
        }
    }

    /// Stops reading the receipt, when it seems stuck, so the person can try again.
    private func stopReadingReceipt() {
        receiptTask?.cancel()
        receiptTask = nil
        isReadingReceipt = false
        receiptWasStopped = true
    }

    /// Keeps the receipt, and fills in from it only what's still empty, by the user's choice: the
    /// amount, unless the account is in another currency; who was paid; and the date, unless the
    /// person set it or it came from the inbox.
    private func fill(from read: Receipt) {
        receipt = read
        if amount == nil, let total = read.total, asset(account).map({ $0.currencyCode == read.currencyCode }) ?? true {
            currencyCode = read.currencyCode
            amountText = NumberField.text(for: total, fractionDigits: Currencies.fractionDigits(for: read.currencyCode))
        }
        if party.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            party = read.merchant
        }
        if !dateWasPicked, let receiptDate = read.date {
            date = receiptDate
        }
    }

    /// An expense's category from what the receipt says was bought, until the person picks one.
    private func suggestCategory(from receipt: Receipt) async {
        let note = ([receipt.merchant] + receipt.items.prefix(8).map(\.name)).filter { !$0.isEmpty }.joined(separator: ", ")
        guard mode == .expense, !categoryWasPicked, !note.isEmpty, ExpenseTagger.availability == .available,
              let category = try? await ExpenseTagger.suggest(note: note, amount: amount, currencyCode: currencyCode, tags: []).category,
              !categoryWasPicked
        else { return }
        withAnimation {
            expenseCategory = category
            categoryWasSuggested = true
            categoryIsFromReceipt = true
        }
    }

    private func save() {
        guard let amount, let kind else { return }
        let entry = Entry(
            id: original?.id ?? UUID(),
            kind: kind,
            amount: amount,
            currencyCode: currencyCode,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            party: mode == .transfer ? "" : party.trimmingCharacters(in: .whitespacesAndNewlines),
            // Tags say what money was spent or received for.
            tags: mode == .transfer ? [] : tags,
            receipt: mode == .transfer ? nil : receipt
        )
        do {
            try store.save(entry)
            if let captured {
                // The entry is saved either way. If this fails, the transaction stays in the
                // inbox.
                try? inbox.markAdded(id: captured.id, as: entry.id)
            }
            savedCount += 1
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    private func delete(_ entry: Entry) {
        do {
            try store.deleteEntry(id: entry.id)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

/// Picks one of the person's assets, by group.
private struct AssetPicker: View {
    let title: Text
    @Binding var selection: Asset.ID?
    let sections: [Ledger.AssetSection]

    var body: some View {
        Picker(selection: $selection) {
            if selection == nil {
                Text("Choose").tag(Asset.ID?.none)
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.assets) { asset in
                        AssetLabel(asset: asset).tag(Optional(asset.id))
                    }
                } header: {
                    Text(section.group.name)
                }
            }
        } label: {
            title
        }
    }
}

/// An asset's name and its kind's symbol.
struct AssetLabel: View {
    let asset: Asset

    var body: some View {
        Label {
            asset.title
        } icon: {
            Image(systemName: asset.kind.symbolName)
        }
    }
}

#Preview("New") {
    EntryEditor(editing: nil, currencyCode: "VND")
        .previewEnvironment()
}

#Preview("Edit") {
    EntryEditor(editing: Ledger.preview.entries[0], currencyCode: "VND")
        .previewEnvironment()
}

#Preview("Transfer") {
    EntryEditor(editing: Ledger.preview.entries.first { $0.flow == .neither }, currencyCode: "VND")
        .previewEnvironment()
        .environment(\.locale, Locale(identifier: "vi"))
}
