import RiengtuKit
import SwiftUI

/// Every expense, newest first, grouped by day. Amounts stay in their own currencies.
struct SpendingView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.calendar) private var calendar
    @State private var editor: Editor?
    @State private var saveFailed = false

    private enum Editor: Identifiable {
        case new
        case edit(Expense)

        var id: UUID? {
            switch self {
            case .new: nil
            case .edit(let expense): expense.id
            }
        }
    }

    var body: some View {
        let days = store.ledger.days(in: calendar)
        List {
            ForEach(days) { day in
                Section {
                    ForEach(day.expenses) { expense in
                        Button {
                            editor = .edit(expense)
                        } label: {
                            ExpenseRow(expense: expense)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(expense)
                            }
                        }
                    }
                } header: {
                    DayHeader(date: day.date)
                }
            }
        }
        .overlay {
            if days.isEmpty {
                ContentUnavailableView {
                    Label("No Expenses", systemImage: "wallet.bifold")
                } description: {
                    Text("Add what you spend. It stays on this device.")
                } actions: {
                    Button("Add Expense") { editor = .new }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Spending")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Expense", systemImage: "plus") { editor = .new }
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                ExpenseEditor(editing: nil, currencyCode: preferredCurrencyCode)
            case .edit(let expense):
                ExpenseEditor(editing: expense, currencyCode: preferredCurrencyCode)
            }
        }
        .alert("Couldn’t Save", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
        }
    }

    private var preferredCurrencyCode: String {
        store.ledger.preferredCurrencyCode(fallback: Currencies.code(for: .autoupdatingCurrent))
    }

    private func delete(_ expense: Expense) {
        do {
            try store.deleteExpense(id: expense.id)
        } catch {
            saveFailed = true
        }
    }
}

private struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: expense.category)
            VStack(alignment: .leading, spacing: 2) {
                if expense.note.isEmpty {
                    Text(expense.category.name)
                } else {
                    Text(expense.note)
                        .lineLimit(2)
                    Text(expense.category.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(expense.amount, format: .currency(code: expense.currencyCode))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct DayHeader: View {
    let date: Date

    @Environment(\.calendar) private var calendar

    var body: some View {
        if calendar.isDateInToday(date) {
            Text("Today")
        } else if calendar.isDateInYesterday(date) {
            Text("Yesterday")
        } else if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
        } else {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
        }
    }
}

#Preview("English") {
    NavigationStack {
        SpendingView()
    }
    .previewEnvironment()
}

#Preview("Vietnamese") {
    NavigationStack {
        SpendingView()
    }
    .previewEnvironment()
    .environment(\.locale, Locale(identifier: "vi"))
}

#Preview("Empty") {
    NavigationStack {
        SpendingView()
    }
    .previewEnvironment(Ledger())
}
