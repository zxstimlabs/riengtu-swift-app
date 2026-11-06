import RiengtuKit
import SwiftUI

/// Adds an asset, or edits one, in a sheet. The fields follow how the kind is valued: an amount,
/// a quantity and a price, or a weight of gold and a price by weight.
struct AssetEditor: View {
    /// The asset being edited as it is now (`Ledger.current`), with what entries changed since
    /// its value was set, or `nil` for a new one.
    private let original: Asset?

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: AssetKind
    @State private var name: String
    @State private var currencyCode: String
    /// The balance or value, for kinds valued by an amount.
    @State private var amountText: String
    /// The number of shares, units or coins, or the weight of gold.
    @State private var quantityText: String
    @State private var priceText: String
    @State private var weightUnit: GoldUnit
    @State private var priceUnit: GoldUnit
    @State private var note: String
    /// What the value's fields started with, to tell whether the person changed them.
    private let startingValueFields: [String]
    @State private var saveFailed = false
    @State private var savedCount = 0
    @FocusState private var focus: Field?

    private enum Field {
        case name, amount, quantity
    }

    init(editing asset: Asset?, kind defaultKind: AssetKind, currencyCode defaultCurrencyCode: String) {
        original = asset
        let kind = asset?.kind ?? defaultKind
        let currencyCode = asset?.currencyCode ?? defaultCurrencyCode
        let moneyDigits = Currencies.fractionDigits(for: currencyCode)
        _kind = State(initialValue: kind)
        _name = State(initialValue: asset?.name ?? "")
        _currencyCode = State(initialValue: currencyCode)
        _note = State(initialValue: asset?.note ?? "")

        var amountText = "", quantityText = "", priceText = ""
        var weightUnit = GoldUnit.chi, priceUnit = GoldUnit.luong
        switch asset?.value {
        case .amount(let amount):
            amountText = NumberField.text(for: amount, fractionDigits: moneyDigits)
        case .holding(let quantity, let price):
            quantityText = NumberField.text(for: quantity, fractionDigits: kind.quantityFractionDigits)
            priceText = NumberField.text(for: price, fractionDigits: moneyDigits)
        case .gold(let weight, let unit, let price, let unitOfPrice):
            quantityText = NumberField.text(for: weight, fractionDigits: kind.quantityFractionDigits)
            priceText = NumberField.text(for: price, fractionDigits: moneyDigits)
            weightUnit = unit
            priceUnit = unitOfPrice
        case nil:
            break
        }
        _amountText = State(initialValue: amountText)
        _quantityText = State(initialValue: quantityText)
        _priceText = State(initialValue: priceText)
        _weightUnit = State(initialValue: weightUnit)
        _priceUnit = State(initialValue: priceUnit)
        startingValueFields = [amountText, quantityText, priceText, weightUnit.rawValue, priceUnit.rawValue]
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value as typed, or `nil` while something it needs is missing. Shares, fund
    /// certificates and coins also need a ticker.
    ///
    /// Until the fields are changed, it's the value the asset had, which can be below zero after
    /// entries took from it. The fields can't show a minus, nor can it be typed.
    private var value: Asset.Value? {
        if let original, original.kind.valuation == kind.valuation,
           [amountText, quantityText, priceText, weightUnit.rawValue, priceUnit.rawValue] == startingValueFields,
           kind.valuation != .holding || !trimmedName.isEmpty {
            return original.value
        }
        let quantity = NumberField.number(in: quantityText).flatMap { $0 > 0 ? $0 : nil }
        let price = NumberField.number(in: priceText)
        switch kind.valuation {
        case .amount:
            return NumberField.number(in: amountText).map { .amount($0) }
        case .holding:
            guard let quantity, let price, !trimmedName.isEmpty else { return nil }
            return .holding(quantity: quantity, price: price)
        case .gold:
            guard let quantity, let price else { return nil }
            return .gold(weight: quantity, unit: weightUnit, price: price, priceUnit: priceUnit)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(AssetKind.Group.allCases, id: \.self) { group in
                            Section {
                                ForEach(AssetKind.kinds(in: group), id: \.self) { kind in
                                    Label {
                                        Text(kind.name)
                                    } icon: {
                                        Image(systemName: kind.symbolName)
                                    }
                                    .tag(kind)
                                }
                            } header: {
                                Text(group.name)
                            }
                        }
                    }
                    nameField
                }

                switch kind.valuation {
                case .amount: amountSection
                case .holding: holdingSection
                case .gold: goldSection
                }

                Section {
                    TextField("Note", text: $note, axis: .vertical)
                } footer: {
                    if let original {
                        Text("Updated \(original.valuedAt, format: .dateTime.day().month().year())")
                    }
                }

                if let original {
                    Section {
                        Button("Delete Asset", role: .destructive) {
                            delete(original)
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Asset" : "Edit Asset")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(value == nil)
                }
            }
            .onAppear {
                guard original == nil else { return }
                switch kind.valuation {
                case .amount: focus = .amount
                case .holding: focus = .name
                case .gold: focus = .quantity
                }
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

    @ViewBuilder private var nameField: some View {
        if kind.valuation == .holding {
            TextField("Ticker", text: $name, prompt: Text(verbatim: kind.tickerExample))
                .focused($focus, equals: .name)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
        } else {
            TextField("Name", text: $name, prompt: Text(kind.name))
                .focused($focus, equals: .name)
        }
    }

    // MARK: Values

    private var amountSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: isBelowZero ? "−" + currencySymbol : currencySymbol)
                    .foregroundStyle(isBelowZero ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                NumberField(title: kind.group == .money ? Text("Balance") : Text("Value"), text: $amountText, fractionDigits: moneyDigits)
                    .focused($focus, equals: .amount)
            }
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .monospacedDigit()

            currencyRow
        } header: {
            Text(kind.group == .money ? "Balance" : "Value")
        } footer: {
            if isBelowZero {
                Text("Below zero, because more was recorded going out than coming in. Type what’s there now.")
            } else if kind.group == .things {
                Text("What it would sell for today.")
            }
        }
    }

    /// Whether the balance entries left is below zero, and hasn't been changed yet.
    private var isBelowZero: Bool {
        if case .amount(let amount)? = value, amount < 0 { true } else { false }
    }

    private var holdingSection: some View {
        Section {
            LabeledContent {
                NumberField(title: Text(kind.quantityName), text: $quantityText, fractionDigits: kind.quantityFractionDigits)
                    .focused($focus, equals: .quantity)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(kind.quantityName)
            }
            priceRow
            currencyRow
            worthRow
        } footer: {
            priceFooter
        }
    }

    private var goldSection: some View {
        Section {
            LabeledContent {
                HStack {
                    NumberField(title: Text("Weight"), text: $quantityText, fractionDigits: kind.quantityFractionDigits)
                        .focused($focus, equals: .quantity)
                        .multilineTextAlignment(.trailing)
                    Picker("Unit", selection: $weightUnit) {
                        ForEach(GoldUnit.allCases, id: \.self) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } label: {
                Text("Weight")
            }
            priceRow
            currencyRow
            worthRow
        } footer: {
            priceFooter
        }
    }

    private var priceRow: some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currencySymbol)
                    .foregroundStyle(.secondary)
                NumberField(title: Text("Price"), text: $priceText, fractionDigits: moneyDigits)
                    .multilineTextAlignment(.trailing)
                if kind.valuation == .gold {
                    Picker("Price Unit", selection: $priceUnit) {
                        ForEach(GoldUnit.allCases, id: \.self) { unit in
                            Text(unit.perName).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .monospacedDigit()
        } label: {
            Text("Price")
        }
    }

    private var currencyRow: some View {
        NavigationLink {
            CurrencyPicker(selection: $currencyCode, suggested: suggestedCurrencies)
        } label: {
            LabeledContent("Currency", value: currencyCode)
        }
    }

    /// What the quantity is worth at the price, once both are typed.
    @ViewBuilder private var worthRow: some View {
        if let value {
            let asset = Asset(kind: kind, currencyCode: currencyCode, value: value, valuedAt: .now)
            LabeledContent("Value") {
                Text(asset.worth, format: .currency(code: currencyCode))
                    .monospacedDigit()
            }
        }
    }

    /// Price boards in Vietnam usually leave off the last three zeros.
    @ViewBuilder private var priceFooter: some View {
        if currencyCode == "VND" {
            Text("Type the whole price in đồng. Price boards often show it in thousands.")
        }
    }

    private var moneyDigits: Int {
        Currencies.fractionDigits(for: currencyCode)
    }

    private var currencySymbol: String {
        Currencies.symbol(for: currencyCode, locale: NumberField.locale)
    }

    /// The region's currency, the ones assets are already in, and the ones spent in recently.
    private var suggestedCurrencies: [String] {
        let ledger = store.ledger
        var seen = Set<String>()
        let codes = [Currencies.code(for: NumberField.locale)] + ledger.assets.map(\.currencyCode) + ledger.recentCurrencyCodes
        return Array(codes.filter { seen.insert($0).inserted }.prefix(Ledger.recentCurrencyLimit))
    }

    // MARK: Saving

    private func save() {
        guard let value else { return }
        // Unchanged, it keeps the value set by hand, and when, so the entries since still count.
        // Changed, what's typed is its value from now on.
        let isUnchanged = original?.value == value && original?.currencyCode == currencyCode
        let setByHand = original.flatMap { store.ledger.asset(id: $0.id) }
        let asset = Asset(
            id: original?.id ?? UUID(),
            kind: kind,
            name: kind.valuation == .holding ? trimmedName.uppercased() : trimmedName,
            currencyCode: currencyCode,
            value: isUnchanged ? setByHand?.value ?? value : value,
            valuedAt: isUnchanged ? setByHand?.valuedAt ?? .now : .now,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            // A change to its value goes in the ledger.
            try store.save(asset, recordingChangeOn: .now)
            savedCount += 1
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    private func delete(_ asset: Asset) {
        do {
            try store.deleteAsset(id: asset.id)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

#Preview("New Gold") {
    AssetEditor(editing: nil, kind: .gold, currencyCode: "VND")
        .previewEnvironment()
}

#Preview("Edit Stocks") {
    AssetEditor(editing: Ledger.preview.assets.first { $0.kind == .stock }, kind: .stock, currencyCode: "VND")
        .previewEnvironment()
}

#Preview("Vietnamese") {
    AssetEditor(editing: Ledger.preview.assets.first { $0.kind == .gold }, kind: .gold, currencyCode: "VND")
        .previewEnvironment()
        .environment(\.locale, Locale(identifier: "vi"))
}
