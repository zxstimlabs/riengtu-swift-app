import RiengtuKit
import SwiftUI

/// One entry in the ledger: what it was, the assets it touched, and how much, with a minus for
/// money out and a plus for money in.
struct EntryRow: View {
    let entry: Entry

    @Environment(LedgerStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                if entry.note.isEmpty {
                    title
                    if let detail {
                        Text(verbatim: detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(entry.note)
                        .lineLimit(2)
                    Text(verbatim: [titleString, detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !entry.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(verbatim: entry.tags.map(Tags.displayName).joined(separator: " · "))
                    }
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 8)
            EntryAmount(entry: entry)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch entry.kind {
        case .expense(let category, _):
            CategoryIcon(category: category)
        case .income(let category, _):
            CategoryIcon(category: category)
        case .transfer:
            IconBadge(symbolName: "arrow.left.arrow.right", color: .accentColor)
        case .adjustment(let id, _):
            if let asset = store.ledger.asset(id: id) {
                IconBadge(symbolName: asset.kind.symbolName, color: asset.kind.color)
            }
        }
    }

    private var title: Text {
        Text(verbatim: titleString)
    }

    /// The category, "Transfer", or the asset whose value changed.
    private var titleString: String {
        switch entry.kind {
        case .expense(let category, _):
            String(localized: category.name)
        case .income(let category, _):
            String(localized: category.name)
        case .transfer:
            String(localized: "Transfer")
        case .adjustment(let id, _):
            store.ledger.asset(id: id)?.titleString ?? String(localized: "Removed Asset")
        }
    }

    /// The account, the two sides of a transfer, or what changed about an asset.
    private var detail: String? {
        switch entry.kind {
        case .expense(_, let account), .income(_, let account):
            return account.map(name(of:))
        case .transfer(let from, let to):
            return "\(from.map { name(of: $0.asset) } ?? String(localized: "Removed Asset")) → \(to.map { name(of: $0.asset) } ?? String(localized: "Removed Asset"))"
        case .adjustment(let id, _):
            return store.ledger.asset(id: id)?.kind.group == .money
                ? String(localized: "Balance Updated")
                : String(localized: "Value Updated")
        }
    }

    private func name(of id: Asset.ID) -> String {
        store.ledger.asset(id: id)?.titleString ?? String(localized: "Removed Asset")
    }
}

/// An entry's amount: with a minus for spending, a plus for income, and either for a change to
/// an asset's value.
struct EntryAmount: View {
    let entry: Entry

    var body: some View {
        Group {
            switch entry.kind {
            case .expense:
                Text(-entry.amount, format: .currency(code: entry.currencyCode))
            case .income:
                Text(entry.amount, format: .currency(code: entry.currencyCode).sign(strategy: .always()))
                    .foregroundStyle(.green)
            case .transfer:
                Text(entry.amount, format: .currency(code: entry.currencyCode))
            case .adjustment(_, let isIncrease):
                Text(isIncrease ? entry.amount : -entry.amount, format: .currency(code: entry.currencyCode).sign(strategy: .always()))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}
