import RiengtuKit
import SwiftUI

extension IncomeCategory: DisplayedCategory {
    var name: LocalizedStringResource {
        switch self {
        case .salary: "Salary"
        case .bonus: "Bonus"
        case .business: "Business"
        case .sideJob: "Side Jobs"
        case .investment: "Interest & Dividends"
        case .rental: "Rent Received"
        case .gifts: "Gifts & Lucky Money"
        case .family: "From Family"
        case .refunds: "Refunds & Cashback"
        case .selling: "Things Sold"
        case .other: "Other"
        }
    }

    /// Symbols that are in iOS 18.0, the app's oldest version.
    var symbolName: String {
        switch self {
        case .salary: "briefcase.fill"
        case .bonus: "sparkles"
        case .business: "storefront.fill"
        case .sideJob: "hammer.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .rental: "key.fill"
        case .gifts: "gift.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .refunds: "arrow.uturn.backward.circle.fill"
        case .selling: "dollarsign.arrow.circlepath"
        case .other: "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .salary: .green
        case .bonus: .yellow
        case .business: .orange
        case .sideJob: .indigo
        case .investment: .teal
        case .rental: .brown
        case .gifts: .pink
        case .family: .mint
        case .refunds: .blue
        case .selling: .cyan
        case .other: .gray
        }
    }
}
