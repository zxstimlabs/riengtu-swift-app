import RiengtuKit
import SwiftUI

extension ExpenseCategory {
    var name: LocalizedStringResource {
        switch self {
        case .food: "Food & Drink"
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .housing: "Housing"
        case .bills: "Bills"
        case .health: "Health"
        case .education: "Education"
        case .entertainment: "Entertainment"
        case .travel: "Travel"
        case .family: "Family"
        case .gifts: "Gifts & Occasions"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "cart.fill"
        case .transport: "car.fill"
        case .shopping: "bag.fill"
        case .housing: "house.fill"
        case .bills: "doc.text.fill"
        case .health: "cross.case.fill"
        case .education: "book.fill"
        case .entertainment: "popcorn.fill"
        case .travel: "airplane"
        case .family: "figure.2.and.child.holdinghands"
        case .gifts: "gift.fill"
        case .other: "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .food: .orange
        case .groceries: .green
        case .transport: .blue
        case .shopping: .pink
        case .housing: .brown
        case .bills: .cyan
        case .health: .red
        case .education: .indigo
        case .entertainment: .purple
        case .travel: .teal
        case .family: .mint
        case .gifts: .pink
        case .other: .gray
        }
    }
}

/// The category's symbol in a circle of its color.
struct CategoryIcon: View {
    let category: ExpenseCategory
    var isSelected = false

    var body: some View {
        IconBadge(symbolName: category.symbolName, color: category.color, isSelected: isSelected)
    }
}
