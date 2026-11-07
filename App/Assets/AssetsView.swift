import RiengtuKit
import SwiftUI

/// What the person owns, grouped into money, investments, and property and belongings, with what
/// it's worth in each currency. Each asset shows what it holds now: its value as set by hand, with
/// what entries changed since.
struct AssetsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editor: Editor?
    @State private var saveFailed = false
    @State private var showsNewerVersion = false

    private enum Editor: Identifiable {
        case new(AssetKind)
        case edit(Asset)

        var id: String {
            switch self {
            case .new(let kind): "new-\(kind.rawValue)"
            case .edit(let asset): asset.id.uuidString
            }
        }
    }

    var body: some View {
        let sections = store.ledger.assetSections()
        let totals = store.ledger.assetTotals()
        List {
            if !totals.isEmpty {
                Section {
                    ForEach(totals) { total in
                        Text(total.amount, format: .money(code: total.currencyCode))
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            // A number reads wrong split over two lines.
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                } header: {
                    Text("Total")
                } footer: {
                    if totals.count > 1 {
                        Text("Each currency is totaled on its own.")
                    }
                }
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.assets) { asset in
                        Button {
                            if store.ledger.newerIDs.contains(asset.id) {
                                showsNewerVersion = true
                            } else {
                                editor = .edit(asset)
                            }
                        } label: {
                            AssetRow(asset: asset)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(asset)
                            }
                        }
                    }
                } header: {
                    Text(section.group.name)
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label("No Assets", systemImage: "chart.pie")
                } description: {
                    Text("Add what you own, from money and stocks to gold and property. It stays on this device.")
                } actions: {
                    AddAssetMenu(add: add) {
                        Text("Add Asset")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Assets")
        .settingsButton()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddAssetMenu(add: add) {
                    Label("Add Asset", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new(let kind):
                AssetEditor(editing: nil, kind: kind, currencyCode: Self.currencyCode(for: kind))
            case .edit(let asset):
                AssetEditor(editing: asset, kind: asset.kind, currencyCode: asset.currencyCode)
            }
        }
        .newerVersionAlert(isPresented: $showsNewerVersion)
        .alert("Couldn’t Save", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
        }
    }

    /// The currency a new asset starts in. Vietnamese shares, fund certificates and gold are
    /// priced in đồng; anything else starts in the region's currency.
    private static func currencyCode(for kind: AssetKind) -> String {
        switch kind {
        case .stock, .fund, .gold: "VND"
        default: Currencies.code(for: .autoupdatingCurrent)
        }
    }

    private func add(_ kind: AssetKind) {
        editor = .new(kind)
    }

    private func delete(_ asset: Asset) {
        do {
            try store.deleteAsset(id: asset.id)
        } catch {
            saveFailed = true
        }
    }
}

/// A menu of every kind of asset, by group, so the editor opens with the right fields.
private struct AddAssetMenu<MenuLabel: View>: View {
    let add: (AssetKind) -> Void
    @ViewBuilder let label: MenuLabel

    var body: some View {
        Menu {
            ForEach(AssetKind.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(AssetKind.kinds(in: group), id: \.self) { kind in
                        Button {
                            add(kind)
                        } label: {
                            Label {
                                Text(kind.name)
                            } icon: {
                                Image(systemName: kind.symbolName)
                            }
                        }
                    }
                } header: {
                    Text(group.name)
                }
            }
        } label: {
            label
        }
    }
}

private struct AssetRow: View {
    let asset: Asset

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbolName: asset.kind.symbolName, color: asset.kind.color)
            VStack(alignment: .leading, spacing: 2) {
                if asset.name.isEmpty {
                    Text(asset.kind.name)
                } else {
                    Text(asset.name)
                        .lineLimit(2)
                }
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if !asset.name.isEmpty {
                    Text(asset.kind.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(asset.worth, format: .money(code: asset.currencyCode))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// How the value is worked out, such as "1.000 × 125.500 ₫", or "5 chỉ · 148.500.000 ₫ per
    /// lượng" for gold: numbers and units, with no sentence to translate.
    private var detail: String? {
        let currency = Decimal.FormatStyle.Currency(code: asset.currencyCode, locale: locale)
        let quantity = Decimal.FormatStyle(locale: locale).precision(.fractionLength(0...asset.kind.quantityFractionDigits))
        switch asset.value {
        case .amount:
            return nil
        case .holding(let count, let price):
            return "\(count.formatted(quantity)) × \(price.formatted(currency))"
        case .gold(let weight, let unit, let price, let priceUnit):
            let weightText = String(localized: unit.weight(weight.formatted(quantity)))
            return "\(weightText) · \(price.formatted(currency)) \(String(localized: priceUnit.perName))"
        }
    }
}

#Preview("English") {
    NavigationStack {
        AssetsView()
    }
    .previewEnvironment()
}

#Preview("Vietnamese") {
    NavigationStack {
        AssetsView()
    }
    .previewEnvironment()
    .environment(\.locale, Locale(identifier: "vi"))
}

#Preview("Empty") {
    NavigationStack {
        AssetsView()
    }
    .previewEnvironment(Ledger())
}
