import RiengtuKit
import SwiftUI

/// Every category at once, so picking one is a single tap.
struct CategoryGrid: View {
    @Binding var selection: ExpenseCategory

    @ScaledMetric(relativeTo: .caption) private var minimumWidth = 76

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 4, alignment: .top)], spacing: 12) {
            ForEach(ExpenseCategory.allCases, id: \.self) { category in
                Button {
                    selection = category
                } label: {
                    VStack(spacing: 6) {
                        CategoryIcon(category: category, isSelected: category == selection)
                        Text(category.name)
                            .font(.caption)
                            .fontWeight(category == selection ? .semibold : .regular)
                            .foregroundStyle(category == selection ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview {
    @Previewable @State var category = ExpenseCategory.food
    Form {
        CategoryGrid(selection: $category)
    }
}
