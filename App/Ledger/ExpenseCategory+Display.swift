import RiengtuKit
import SwiftUI

extension ExpenseCategory {
    var name: LocalizedStringResource {
        switch self {
        case .food: "Eating Out"
        case .drinks: "Coffee & Drinks"
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .vehicle: "Vehicle"
        case .housing: "Housing"
        case .household: "Household"
        case .bills: "Bills"
        case .subscriptions: "Subscriptions"
        case .shopping: "Shopping"
        case .fashion: "Fashion"
        case .electronics: "Electronics"
        case .beauty: "Beauty & Care"
        case .health: "Health"
        case .fitness: "Sports & Fitness"
        case .insurance: "Insurance"
        case .education: "Education"
        case .entertainment: "Entertainment"
        case .travel: "Travel"
        case .family: "Family"
        case .kids: "Kids"
        case .pets: "Pets"
        case .gifts: "Gifts & Occasions"
        case .charity: "Charity"
        case .worship: "Worship & Offerings"
        case .fees: "Fees & Taxes"
        case .loans: "Loans & Installments"
        case .other: "Other"
        }
    }

    /// Symbols that are in iOS 18.0, the app's oldest version.
    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .drinks: "cup.and.saucer.fill"
        case .groceries: "cart.fill"
        case .transport: "car.fill"
        case .vehicle: "wrench.and.screwdriver.fill"
        case .housing: "house.fill"
        case .household: "sofa.fill"
        case .bills: "doc.text.fill"
        case .subscriptions: "repeat.circle.fill"
        case .shopping: "bag.fill"
        case .fashion: "tshirt.fill"
        case .electronics: "laptopcomputer"
        case .beauty: "comb.fill"
        case .health: "cross.case.fill"
        case .fitness: "figure.run"
        case .insurance: "umbrella.fill"
        case .education: "book.fill"
        case .entertainment: "popcorn.fill"
        case .travel: "airplane"
        case .family: "figure.2.and.child.holdinghands"
        case .kids: "teddybear.fill"
        case .pets: "pawprint.fill"
        case .gifts: "gift.fill"
        case .charity: "heart.fill"
        case .worship: "flame.fill"
        case .fees: "percent"
        case .loans: "calendar.badge.clock"
        case .other: "ellipsis"
        }
    }

    /// There are more categories than system colors, so some share one, kept apart in the order.
    var color: Color {
        switch self {
        case .food: .orange
        case .drinks: .brown
        case .groceries: .green
        case .transport: .blue
        case .vehicle: .indigo
        case .housing: .teal
        case .household: .mint
        case .bills: .cyan
        case .subscriptions: .purple
        case .shopping: .pink
        case .fashion: .red
        case .electronics: .gray
        case .beauty: .pink
        case .health: .red
        case .fitness: .green
        case .insurance: .blue
        case .education: .indigo
        case .entertainment: .purple
        case .travel: .teal
        case .family: .mint
        case .kids: .yellow
        case .pets: .brown
        case .gifts: .pink
        case .charity: .red
        case .worship: .yellow
        case .fees: .gray
        case .loans: .orange
        case .other: .gray
        }
    }
}

/// The category's symbol in a circle of its color.
struct CategoryIcon<Category: DisplayedCategory>: View {
    let category: Category
    var isSelected = false

    var body: some View {
        IconBadge(symbolName: category.symbolName, color: category.color, isSelected: isSelected)
    }
}

/// A category of expense or of income, as the app shows it.
protocol DisplayedCategory: Hashable, CaseIterable where AllCases: RandomAccessCollection {
    var name: LocalizedStringResource { get }
    /// A symbol that's in iOS 18.0, the app's oldest version.
    var symbolName: String { get }
    var color: Color { get }
}

extension ExpenseCategory: DisplayedCategory {}
