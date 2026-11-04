import RiengtuKit
import SwiftUI

/// Adds an expense, or edits one, in a sheet.
struct ExpenseEditor: View {
    /// The expense being edited, or `nil` for a new one.
    private let original: Expense?

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var currencyCode: String
    @State private var category: ExpenseCategory
    @State private var date: Date
    @State private var note: String
    @State private var saveFailed = false
    @State private var savedCount = 0
    @FocusState private var amountIsFocused: Bool

    init(editing expense: Expense?, currencyCode defaultCurrencyCode: String) {
        original = expense
        let currencyCode = expense?.currencyCode ?? defaultCurrencyCode
        _currencyCode = State(initialValue: currencyCode)
        _amountText = State(initialValue: expense.map {
            NumberField.text(for: $0.amount, fractionDigits: Currencies.fractionDigits(for: currencyCode))
        } ?? "")
        _category = State(initialValue: expense?.category ?? .food)
        _date = State(initialValue: expense?.date ?? .now)
        _note = State(initialValue: expense?.note ?? "")
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

                Section("Category") {
                    CategoryGrid(selection: $category)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note", text: $note, axis: .vertical)
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
                if original == nil { amountIsFocused = true }
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

    private func save() {
        guard let amount else { return }
        let expense = Expense(
            id: original?.id ?? UUID(),
            amount: amount,
            currencyCode: currencyCode,
            category: category,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try store.save(expense)
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
