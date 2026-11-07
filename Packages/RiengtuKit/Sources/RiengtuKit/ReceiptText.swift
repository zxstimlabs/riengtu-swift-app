import Foundation

/// Reads a receipt's text, as Vision found it on a photo (`ReceiptReader`), by general rules,
/// not one shop's layout: rows from where the lines are, items as rows that end in a price, and
/// the totals by their labels ("Tổng cộng", "Total", "VAT"). Apple Intelligence reads receipts
/// better where it's available; these rules check what it read, and read them on their own
/// otherwise.
public enum ReceiptText {
    /// One row across the receipt: its pieces of text, left to right.
    public struct Row: Equatable, Sendable {
        public var cells: [String]

        public init(cells: [String]) {
            self.cells = cells
        }

        public var text: String { cells.joined(separator: "  ") }
    }

    /// The lines Vision found, in rows: a line whose middle is within a row's height is on that
    /// row, such as a price printed on the right of its item.
    public static func rows(from lines: [ScreenshotText.Line]) -> [Row] {
        var rows: [(minY: Double, maxY: Double, lines: [ScreenshotText.Line])] = []
        for line in lines.sorted(by: { $0.minY < $1.minY }) {
            let middle = (line.minY + line.maxY) / 2
            if let last = rows.indices.last, middle >= rows[last].minY, middle <= rows[last].maxY {
                rows[last].lines.append(line)
            } else {
                rows.append((line.minY, line.maxY, [line]))
            }
        }
        return rows.map { Row(cells: $0.lines.sorted { $0.minX < $1.minX }.map(\.text)) }
    }

    /// What the rules read from a receipt's rows.
    public static func receipt(from rows: [Row], timeZone: TimeZone = .current) -> Receipt {
        let text = rows.map(\.text).joined(separator: "\n")
        let currencyCode = statedCurrencyCode(in: text) ?? "VND"
        let digits = Currencies.fractionDigits(for: currencyCode)
        var receipt = Receipt(currencyCode: currencyCode)
        receipt.date = TransactionText.read(text, timeZone: timeZone).date

        // The summary: what the rows from the first total-like label say.
        var summaryStart: Int?
        for (index, row) in rows.enumerated() {
            let folded = TransactionText.fold(row.text)
            guard let label = summaryLabel(of: folded) else { continue }
            if label == .payment {
                summaryStart = summaryStart ?? index
                if receipt.paymentMethod.isEmpty, let method = paymentMethod(of: row.text, folded: folded) {
                    receipt.paymentMethod = method
                }
                continue
            }
            guard let value = trailingNumbers(of: row.text, fractionDigits: digits).numbers.last(where: { !$0.isQuantity })?.value
            else { continue }
            summaryStart = summaryStart ?? index
            switch label {
            case .subtotal: receipt.subtotal = value
            case .discount: receipt.discount = value
            case .tax: receipt.tax = value
            // The last, such as "Thanh toán" after "Tổng cộng" and a discount, is what was paid.
            case .total: receipt.total = value
            case .payment: break
            }
        }

        let top = rows.prefix(6)
        receipt.merchant = top.first(where: isMerchant).map { Tags.tidy($0.text) } ?? ""
        receipt.address = top.lazy.compactMap { address(of: $0) }.first ?? ""
        receipt.reference = rows.lazy.compactMap { reference(of: $0.text) }.first ?? ""
        receipt.items = items(in: Array(rows.prefix(summaryStart ?? rows.count)), fractionDigits: digits)
        return receipt
    }

    // MARK: Items

    /// Each row that ends in a price, or a name whose quantity and price are on the row below,
    /// as supermarkets print them.
    static func items(in rows: [Row], fractionDigits: Int) -> [Receipt.Item] {
        var items: [Receipt.Item] = []
        var index = rows.startIndex
        while index < rows.endIndex {
            let text = rows[index].text
            let folded = TransactionText.fold(text)
            defer { index += 1 }
            guard !startsWithLabel(folded) else { continue }
            if let item = item(from: text, fractionDigits: fractionDigits) {
                items.append(item)
            } else if letterCount(text) >= 2, index + 1 < rows.endIndex, letterCount(rows[index + 1].text.filter { $0 != "x" && $0 != "X" }) == 0,
                      var item = item(from: "_ " + rows[index + 1].text, fractionDigits: fractionDigits) {
                item.name = itemName(from: text)
                items.append(item)
                index += 1
            }
        }
        return items
    }

    /// An item, from a row such as "Phin Sữa Đá  2  29.000  58.000": its name, then a quantity,
    /// the price of one, and what the line came to, as far as the row gives them.
    static func item(from text: String, fractionDigits: Int) -> Receipt.Item? {
        let (numbers, separators) = trailingNumbers(of: text, fractionDigits: fractionDigits)
        let prices = numbers.filter { !$0.isQuantity }.map(\.value)
        guard let amount = prices.last, amount >= minimumPrice(fractionDigits) else { return nil }
        var tokens = text.split(whereSeparator: \.isWhitespace)
        tokens.removeLast(numbers.count + separators)
        let name = itemName(from: tokens.joined(separator: " "))
        guard letterCount(name) >= 2 || name == "_" else { return nil }
        return Receipt.Item(
            name: name == "_" ? "" : name,
            quantity: numbers.first(where: \.isQuantity)?.value,
            unitPrice: prices.count > 1 ? prices[prices.count - 2] : nil,
            amount: amount
        )
    }

    /// A name without an item's number in front of it, such as "1." or "01".
    private static func itemName(from text: String) -> String {
        let trimmed = text.replacingOccurrences(of: #"^\s*\d{1,3}[.)\-]?\s+(?=\p{L})"#, with: "", options: .regularExpression)
        return Tags.tidy(trimmed)
    }

    private static func letterCount(_ text: String) -> Int {
        text.count(where: \.isLetter)
    }

    /// Less than this isn't a price, but a quantity or a number in a name.
    private static func minimumPrice(_ fractionDigits: Int) -> Decimal {
        fractionDigits == 0 ? 100 : Decimal(string: "0.01")!
    }

    // MARK: Numbers

    struct Number {
        var value: Decimal
        /// A count, such as "2" or "x2", rather than money.
        var isQuantity: Bool
    }

    /// The numbers at the end of a row, in order: prices and quantities, and how many "x" were
    /// between them.
    static func trailingNumbers(of text: String, fractionDigits: Int) -> (numbers: [Number], separatorCount: Int) {
        var numbers: [Number] = []
        var separators = 0
        for token in text.split(whereSeparator: \.isWhitespace).reversed() {
            if token == "x" || token == "X" || token == "×" || token == "@" {
                separators += 1
            } else if let quantity = quantity(token) {
                numbers.insert(Number(value: quantity, isQuantity: true), at: 0)
            } else if let price = price(token, fractionDigits: fractionDigits) {
                numbers.insert(Number(value: price, isQuantity: false), at: 0)
            } else {
                break
            }
            if numbers.count == 4 { break }
        }
        return (numbers, separators)
    }

    /// A count: "2", "x2", "2x".
    static func quantity(_ token: Substring) -> Decimal? {
        let digits = token.trimmingCharacters(in: CharacterSet(charactersIn: "xX×"))
        guard (1...2).contains(digits.count), digits.allSatisfy(\.isNumber), !digits.hasPrefix("0"),
              digits.count == token.count || token.count == digits.count + 1
        else { return nil }
        return Decimal(string: digits)
    }

    /// A number as a receipt prints money: "58.000", "58,000", "58000", "58.000đ", "29K", "$5.25".
    /// Not a phone number, a code, a time or a date.
    static func price(_ token: Substring, fractionDigits: Int) -> Decimal? {
        var text = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "₫$€đĐ:"))
        for code in ["VNĐ", "VND", "vnd", "USD", "EUR"] where text.hasSuffix(code) || text.hasPrefix(code) {
            text = text.replacingOccurrences(of: code, with: "")
        }
        var multiplier: Decimal = 1
        if fractionDigits == 0, text.hasSuffix("k") || text.hasSuffix("K") {
            multiplier = 1_000
            text.removeLast()
        }
        guard text.range(of: #"^(?:\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)$"#, options: .regularExpression) != nil,
              !(text.hasPrefix("0") && text.count > 1 && !text.hasPrefix("0.") && !text.hasPrefix("0,"))
        else { return nil }
        return TransactionText.parseNumber(text, fractionDigits: fractionDigits).map { $0 * multiplier }
    }

    /// Every price a receipt's text gives, for checking what the model read.
    static func prices(in text: String, fractionDigits: Int) -> Set<Decimal> {
        Set(text.split(whereSeparator: { $0.isWhitespace || $0 == "|" }).compactMap { price($0, fractionDigits: fractionDigits) })
            .union(TransactionText.numbers(in: text))
    }

    /// The currency the receipt prints with its amounts, if it does: "đ", "VND", "$", "€".
    static func statedCurrencyCode(in text: String) -> String? {
        if let code = TransactionText.amounts(in: text).first?.currencyCode { return code }
        if text.contains("$") { return "USD" }
        if text.contains("€") { return "EUR" }
        return nil
    }

    // MARK: Labels

    enum SummaryLabel {
        case subtotal, discount, tax, total
        /// How it was paid, and the change: not part of what was bought.
        case payment
    }

    /// What a row of the totals is, by its label at the start, in folded text. A subtotal's
    /// labels are checked before a total's, since "tong tien hang" starts like "tong tien".
    static func summaryLabel(of folded: String) -> SummaryLabel? {
        let labels: [(SummaryLabel, [String])] = [
            (.subtotal, ["tam tinh", "tong tien hang", "cong tien hang", "tien hang", "subtotal", "sub total", "sub-total"]),
            (.discount, ["giam gia", "chiet khau", "khuyen mai", "voucher", "discount"]),
            (.tax, ["vat", "thue", "gtgt", "tax"]),
            (.payment, ["tien khach dua", "khach dua", "tien thua", "tien thoi", "tra lai", "change"] + paymentMethods),
            (.total, ["tong thanh toan", "tong cong", "tong tien", "tong", "thanh toan", "khach phai tra", "can thanh toan",
                      "grand total", "total", "amount due"]),
        ]
        let start = folded.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        for (label, words) in labels where words.contains(where: { start.hasPrefix($0) && !start.dropFirst($0.count).prefix(1).contains(where: \.isLetter) }) {
            return label
        }
        return nil
    }

    /// How a receipt says it was paid, folded, at the start of a row.
    private static let paymentMethods = [
        "tien mat", "cash", "the tin dung", "the ghi no", "thanh toan the", "thanh toan qr", "card", "visa", "mastercard",
        "master card", "jcb", "amex", "momo", "zalopay", "vnpay", "shopeepay", "vietqr", "qr code", "chuyen khoan",
    ]

    /// How it was paid, as printed: the label of a row such as "TIỀN MẶT  100.000".
    private static func paymentMethod(of text: String, folded: String) -> String? {
        guard paymentMethods.contains(where: { folded.hasPrefix($0) }) else { return nil }
        var tokens = text.split(whereSeparator: \.isWhitespace)
        let (numbers, separators) = trailingNumbers(of: text, fractionDigits: 0)
        tokens.removeLast(min(tokens.count, numbers.count + separators))
        let label = Tags.tidy(tokens.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ":")))
        return label.isEmpty ? nil : label
    }

    /// The receipt's number, after a label such as "Số HĐ:" or "Mã giao dịch:": the first word
    /// with a digit.
    private static func reference(of text: String) -> String? {
        let folded = TransactionText.fold(text)
        let labels = ["so hoa don", "so hd", "ma hoa don", "ma hd", "ma giao dich", "ma gd", "receipt no", "invoice no", "bill no",
                      "order no", "receipt #", "invoice #", "order #"]
        guard let label = labels.first(where: { folded.hasPrefix($0) }) else { return nil }
        return text.dropFirst(label.count)
            .split { $0.isWhitespace || $0 == ":" || $0 == "|" }
            .first { $0.contains(where: \.isNumber) }
            .map(String.init)
    }

    /// Rows about the shop or the bill, not an item: "ĐT: 028…", "Số HĐ: 0001", "Bàn: 5".
    private static func startsWithLabel(_ folded: String) -> Bool {
        let start = folded.trimmingCharacters(in: .whitespaces)
        return ["dt", "tel", "hotline", "mst", "so hd", "hd", "ban", "thu ngan", "nhan vien", "ngay", "gio", "ma", "so", "khach",
                "dia chi", "d/c", "dc", "wifi", "pass", "address", "phone", "date", "time", "table", "cashier", "order"]
            .contains { start.hasPrefix($0) && !start.dropFirst($0.count).prefix(1).contains(where: \.isLetter) }
    }

    /// The shop's name: near the top, with letters, and not the receipt's heading or a label.
    private static func isMerchant(_ row: Row) -> Bool {
        let folded = TransactionText.fold(row.text)
        let words = folded.split { !$0.isLetter }
        let headings: Set<Substring> = ["hoa", "don", "ban", "hang", "phieu", "thanh", "toan", "tam", "tinh", "gtgt", "bill",
                                        "receipt", "invoice", "tax", "lien", "chi", "tiet"]
        return letterCount(row.text) >= 3 && !words.allSatisfy(headings.contains) && !startsWithLabel(folded)
            && summaryLabel(of: folded) == nil && address(of: row) == nil
    }

    /// The shop's address: after a label such as "Địa chỉ:", or a row with a street's words.
    private static func address(of row: Row) -> String? {
        let text = row.text
        let folded = TransactionText.fold(text)
        if let label = ["dia chi", "d/c", "dc", "address", "add"].first(where: { folded.hasPrefix($0) }),
           !folded.dropFirst(label.count).prefix(1).contains(where: \.isLetter) {
            let value = text.dropFirst(label.count).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":.")))
            return value.isEmpty ? nil : Tags.tidy(value)
        }
        let words = Set(folded.split { !$0.isLetter && $0 != "." }.map(String.init))
        let streetWords: Set<String> = ["duong", "phuong", "quan", "huyen", "p.", "q.", "tp", "tp.", "street", "st.", "ward", "district"]
        return text.contains(where: \.isNumber) && !words.isDisjoint(with: streetWords) ? Tags.tidy(text) : nil
    }
}
