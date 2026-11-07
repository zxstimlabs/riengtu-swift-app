import RiengtuKit
import SwiftUI

/// A month of the ledger, newest first, grouped by day: what was spent and received, money moved
/// between the person's assets, and changes to their values. The month's income and spending are
/// totaled on top, each currency on its own. A tag shows only the entries that have it.
struct LedgerView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.calendar) private var calendar
    @State private var editor: Editor?
    @State private var saveFailed = false
    @State private var showsNewerVersion = false
    /// The tag to show the entries of, or `nil` for all of them.
    @State private var tagFilter: String?
    /// The start of the month shown, or `nil` for the current one, which follows the date.
    @State private var month: Date?

    private enum Editor: Identifiable {
        case new
        case edit(Entry)
        /// The asset whose change an adjustment records.
        case asset(Asset)

        var id: UUID? {
            switch self {
            case .new: nil
            case .edit(let entry): entry.id
            case .asset(let asset): asset.id
            }
        }
    }

    var body: some View {
        let ledger = store.ledger
        let interval = calendar.dateInterval(of: .month, for: shownMonth)!
        let days = ledger.days(in: calendar, during: interval, taggedWith: tagFilter)
        List {
            if ledger.unreadableRecordCount > 0 {
                Section {
                    Label("Some of your data was saved by a newer version of Riêng Tư. Update the app on this device to see it.", systemImage: "arrow.down.app")
                        .foregroundStyle(.secondary)
                }
            }
            if !ledger.entries.isEmpty {
                MonthSummary(
                    month: shownMonth,
                    flows: ledger.flows(during: interval, taggedWith: tagFilter),
                    countsEverything: !days.contains { $0.entries.contains { $0.flow == .neither } },
                    previous: canStep(by: -1) ? { step(by: -1) } : nil,
                    next: canStep(by: 1) ? { step(by: 1) } : nil
                )
            }
            if days.isEmpty, !ledger.entries.isEmpty {
                Section {
                    if let tagFilter {
                        Text("Nothing tagged “\(Tags.displayName(tagFilter))” in this month.")
                            .foregroundStyle(.secondary)
                        Button("Show Everything") { self.tagFilter = nil }
                    } else {
                        Text("Nothing recorded in this month.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        Button {
                            open(entry)
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(entry)
                            }
                        }
                    }
                } header: {
                    DayHeader(date: day.date)
                }
            }
        }
        .overlay {
            if ledger.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Transactions", systemImage: "book.closed")
                } description: {
                    Text("Add what you spend and receive, and money you move between accounts. It stays on this device.")
                } actions: {
                    Button("Add Transaction") { editor = .new }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(tagFilter.map { Text(verbatim: Tags.displayName($0)) } ?? Text("Ledger"))
        .settingsButton()
        .toolbar {
            if !ledger.tags.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Tag", selection: $tagFilter) {
                            Text("All Transactions").tag(String?.none)
                            ForEach(ledger.tags, id: \.self) { tag in
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
                Button("Add Transaction", systemImage: "plus") { editor = .new }
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                EntryEditor(editing: nil, currencyCode: preferredCurrencyCode)
            case .edit(let entry):
                EntryEditor(editing: entry, currencyCode: preferredCurrencyCode)
            case .asset(let asset):
                AssetEditor(editing: asset, kind: asset.kind, currencyCode: asset.currencyCode)
            }
        }
        .onChange(of: ledger.tags) { _, tags in
            // The tag was renamed or deleted.
            if let tagFilter, !tags.contains(tagFilter) { self.tagFilter = nil }
        }
        .newerVersionAlert(isPresented: $showsNewerVersion)
        .alert("Couldn’t Save", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
        }
    }

    // MARK: Months

    private var currentMonth: Date {
        calendar.dateInterval(of: .month, for: .now)!.start
    }

    private var shownMonth: Date {
        month ?? currentMonth
    }

    /// Whether there's a month to go to: back to the earliest entry's, and on to this month or
    /// the latest entry's, if that's later.
    private func canStep(by months: Int) -> Bool {
        guard let range = store.ledger.dateRange else { return false }
        if months < 0 {
            return shownMonth > calendar.dateInterval(of: .month, for: range.lowerBound)!.start
        }
        return shownMonth < max(currentMonth, calendar.dateInterval(of: .month, for: range.upperBound)!.start)
    }

    private func step(by months: Int) {
        let next = calendar.date(byAdding: .month, value: months, to: shownMonth)!
        month = next == currentMonth ? nil : next
    }

    // MARK: Actions

    private var preferredCurrencyCode: String {
        store.ledger.preferredCurrencyCode(fallback: Currencies.code(for: .autoupdatingCurrent))
    }

    private func open(_ entry: Entry) {
        if case .adjustment(let id, _) = entry.kind {
            guard let asset = store.ledger.asset(id: id) else { return }
            if store.ledger.newerIDs.contains(id) {
                showsNewerVersion = true
            } else {
                editor = .asset(store.ledger.current(asset))
            }
        } else if store.ledger.newerIDs.contains(entry.id) {
            showsNewerVersion = true
        } else {
            editor = .edit(entry)
        }
    }

    private func delete(_ entry: Entry) {
        do {
            try store.deleteEntry(id: entry.id)
        } catch {
            saveFailed = true
        }
    }

}

/// The month shown, with buttons to step through months, and the money that came in and went
/// out in each currency.
private struct MonthSummary: View {
    let month: Date
    let flows: [Ledger.MoneyFlow]
    /// Whether the month has no transfers or adjustments, which the totals leave out.
    let countsEverything: Bool
    let previous: (() -> Void)?
    let next: (() -> Void)?

    var body: some View {
        Section {
            HStack {
                Button("Previous Month", systemImage: "chevron.left") { previous?() }
                    .disabled(previous == nil)
                Spacer()
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
                Button("Next Month", systemImage: "chevron.right") { next?() }
                    .disabled(next == nil)
            }
            .labelStyle(.iconOnly)
            // Each button is tapped on its own, not the whole row.
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            ForEach(flows) { flow in
                LabeledContent("Money In") {
                    Text(flow.moneyIn, format: .money(code: flow.currencyCode))
                        .foregroundStyle(flow.moneyIn > 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                }
                LabeledContent("Money Out") {
                    Text(-flow.moneyOut, format: .money(code: flow.currencyCode))
                }
                LabeledContent("Net") {
                    Text(flow.net, format: .money(code: flow.currencyCode).showingPlus())
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .monospacedDigit()
        } footer: {
            if flows.count > 1 {
                Text("Each currency is totaled on its own.")
            } else if !countsEverything {
                Text("Transfers and changes to assets’ values aren’t counted.")
            }
        }
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
        LedgerView()
    }
    .previewEnvironment()
}

#Preview("Vietnamese") {
    NavigationStack {
        LedgerView()
    }
    .previewEnvironment()
    .environment(\.locale, Locale(identifier: "vi"))
}

#Preview("Empty") {
    NavigationStack {
        LedgerView()
    }
    .previewEnvironment(Ledger())
}
