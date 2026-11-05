import RiengtuKit
import SwiftUI

/// Adds an expense, or edits one, in a sheet.
///
/// Where Apple Intelligence is available, the model on the device reads the note as it's typed
/// and suggests tags, and a category until the person picks one.
struct ExpenseEditor: View {
    /// The expense being edited, or `nil` for a new one.
    private let original: Expense?
    /// The payment from the inbox this expense starts from, which leaves the inbox once it's
    /// saved.
    private let captured: CapturedTransaction?

    @Environment(LedgerStore.self) private var store
    @Environment(InboxStore.self) private var inbox
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var currencyCode: String
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var note: String
    @State private var tags: [String]
    @State private var suggestion: TagSuggestion?
    /// Whether the person picked the category, so a suggestion doesn't change it.
    @State private var categoryWasPicked: Bool
    @State private var categoryWasSuggested = false
    @State private var saveFailed = false
    @State private var savedCount = 0
    @FocusState private var amountIsFocused: Bool
    @AppStorage(SettingsView.suggestsTagsKey) private var suggestsTags = true

    init(editing expense: Expense?, currencyCode defaultCurrencyCode: String) {
        self.init(expense: expense, captured: nil, currencyCode: defaultCurrencyCode)
    }

    /// A new expense from a payment in the inbox.
    init(capturing item: CapturedTransaction, currencyCode defaultCurrencyCode: String) {
        self.init(expense: nil, captured: item, currencyCode: defaultCurrencyCode)
    }

    private init(expense: Expense?, captured: CapturedTransaction?, currencyCode defaultCurrencyCode: String) {
        original = expense
        self.captured = captured
        let currencyCode = expense?.currencyCode ?? captured?.currencyCode ?? defaultCurrencyCode
        let amount = expense?.amount ?? captured?.amount
        _currencyCode = State(initialValue: currencyCode)
        _amountText = State(initialValue: amount.map {
            NumberField.text(for: $0, fractionDigits: Currencies.fractionDigits(for: currencyCode))
        } ?? "")
        _category = State(initialValue: expense?.category ?? .food)
        _date = State(initialValue: expense?.date ?? captured?.date ?? .now)
        _note = State(initialValue: expense?.note ?? captured?.description ?? "")
        _tags = State(initialValue: expense?.tags ?? [])
        _categoryWasPicked = State(initialValue: expense != nil)
    }

    private var amount: Decimal? {
        NumberField.number(in: amountText).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Currencies.symbol(for: currencyCode, locale: NumberField.locale))
                            .foregroundStyle(.secondary)
                        NumberField(title: Text("Amount"), text: $amountText, fractionDigits: fractionDigits)
                            .focused($amountIsFocused)
                    }
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                    NavigationLink {
                        CurrencyPicker(selection: $currencyCode, suggested: suggestedCurrencies)
                    } label: {
                        LabeledContent("Currency", value: currencyCode)
                    }
                }

                Section {
                    CategoryGrid(selection: Binding(
                        get: { category },
                        set: { picked in
                            category = picked
                            categoryWasPicked = true
                            categoryWasSuggested = false
                        }
                    ))
                } header: {
                    Text("Category")
                } footer: {
                    if categoryWasSuggested {
                        Label("Picked from your note by Apple Intelligence.", systemImage: "apple.intelligence")
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note", text: $note, axis: .vertical)
                }

                Section {
                    TagPicker(selection: $tags, tags: store.ledger.tags, suggestion: suggestion)
                } header: {
                    Text("Tags")
                } footer: {
                    if let suggestion, !suggestion.tags.allSatisfy(tags.contains) || suggestion.newTag != nil {
                        Label("Suggested by Apple Intelligence on this device. Tap to add.", systemImage: "apple.intelligence")
                    }
                }

                if let captured, !captured.text.isEmpty {
                    Section {
                        DisclosureGroup("Bank Message") {
                            Text(verbatim: captured.text)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let original {
                    Section {
                        Button("Delete Expense", role: .destructive) {
                            delete(original)
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Expense" : "Edit Expense")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(amount == nil)
                }
            }
            .onAppear {
                if original == nil, captured?.amount == nil { amountIsFocused = true }
            }
            .task(id: note) {
                await suggest()
            }
            .alert("Couldn’t Save", isPresented: $saveFailed) {
                Button("OK") {}
            } message: {
                Text("Riengtu couldn’t save your change. Try again.")
            }
            .sensoryFeedback(.success, trigger: savedCount)
        }
        .privacyShield()
    }

    private var fractionDigits: Int {
        Currencies.fractionDigits(for: currencyCode)
    }

    private var suggestedCurrencies: [String] {
        let recent = store.ledger.recentCurrencyCodes
        return recent.isEmpty ? [Currencies.code(for: NumberField.locale)] : recent
    }

    /// Asks the model about the note, once the person stops typing for a moment. Typing again
    /// cancels the question.
    private func suggest() async {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard suggestsTags, note.count >= 2, note != original?.note,
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
                    category = suggested
                    categoryWasSuggested = true
                }
            }
        } catch {
            // Cancelled by more typing, or the model couldn't answer, such as for a language it
            // doesn't support. Either way, no suggestion.
        }
    }

    private func save() {
        guard let amount else { return }
        let expense = Expense(
            id: original?.id ?? UUID(),
            amount: amount,
            currencyCode: currencyCode,
            category: category,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags
        )
        do {
            try store.save(expense)
            if let captured {
                // The expense is saved either way. If this fails, the payment stays in the inbox.
                try? inbox.remove(id: captured.id)
            }
            savedCount += 1
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    private func delete(_ expense: Expense) {
        do {
            try store.deleteExpense(id: expense.id)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

#Preview("New") {
    ExpenseEditor(editing: nil, currencyCode: "VND")
        .previewEnvironment()
}

#Preview("Edit") {
    ExpenseEditor(editing: Ledger.preview.expenses[0], currencyCode: "VND")
        .previewEnvironment()
}
