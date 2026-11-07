import RiengtuKit
import SwiftUI

/// What an item from the inbox was for, or what it is when that isn't known.
struct CapturedTitle: View {
    let item: CapturedTransaction

    var body: some View {
        if !item.description.isEmpty {
            Text(verbatim: item.description)
        } else if !item.wasRead, !item.text.isEmpty {
            // The message as it came, on as few lines as it fits, until it's read.
            Text(verbatim: item.text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        } else if item.isTransfer {
            Text("Transfer")
        } else if item.isMoneyIn {
            Text("Money Received")
        } else {
            switch item.source {
            case .bankMessage: Text("Bank Message")
            case .payment: Text("Payment")
            case .screenshot: Text("From a Screenshot")
            case .file: Text("From a File")
            }
        }
    }
}

/// An inbox item's amount: with a plus for money that came in, without a sign for a transfer.
struct CapturedAmount: View {
    let item: CapturedTransaction

    var body: some View {
        Group {
            if let amount = item.amount {
                let code = item.currencyCode ?? Currencies.code(for: .autoupdatingCurrent)
                if item.isTransfer {
                    Text(amount, format: .money(code: code))
                        .foregroundStyle(.secondary)
                } else if item.isMoneyIn {
                    Text(amount, format: .money(code: code).showingPlus())
                        .foregroundStyle(.green)
                } else {
                    Text(-amount, format: .money(code: code))
                }
            } else {
                Text("No Amount")
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

/// An inbox item's symbol: its category's once it's been read, or where it came from before.
struct CapturedIcon: View {
    let item: CapturedTransaction

    var body: some View {
        if !item.wasRead {
            switch item.source {
            case .bankMessage: IconBadge(symbolName: "envelope.fill", color: .gray)
            case .payment: IconBadge(symbolName: "creditcard.fill", color: .gray)
            case .screenshot: IconBadge(symbolName: "photo", color: .gray)
            case .file: IconBadge(symbolName: "doc.text", color: .gray)
            }
        } else if item.isTransfer {
            IconBadge(symbolName: "arrow.left.arrow.right", color: .gray)
        } else if item.isMoneyIn {
            let category = item.incomeCategory ?? .other
            IconBadge(symbolName: category.symbolName, color: category.color)
        } else {
            let category = item.expenseCategory ?? .other
            IconBadge(symbolName: category.symbolName, color: category.color)
        }
    }
}
