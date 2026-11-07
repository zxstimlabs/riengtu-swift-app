import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads photos of a receipt, on the device: Vision finds the text on them (`ScreenshotReader`),
/// in rows (`ReceiptText.rows`), and Apple Intelligence reads what it says, where it's
/// available, checked with the rules (`ReceiptText`), which read it on their own otherwise. The
/// photos are only read, never kept, by the user's choice.
public enum ReceiptReader {
    /// The rows of text on photos of a receipt, such as a long one's pages, in order.
    public static func rows(in photos: [Data]) async throws -> [ReceiptText.Row] {
        var rows: [ReceiptText.Row] = []
        for photo in photos {
            rows += ReceiptText.rows(from: try await ScreenshotReader.read(photo).lines)
        }
        return rows
    }

    /// What a receipt's rows say: as Apple Intelligence reads them where it's available, checked
    /// with the rules, or as the rules read them where it isn't, or can't answer in time.
    public static func read(
        _ rows: [ReceiptText.Row], usingModel: Bool = ExpenseTagger.availability == .available, timeZone: TimeZone = .current
    ) async -> Receipt {
        let rules = ReceiptText.receipt(from: rows, timeZone: timeZone)
        guard usingModel, !rows.isEmpty else { return rules }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let text = rows.map(\.text).joined(separator: "\n")
            let prompt = "Receipt:\n" + text.prefix(maximumLength)
            do {
                let facts = try await ModelQueue.shared.run(within: timeLimit) {
                    try await LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                        .respond(to: prompt, generating: Facts.self, options: TransactionReader.options(maximumTokens: 1_500))
                        .content
                }
                return checked(facts.read, against: rules, text: text, timeZone: timeZone)
            } catch {
                // Such as a language it doesn't support, or no answer in time. The rules read it.
            }
        }
        #endif
        return rules
    }

    /// The longest text read: a long supermarket receipt, within what the model can take in.
    static let maximumLength = 3_000
    /// A receipt is a longer answer than a bank's message, with every item.
    static let timeLimit: Duration = .seconds(90)

    /// What the model read, as it gave it.
    struct Read {
        struct Item {
            var name: String
            var quantity: String?
            var unitPrice: String?
            var amount: String?
        }

        var merchant: String
        var address: String?
        var date: String?
        var items: [Item]
        var subtotal: String?
        var discount: String?
        var tax: String?
        var total: String?
        var currency: String?
        var reference: String?
        var paymentMethod: String?
    }

    /// What the model read, checked: a name must be written on the receipt, and an amount must
    /// be a price it prints, in the currency it prints. The rules' totals, found by their labels, are taken over the
    /// model's, which sometimes gives the cash handed over; its items, and its shop, over the
    /// rules', since it reads names better.
    static func checked(_ read: Read, against rules: Receipt, text: String, timeZone: TimeZone) -> Receipt {
        // The currency the receipt prints, over the model's.
        let code = ReceiptText.statedCurrencyCode(in: text)
            ?? read.currency.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.flatMap { Currencies.all.contains($0) ? $0 : nil }
            ?? rules.currencyCode
        let digits = Currencies.fractionDigits(for: code)
        let prices = ReceiptText.prices(in: text, fractionDigits: digits)
        func number(_ text: String?) -> Decimal? {
            text.flatMap { TransactionText.parseNumber($0.filter { $0.isNumber || $0 == "." || $0 == "," }, fractionDigits: digits) }
        }
        func price(_ text: String?) -> Decimal? {
            number(text).flatMap { $0 > 0 && prices.contains($0) ? $0 : nil }
        }
        func written(_ name: String?) -> String? {
            name.flatMap { TransactionText.isWritten($0, in: text) ? Tags.tidy($0) : nil }
        }

        var receipt = Receipt(currencyCode: code)
        receipt.merchant = written(read.merchant) ?? rules.merchant
        receipt.address = written(read.address) ?? rules.address
        receipt.date = read.date.flatMap { TransactionText.read($0, timeZone: timeZone).date } ?? rules.date
        let items = read.items.compactMap { item -> Receipt.Item? in
            guard let name = written(item.name) else { return nil }
            return Receipt.Item(
                name: name,
                quantity: number(item.quantity).flatMap { $0 > 0 && $0 < 1_000 ? $0 : nil },
                unitPrice: price(item.unitPrice),
                amount: price(item.amount)
            )
        }
        receipt.items = items.isEmpty ? rules.items : items
        receipt.reference = written(read.reference).map { $0.replacingOccurrences(of: " ", with: "") } ?? rules.reference
        receipt.paymentMethod = written(read.paymentMethod) ?? rules.paymentMethod
        receipt.subtotal = rules.subtotal ?? price(read.subtotal)
        receipt.discount = rules.discount ?? price(read.discount)
        receipt.tax = rules.tax ?? price(read.tax)
        receipt.total = rules.total ?? price(read.total)
        return receipt
    }

    static let instructions = """
        You read the text of a shop's or restaurant's receipt, as found on a photo, one row per \
        line, and pull out what it says: the shop's name, its address, when it was printed, each \
        item bought with its quantity, the price of one and what the line came to, and the \
        subtotal, discount, tax and total, the receipt's number or the payment's reference, and \
        how it was paid, such as cash, a card or a QR code. Copy names as printed, in the receipt's language; \
        don't translate them. Give amounts as digits, with a dot only before decimals. Leave out \
        what the receipt doesn't say. Receipts are often in Vietnamese: Tổng cộng, Tổng tiền or \
        Thanh toán is the total; Tạm tính or Tổng tiền hàng the subtotal; Giảm giá or Chiết khấu \
        a discount; VAT or Thuế the tax; SL the quantity; Đơn giá the price of one; Thành tiền \
        what the line came to. Tiền khách đưa is the cash handed over and Tiền thừa the change, \
        which aren't the total or items.
        """

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct Facts {
        @Guide(description: "The shop's or restaurant's name, as printed at the top.")
        var merchant: String
        @Guide(description: "Its address, as printed, if the receipt gives one.")
        var address: String?
        @Guide(description: "When it was printed, as written, such as 06/11/2026 12:30.")
        var date: String?
        @Guide(description: "Each item bought, in order. Not the totals, the payment or the change.")
        var items: [Item]
        @Guide(description: "The total before any discount and tax, digits only.")
        var subtotal: String?
        @Guide(description: "The discount, digits only.")
        var discount: String?
        @Guide(description: "The tax or VAT, digits only.")
        var tax: String?
        @Guide(description: "What was paid in all, digits only. Not the cash handed over, or the change.")
        var total: String?
        @Guide(description: "The amounts' ISO 4217 currency code, such as VND or USD.")
        var currency: String?
        @Guide(description: "The receipt's number, or the payment's reference code, as printed.")
        var reference: String?
        @Guide(description: "How it was paid, as printed, such as Tiền mặt, Thẻ Visa or VietQR.")
        var paymentMethod: String?

        @Generable
        struct Item {
            @Guide(description: "The item's name, as printed.")
            var name: String
            @Guide(description: "How many, digits only.")
            var quantity: String?
            @Guide(description: "The price of one, digits only.")
            var unitPrice: String?
            @Guide(description: "What the line came to, digits only.")
            var amount: String?
        }

        var read: Read {
            Read(
                merchant: merchant, address: address, date: date,
                items: items.map { Read.Item(name: $0.name, quantity: $0.quantity, unitPrice: $0.unitPrice, amount: $0.amount) },
                subtotal: subtotal, discount: discount, tax: tax, total: total, currency: currency,
                reference: reference, paymentMethod: paymentMethod
            )
        }
    }
    #endif
}
