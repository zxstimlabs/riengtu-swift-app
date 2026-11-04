import RiengtuKit
import SwiftUI

/// Picks the currency of an expense, with the ones used recently on top.
struct CurrencyPicker: View {
    @Binding var selection: String
    /// Shown first. Never empty in practice: before any expense, it's the region's currency.
    let suggested: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty {
                Section("Suggested") {
                    ForEach(suggested, id: \.self, content: row)
                }
                Section("All Currencies") {
                    ForEach(sorted, id: \.self, content: row)
                }
            } else {
                ForEach(matching, id: \.self, content: row)
            }
        }
        .searchable(text: $query)
        .navigationTitle("Currency")
    }

    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(name(of: code))
                    Text(code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(code == selection ? .isSelected : [])
    }

    /// All currencies, by name in the app's language.
    private var sorted: [String] {
        Currencies.all
            .map { (code: $0, name: name(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.code)
    }

    private var matching: [String] {
        sorted.filter { code in
            code.localizedStandardContains(query) || name(of: code).localizedStandardContains(query)
        }
    }

    /// The currency's name from the system, already in the app's language.
    private func name(of code: String) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }
}

#Preview {
    @Previewable @State var code = "VND"
    NavigationStack {
        CurrencyPicker(selection: $code, suggested: ["VND", "USD"])
    }
}
