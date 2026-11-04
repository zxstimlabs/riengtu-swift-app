import RiengtuKit
import SwiftUI

extension AssetKind {
    var name: LocalizedStringResource {
        switch self {
        case .cash: "Cash"
        case .bankAccount: "Bank Account"
        case .eWallet: "E-Wallet"
        case .savings: "Savings Deposit"
        case .stock: "Stocks"
        case .fund: "Fund Certificates"
        case .gold: "Gold"
        case .crypto: "Crypto"
        case .property: "Property"
        case .vehicle: "Vehicle"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .cash: "banknote.fill"
        case .bankAccount: "building.columns.fill"
        case .eWallet: "iphone.gen3"
        case .savings: "dollarsign.bank.building.fill"
        case .stock: "chart.line.uptrend.xyaxis"
        case .fund: "chart.pie.fill"
        // Stacked bars.
        case .gold: "square.stack.3d.up.fill"
        case .crypto: "bitcoinsign.circle.fill"
        case .property: "house.fill"
        // Most people in Vietnam ride a motorbike.
        case .vehicle: "scooter"
        case .other: "shippingbox.fill"
        }
    }

    var color: Color {
        switch self {
        case .cash: .green
        case .bankAccount: .blue
        case .eWallet: .pink
        case .savings: .teal
        case .stock: .indigo
        case .fund: .cyan
        case .gold: .orange
        case .crypto: .purple
        case .property: .brown
        case .vehicle: .mint
        case .other: .gray
        }
    }

    /// What a quantity of shares, fund units or coins is called.
    var quantityName: LocalizedStringResource {
        switch self {
        case .stock: "Shares"
        case .fund: "Units"
        default: "Quantity"
        }
    }

    /// An example of a ticker, for the name field of shares, fund certificates and coins.
    var tickerExample: String {
        switch self {
        case .fund: "E1VFVN30"
        case .crypto: "BTC"
        default: "FPT"
        }
    }
}

extension AssetKind.Group {
    var name: LocalizedStringResource {
        switch self {
        case .money: "Money"
        case .investments: "Investments"
        case .things: "Property & Belongings"
        }
    }
}

extension GoldUnit {
    var name: LocalizedStringResource {
        switch self {
        case .luong: "lượng"
        case .chi: "chỉ"
        case .gram: "gram"
        }
    }

    /// For a price by weight, as in "148.500.000 ₫ per lượng".
    var perName: LocalizedStringResource {
        switch self {
        case .luong: "per lượng"
        case .chi: "per chỉ"
        case .gram: "per gram"
        }
    }

    /// A weight in this unit, such as "5 chỉ". `number` is already formatted.
    func weight(_ number: String) -> LocalizedStringResource {
        switch self {
        case .luong: "\(number) lượng"
        case .chi: "\(number) chỉ"
        case .gram: "\(number) g"
        }
    }
}
