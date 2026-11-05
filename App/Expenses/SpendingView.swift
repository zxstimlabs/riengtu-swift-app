import RiengtuKit
import SwiftUI

/// Every expense, newest first, grouped by day, or only the ones with a tag. Amounts stay in
/// their own currencies.
struct SpendingView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(InboxStore.self) private var inbox
    @Environment(\.calendar) private var calendar
    @State private var editor: Editor?
    @State private var saveFailed = false
    /// The tag to show the expenses of, or `nil` for all of them.
    @State private var tagFilter: String?

    private enum Editor: Identifiable {
        case new
        case edit(Expense)
        case capture(CapturedTransaction)

        var id: UUID? {
            switch self {
            case .new: nil
            case .edit(let expense): expense.id
            case .capture(let item): item.id
            }
        }
    }

    var body: some View {
        let days = store.ledger.days(in: calendar, taggedWith: tagFilter)
        let showsInbox = tagFilter == nil && !inbox.items.isEmpty
        List {
            if showsInbox {
                Section {
                    ForEach(inbox.items) { item in
                        Button {
                            editor = .capture(item)
                        } label: {
                            CapturedRow(item: item)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Dismiss", systemImage: "xmark", role: .destructive) {
                                dismiss(item)
                            }
                        }
                    }
                } header: {
                    Text("Inbox")
                } footer: {
                    Text("Tap a payment to add it as an expense, or swipe to dismiss it.")
                }
            }
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
            if days.isEmpty, let tagFilter {
                ContentUnavailableView {
                    Label("No Expenses Tagged “\(Tags.displayName(tagFilter))”", systemImage: "tag")
                } actions: {
                    Button("Show All Expenses") { self.tagFilter = nil }
                }
            } else if days.isEmpty, !showsInbox {
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
        .navigationTitle(tagFilter.map { Text(verbatim: Tags.displayName($0)) } ?? Text("Spending"))
        .toolbar {
            if !store.ledger.tags.isEmpty {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        Picker("Tag", selection: $tagFilter) {
                            Text("All Expenses").tag(String?.none)
                            ForEach(store.ledger.tags, id: \.self) { tag in
                                Text(verbatim: Tags.displayName(tag)).tag(Optional(tag))
                            }
                        }
                    } label: {
                        Label(
                            "Filter by Tag",
                            systemImage: tagFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
            }
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
            case .capture(let item):
                ExpenseEditor(capturing: item, currencyCode: preferredCurrencyCode)
            }
        }
        .onChange(of: store.ledger.tags) { _, tags in
            // The tag was renamed or deleted.
            if let tagFilter, !tags.contains(tagFilter) { self.tagFilter = nil }
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

    private func dismiss(_ item: CapturedTransaction) {
        do {
            try inbox.remove(id: item.id)
        } catch {
            saveFailed = true
        }
    }
}

/// A payment waiting in the inbox: what it was for, when, and how much.
private struct CapturedRow: View {
    let item: CapturedTransaction

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbolName: item.source == .payment ? "creditcard.fill" : "envelope.fill", color: .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                if item.description.isEmpty {
                    Text(item.source == .payment ? "Payment" : "Bank Message")
                } else {
                    Text(verbatim: item.description)
                        .lineLimit(2)
                }
                Text(item.date, format: .dateTime.day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let amount = item.amount {
                Text(amount, format: .currency(code: item.currencyCode ?? Currencies.code(for: .autoupdatingCurrent)))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text("No Amount")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
                if !expense.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(verbatim: expense.tags.map(Tags.displayName).joined(separator: " · "))
                    }
                    .font(.caption)
                    .foregroundStyle(.tint)
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
