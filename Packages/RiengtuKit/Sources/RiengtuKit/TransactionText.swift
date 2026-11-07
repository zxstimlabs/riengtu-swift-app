import Foundation

/// Reads a bank's email or message about a transaction with fixed rules: the amount, whether
/// money went out or came in, when, and what for.
///
/// Rules, not a model, so it works anywhere, even in the background while the device is locked.
/// It's written for the way Vietnamese banks word their notices, in Vietnamese and English, but
/// knows no bank's format exactly. `TransactionReader` reads the same text with the model, where
/// Apple Intelligence is available.
public enum TransactionText {
    public enum Direction: String, Codable, Sendable {
        case moneyOut, moneyIn
    }

    public struct Reading: Equatable, Sendable {
        public var amount: Decimal?
        public var currencyCode: String?
        /// `nil` when the text doesn't say.
        public var direction: Direction?
        public var date: Date?
        /// What the transaction was for, as the text writes it, such as the "Nội dung" of a
        /// transfer. Empty when it doesn't say.
        public var description: String

        public init(
            amount: Decimal? = nil, currencyCode: String? = nil, direction: Direction? = nil,
            date: Date? = nil, description: String = ""
        ) {
            self.amount = amount
            self.currencyCode = currencyCode
            self.direction = direction
            self.date = date
            self.description = description
        }
    }

    /// The longest description kept, so a whole paragraph doesn't become a note.
    static let descriptionMaximumLength = 100

    public static func read(_ text: String, timeZone: TimeZone = .current) -> Reading {
        let text = text.precomposedStringWithCanonicalMapping
        var reading = Reading()
        if let amount = bestAmount(in: text) {
            reading.amount = amount.value
            reading.currencyCode = amount.currencyCode
            reading.direction = amount.direction
        }
        reading.direction = reading.direction ?? direction(in: fold(text))
        reading.date = date(in: text, timeZone: timeZone)
        reading.description = description(in: text)
        return reading
    }

    // MARK: Amounts

    struct Amount {
        var value: Decimal
        var currencyCode: String
        /// Where it is, in the text with its characters precomposed.
        var start: String.Index
        var end: String.Index
        var direction: Direction?
        /// Whether a + or − says the direction.
        var isSigned: Bool
        /// Whether it's after a word such as "số dư", so it's the balance, not what moved.
        var isBalance: Bool
        var score: Int
    }

    private static let number = #"(?<![\d.,])(?:\d{1,3}(?:[., \u00A0\u202F]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    private static let currency = #"VNĐ|VND|đồng|dong|đ|₫|USD|US\$|\$|EUR|€"#

    /// A number then its currency, such as "-150,000 VND", or a currency then its number, such as
    /// "VND 150,000", "VND -150,000", "- VND 150,000" (Techcombank) or "$12.50".
    ///
    /// A currency in brackets can come before a sign, as ACB writes "TK 123456789(VND) - 100,000".
    private static let amountPattern = regex(
        #"(?<sign1>"# + sign + #")?"# + space + #"(?<number1>"# + number + #")"# + space + #"(?<currency1>"# + currency + #")(?!\p{L})"#
            + #"|(?:(?<sign3>"# + sign + #")"# + space + #")?(?<!\p{L})(?<currency2>"# + currency + #")(?:\)"# + space + #"(?="# + sign + #"))?"#
            + space + #"(?<sign2>"# + sign + #")?"# + space + #"(?<number2>"# + number + #")(?!\d)"#
    )

    /// A plus, or a minus as banks and Vision write it: a hyphen, a minus sign, an en or em dash,
    /// or a full-width one.
    private static let sign = #"[+\-−–—－]"#
    private static let space = #"[ \u00A0\u202F\t]*"#

    private static func isPlus(_ sign: String) -> Bool {
        sign == "+"
    }

    /// A label for an amount or a balance, then a number with no currency: "Số tiền GD: - 33,000",
    /// "Số dư: 18,384,880". Matched in folded text, which keeps one character for each.
    private static let labeledAmountPattern = regex(
        #"(?<!\p{L})(?:so tien(?: gd| giao dich)?|so du(?: kha dung)?|ps|phat sinh(?: no| co)?|ghi no|ghi co|rut|nop|amount|balance|debit|credit|withdrawal|deposit)\s*[:：]?\s*(?<sign4>"# + sign + #")?\s*(?<number4>"#
            + number + #")(?![\d.,]*\s*(?:"# + currency + #"))"#
    )

    /// The amount that moved, not the balance: one with a sign, or after words like "số tiền",
    /// wins over one after "số dư".
    private static func bestAmount(in text: String) -> Amount? {
        var best: Amount?
        for amount in amounts(in: text) where best.map({ amount.score > $0.score }) ?? true {
            best = amount
        }
        return best
    }

    /// Every amount in the text with its currency, in order.
    static func amounts(in text: String) -> [Amount] {
        let text = text.precomposedStringWithCanonicalMapping
        let withCurrency = matches(of: amountPattern, in: text)
        // A number after a label such as "Số tiền GD:", without its currency, as Techcombank's
        // history writes them, is in đồng. Not where the label's amount has its currency.
        let folded = fold(text)
        let labeled = matches(of: labeledAmountPattern, in: folded).map { match in
            // The same place in `text`, since folding keeps one character for each, starting at
            // the number, so the label is among the words before it.
            var match = match
            let end = folded.distance(from: folded.startIndex, to: match.end)
            match.end = text.index(text.startIndex, offsetBy: end)
            match.start = text.index(match.end, offsetBy: -(match["number4"]?.count ?? 0))
            return match
        }.filter { label in
            !withCurrency.contains { $0.start < label.end && label.start < $0.end }
        }
        return (withCurrency + labeled).sorted { $0.start < $1.start }.compactMap { match in
            guard let numberText = match["number1"] ?? match["number2"] ?? match["number4"],
                  let code = (match["currency1"] ?? match["currency2"]).flatMap(currencyCode(for:)) ?? (match["number4"] != nil ? "VND" : nil),
                  let value = parseNumber(numberText, fractionDigits: Currencies.fractionDigits(for: code)),
                  value > 0
            else { return nil }
            let sign = match["sign1"] ?? match["sign2"] ?? match["sign3"] ?? match["sign4"]

            // The words just before the amount say what it is: in the same part of the message,
            // so "số dư" in a heading such as "Thong bao thay doi so du" doesn't make it the
            // balance.
            let from: String.Index = text.index(match.start, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            var window = String(text[from..<match.start])
            if let boundary = window.range(of: #"(?:\n|\. |\||;)(?!.*(?:\n|\. |\||;))"#, options: .regularExpression) {
                window = String(window[boundary.upperBound...])
            }
            let before = fold(window)
            var score = 0
            var direction: Direction?
            if let sign {
                score += 3
                direction = isPlus(sign) ? .moneyIn : .moneyOut
            }
            if lastWord(of: before, in: amountWords) != nil { score += 2 }
            var isBalance = false
            // A balance has no sign.
            if sign == nil, let last = lastWord(of: before, in: balanceWords + amountWords), balanceWords.contains(last) {
                score -= 5
                isBalance = true
            }
            return Amount(
                value: value, currencyCode: code, start: match.start, end: match.end,
                direction: direction ?? self.direction(in: before),
                isSigned: sign != nil, isBalance: isBalance, score: score
            )
        }
    }

    // MARK: Notices for the model

    /// A message as Apple Intelligence reads it: its words as they came, with what the rules can
    /// tell put in as tokens where it was, like "[money out 100000 VND]", "[balance]", "[time]",
    /// "[account]" and "[code]". The model keeps the wording around them, such as "chuyển tiền
    /// đến [account]", but can't take the balance or an account number for the amount, and only
    /// judges what the words mean. The tokens come from general rules, not one bank's format, so
    /// a person can send any bank's notifications with a shortcut of their own.
    public struct Notice: Equatable, Sendable {
        public var amount: Decimal?
        public var currencyCode: String?
        public var direction: Direction?
        /// What a label such as "Nội dung:" says, if one does.
        public var labeledDescription: String?
        /// The message with its tokens.
        public var prompt: String
    }

    /// A card's number as banks hide it: "4 .... .... 1234", "**** 1234".
    private static let cardNumber = regex(#"\d?\s*(?:[.*x•]{2,}\s*)+\d{2,4}"#)
    /// A reference or contract code: letters and digits together, such as "6311ASCB02V2Q9YC".
    private static let code = try! NSRegularExpression(pattern: #"(?<![\p{L}\d])(?=[\p{L}\d]*\d[\p{L}\d]*\d)(?=[\p{L}\d]*\p{L})[\p{L}\d]{6,}(?![\p{L}\d])"#)
    /// Six digits or more: an account, phone or reference number, with what joins its parts.
    private static let longDigits = regex(#"\d{6,}"#)
    private static let timeOnly = regex(#"(?<![\d:])\d{1,2}:\d{2}(?::\d{2})?(?![\d:])"#)

    public static func notice(for text: String) -> Notice {
        let text = text.precomposedStringWithCanonicalMapping
        let all = amounts(in: text)
        let best = bestAmount(in: text)

        // Tokens for parts of the text, earlier ones in this list winning where they overlap.
        var spans: [(range: Range<String.Index>, token: String)] = []
        for amount in all {
            let currency = " " + amount.currencyCode
            let token: String
            if amount.isBalance {
                token = "[balance]"
            } else if let best, amount.start == best.start {
                switch best.direction {
                case .moneyOut: token = "[money out \(amount.value)\(currency)]"
                case .moneyIn: token = "[money in \(amount.value)\(currency)]"
                case nil: token = "[amount \(amount.value)\(currency)]"
                }
            } else {
                token = amount.value == best?.value ? "[the same amount]" : "[another amount \(amount.value)\(currency)]"
            }
            spans.append((amount.start..<amount.end, token))
        }
        for pattern in datePatterns { spans += matches(of: pattern, in: text).map { ($0.start..<$0.end, "[time]") } }
        spans += matches(of: timeOnly, in: text).map { ($0.start..<$0.end, "[time]") }
        spans += matches(of: cardNumber, in: text).map { ($0.start..<$0.end, "[card]") }
        spans += matches(of: code, in: text).map { ($0.start..<$0.end, "[code]") }
        spans += matches(of: longDigits, in: text).map { ($0.start..<$0.end, "[account]") }

        var kept: [(range: Range<String.Index>, token: String)] = []
        for span in spans where !kept.contains(where: { $0.range.overlaps(span.range) }) {
            kept.append(span)
        }
        var prompt = ""
        var index = text.startIndex
        for span in kept.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            prompt += text[index..<span.range.lowerBound] + span.token
            index = span.range.upperBound
        }
        prompt += text[index...]

        return Notice(
            amount: best?.value, currencyCode: best?.currencyCode,
            direction: best?.direction ?? direction(in: fold(text)),
            labeledDescription: labeledDescription(in: text).map(clean).flatMap { $0.isEmpty ? nil : $0 },
            prompt: prompt
        )
    }

    /// The account numbers a message names, such as "TK 793979688" or "Tài khoản: 7929792979".
    static func accounts(in text: String) -> Set<String> {
        let folded = fold(text.precomposedStringWithCanonicalMapping)
        return Set(matches(of: accountNumber, in: folded).compactMap { match in
            String(folded[match.start..<match.end]).filter(\.isNumber).nilIfEmpty
        })
    }

    private static let accountNumber = regex(#"(?<=tai khoan|tk|stk|account|acct)[\s:：#.]*\d{6,}"#)

    /// The reference codes in a message, such as "6311ASCB02V2Q9YC", which both sides of a
    /// transfer often carry.
    static func codes(in text: String) -> Set<String> {
        Set(matches(of: code, in: text).map { String(text[$0.start..<$0.end]).uppercased() })
    }

    /// The balances a message gives.
    static func balances(in text: String) -> Set<Decimal> {
        Set(amounts(in: text).filter(\.isBalance).map(\.value))
    }

    /// The tokens in a model's answer, which aren't words of the message.
    static func withoutTokens(_ text: String) -> String {
        tokenPattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)

    /// Which way the money went, where a + or − in front of the amount says.
    static func statedDirection(in text: String) -> Direction? {
        guard let best = bestAmount(in: text.precomposedStringWithCanonicalMapping), best.isSigned else { return nil }
        return best.direction
    }

    /// A name in capitals, then "chuyen tien" or "chuyen khoan". Case-sensitive for the name.
    private static let defaultTransferContent = try! NSRegularExpression(
        pattern: #"^\p{Lu}+(?:\s+\p{Lu}+)+\s+(?i:chuy[eể]n\s+(?:ti[eề]n|kho[aả]n))$"#
    )

    /// Whether a description is only what the bank writes when the person writes nothing, such
    /// as "NGUYEN VAN AN chuyen tien" for a QR payment: the sender's name, which says nothing
    /// about what the money was for.
    public static func isDefaultTransferContent(_ description: String) -> Bool {
        let text = description.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultTransferContent.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let refundPattern = regex(#"(?<!\p{L})(?:hoan tra|hoan tien|refund(?:ed)?|cashback)(?!\p{L})"#)

    /// Whether the text says it's a refund or cashback, without diacritics, so "hoàn trà", as
    /// Vision sometimes reads "hoàn trả", counts too.
    public static func isRefund(_ text: String) -> Bool {
        let folded = fold(text.precomposedStringWithCanonicalMapping)
        return refundPattern.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
    }

    /// Words that label a line rather than say what the money was for.
    private static let labelWords: Set<String> = [
        "tai khoan", "so tai khoan", "so du", "noi dung", "so tien", "giao dich", "account", "balance", "amount",
    ]

    /// Whether every word of `description` is in `text`, so it wasn't made up, and it isn't only
    /// a label, such as "Tài khoản".
    static func isWritten(_ description: String, in text: String) -> Bool {
        let folded = fold(description.precomposedStringWithCanonicalMapping)
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty, !labelWords.contains(words.joined(separator: " ")) else { return false }
        let foldedText = fold(text.precomposedStringWithCanonicalMapping)
        return words.allSatisfy { foldedText.contains($0) }
    }

    /// Reads an amount given on its own, such as the Amount a Wallet payment passes to Shortcuts,
    /// which is text in the device's format: "45.000 ₫", "₫45,000", "VND 45,000", "฿350.00" or
    /// "45000". Its currency is `nil` when the text doesn't name one, and its value is never below
    /// zero.
    public static func amount(_ text: String) -> (value: Decimal, currencyCode: String?)? {
        let text = text.precomposedStringWithCanonicalMapping
        guard let number = matches(of: numberPattern, in: text).first else { return nil }
        let code = currencyCode(in: text)
        let fractionDigits = code.map { Currencies.fractionDigits(for: $0) } ?? 2
        guard let value = parseNumber(String(text[number.start..<number.end]), fractionDigits: fractionDigits) else {
            return nil
        }
        return (value, code)
    }

    /// The currency an amount's text names with its code, such as "VND", or its symbol.
    private static func currencyCode(in text: String) -> String? {
        for match in matches(of: isoCodePattern, in: text) {
            let code = String(text[match.start..<match.end])
            if Currencies.all.contains(code) { return code }
        }
        if let match = matches(of: symbolPattern, in: text).first {
            return currencyCode(for: String(text[match.start..<match.end]))
        }
        let symbols = otherCurrencySymbols.filter { text.contains($0.key) }
        return symbols.max { $0.key.count < $1.key.count }?.value
    }

    private static let numberPattern = regex(number)
    /// Case-sensitive, so "all" isn't read as Albania's lek.
    private static let isoCodePattern = try! NSRegularExpression(pattern: #"(?<!\p{L})\p{Lu}{3}(?!\p{L})"#)
    /// Not after a letter, so the "$" of "CA$" isn't read as the US dollar.
    private static let symbolPattern = regex(#"(?<!\p{L})(?:"# + currency + #")(?!\p{L})"#)

    /// The symbols English, Vietnamese and the device's language write other currencies with,
    /// such as "฿", "£" and "CA$", for an amount from a payment abroad. A symbol that stands for
    /// more than one currency is left out. Made only when an amount has a symbol `currency`
    /// doesn't know, since it takes a formatter for every currency.
    private static let otherCurrencySymbols: [String: String] = {
        var symbols: [String: String] = [:]
        var shared: Set<String> = []
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "vi_VN"), Locale.current] {
            for code in Currencies.all {
                let symbol = Currencies.symbol(for: code, locale: locale)
                guard symbol != code else { continue }
                if let existing = symbols[symbol], existing != code { shared.insert(symbol) }
                symbols[symbol] = code
            }
        }
        return symbols.filter { !shared.contains($0.key) }
    }()

    private static let amountWords = [
        "so tien", "so tien giao dich", "ps", "phat sinh", "giao dich", "gd", "thanh toan", "chuyen",
        "amount", "transaction", "payment", "paid", "debit", "credit", "ghi no", "ghi co",
    ]
    /// A credit card's available limit ("hạn mức khả dụng") is like a balance.
    private static let balanceWords = ["so du", "sd", "so du kha dung", "balance", "available balance", "kha dung", "han muc"]

    private static func currencyCode(for symbol: String) -> String? {
        switch symbol.lowercased() {
        case "vnđ", "vnd", "đồng", "dong", "đ", "₫": "VND"
        case "usd", "us$", "$": "USD"
        case "eur", "€": "EUR"
        default: nil
        }
    }

    /// Reads "150,000", "150.000", "1 250 000" or "12.50": a separator followed by one or two
    /// digits at the end starts the fraction, and any other separator groups digits.
    static func parseNumber(_ text: String, fractionDigits: Int) -> Decimal? {
        let separators: Set<Character> = [".", ",", " ", "\u{00A0}", "\u{202F}"]
        var whole = text
        var fraction = ""
        if let last = text.lastIndex(where: separators.contains) {
            let tail = text[text.index(after: last)...]
            if tail.count <= 2 {
                whole = String(text[..<last])
                fraction = String(tail)
            }
        }
        let digits = whole.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let kept = fractionDigits > 0 && !fraction.isEmpty ? "." + fraction.prefix(fractionDigits) : ""
        return Decimal(string: digits + kept, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: Direction

    private static let moneyOutWords = [
        "ghi no", "debit", "debited", "thanh toan", "chuyen di", "chuyen khoan di", "da chuyen",
        "rut tien", "withdrawal", "payment", "paid", "purchase", "giam",
    ]
    private static let moneyInWords = [
        "ghi co", "credit", "credited", "nhan tien", "da nhan", "nhan duoc", "received", "deposit", "tang",
    ]

    /// Whether `folded` text says money went out or came in, from the last such word in it.
    private static func direction(in folded: String) -> Direction? {
        guard let last = lastWord(of: folded, in: moneyOutWords + moneyInWords) else { return nil }
        return moneyInWords.contains(last) ? .moneyIn : .moneyOut
    }

    // MARK: Dates

    private static let time = #"(?<hour>\d{1,2})[:h](?<minute>\d{2})(?::(?<second>\d{2}))?"#
    private static let dayFirst = #"(?<day>\d{1,2})[/\-.](?<month>\d{1,2})[/\-.](?<year>\d{4})"#
    private static let datePatterns = [
        regex(time + #"\D{1,8}?"# + dayFirst),
        regex(#"(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})(?:[ T]"# + time + ")?"),
        regex(dayFirst + #"(?:\D{1,8}?"# + time + ")?"),
    ]

    /// The first date in the text, day first as in Vietnam: "05/11/2026 12:30", "12:30
    /// 05-11-2026" or "2026-11-05 12:30".
    private static func date(in text: String, timeZone: TimeZone) -> Date? {
        let first = datePatterns
            .compactMap { matches(of: $0, in: text).first }
            .min { $0.start < $1.start }
        guard let match = first,
              let day = match["day"].flatMap({ Int($0) }),
              let month = match["month"].flatMap({ Int($0) }),
              let year = match["year"].flatMap({ Int($0) }),
              (1...31).contains(day), (1...12).contains(month)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: match["hour"].flatMap { Int($0) } ?? 0,
            minute: match["minute"].flatMap { Int($0) } ?? 0,
            second: match["second"].flatMap { Int($0) } ?? 0
        )
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }

    // MARK: Descriptions

    /// Labels for what a transaction was for, best first.
    private static let descriptionLabels = [
        "noi dung giao dich", "noi dung chuyen khoan", "noi dung", "nd", "dien giai", "mo ta",
        "description", "content", "remark", "memo", "details",
        "merchant", "nguoi nhan", "ten nguoi nhan", "tai", "beneficiary", "beneficiary name", "to",
        // ACB's "GD:", though MB's "GD:" gives the amount, which isn't kept as a description.
        "gd",
    ].map { regex(#"(?:^|[^\p{L}])"# + NSRegularExpression.escapedPattern(for: $0) + #"\s*[:：]\s*"#) }

    /// The text after a label such as "Nội dung:" or "ND:", to the end of its line. Without one,
    /// the line after the balance, where app notifications such as Techcombank's put it.
    private static func description(in text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return labeledDescription(in: lines) ?? descriptionAfterBalance(in: lines) ?? ""
    }

    /// Whether a description is only an amount, such as MB's "GD: -500,000VND", or
    /// Techcombank's "Số tiền GD: - 2,042,000": digits, and no letters but a currency's.
    private static func isOnlyAnAmount(_ text: String) -> Bool {
        text.contains(where: \.isNumber) && !text.contains { $0.isLetter && !"VNDvndđĐ".contains($0) }
    }

    // MARK: Messages that aren't transactions

    /// Whether a bank's message tells of money that moved, where that's plain, since banks send
    /// ads, offers, one-time codes and reminders the same way: `true` for one with an amount with
    /// a + or −, or a balance, which those don't give; `false` for one without digits, for the
    /// amount, such as an ad asking to link a card. `nil` otherwise, for Apple Intelligence to
    /// tell (`TransactionReader.isTransaction`), or without it, `looksLikeOtherMessage`.
    public static func isTransaction(_ text: String) -> Bool? {
        let text = text.precomposedStringWithCanonicalMapping
        guard text.contains(where: \.isWholeNumber) else { return false }
        if amounts(in: text).contains(where: { $0.isSigned || $0.isBalance }) { return true }
        return nil
    }

    /// Whether a message that isn't plainly a transaction (`isTransaction`) has the words of an
    /// ad, an offer, a one-time code or a reminder (`otherMessagePattern`), or a percentage or a
    /// link, outside what a label such as "Nội dung" says the money was for, which the sender
    /// wrote. For where Apple Intelligence can't tell.
    public static func looksLikeOtherMessage(_ text: String) -> Bool {
        let folded = fold(withoutLabeledDescriptions(text))
        return otherMessagePattern.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
    }

    /// The text without what labels such as "Nội dung" say the money was for, which whoever sent
    /// it wrote, so it doesn't make a transaction look like an ad: "Nội dung: …".
    static func withoutLabeledDescriptions(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let line = String(line)
            let folded = fold(line)
            guard let label = descriptionLabels.compactMap({ matches(of: $0, in: folded).first }).min(by: { $0.end < $1.end })
            else { return line }
            // Folding keeps one character for each, so the offset carries over to the line.
            let start = line.index(line.startIndex, offsetBy: folded.distance(from: folded.startIndex, to: label.end))
            let end = line[start...].firstIndex { "|;".contains($0) } ?? line.endIndex
            return line[..<start] + " …" + line[end...]
        }.joined(separator: "\n")
    }

    /// Words of an ad or an offer, a one-time code, or a reminder of a bill or a statement, in
    /// folded text, and a percentage or a link.
    private static let otherMessagePattern = regex(
        #"(?<!\p{L})(?:"# + [
            // Ads and offers.
            "uu dai", "khuyen mai", "voucher", "ma giam gia", "giam ngay", "giam den", "giam toi", "hoan tien den",
            "hoan den", "hoan toi", "toi da", "len den", "chi tu", "mien phi", "dang ky", "lien ket", "mo the",
            "mo tai khoan", "chuong trinh", "ap dung", "offer", "promotion", "promo", "discount", "cashback", "up to",
            "sign up",
            // One-time codes.
            "otp", "ma xac thuc", "ma xac nhan", "khong chia se", "khong cung cap", "one-time", "verification code",
            // Reminders and statements.
            "sao ke", "han thanh toan", "den han", "qua han", "nhac", "thanh toan toi thieu", "statement",
            "due date", "payment due", "minimum payment",
        ].joined(separator: "|") + #")(?!\p{L})|%|https?://|www\."#
    )

    /// Every number in the text, as the model may give one: amounts, balances, and others.
    static func numbers(in text: String) -> Set<Decimal> {
        Set(matches(of: numberPattern, in: text.precomposedStringWithCanonicalMapping).flatMap { match -> [Decimal] in
            let text = String(text.precomposedStringWithCanonicalMapping[match.start..<match.end])
            return [0, 2].compactMap { parseNumber(text, fractionDigits: $0) }
        })
    }

    /// What a label such as "Nội dung:" says the money was for, if the text has one.
    static func labeledDescription(in text: String) -> String? {
        labeledDescription(in: text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isNewline).map(String.init))
    }

    private static func labeledDescription(in lines: [String]) -> String? {
        var best: (rank: Int, value: String)?
        for line in lines {
            let folded = fold(line)
            for (rank, label) in descriptionLabels.enumerated() where best.map({ rank < $0.rank }) ?? true {
                guard let match = matches(of: label, in: folded).first else { continue }
                // Folding keeps one character for each, so the offset carries over to the line.
                let offset = folded.distance(from: folded.startIndex, to: match.end)
                let value = line.dropFirst(offset)
                    .prefix { !"|;".contains($0) }
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(["(", ")"])))
                let cleaned = clean(String(value))
                if !cleaned.isEmpty, !isOnlyAnAmount(cleaned) {
                    best = (rank, cleaned)
                }
            }
        }
        return best?.value
    }

    /// A line that starts with the balance, such as "Số dư: VND 16,181,570".
    private static let balanceLine = regex(#"^\s*(?:so du(?: kha dung| hien tai)?|sd|(?:available )?balance|han muc)(?!\p{L})"#)
    /// A line that starts with a label, such as "Thời gian: 12:30".
    private static let labeledLine = regex(#"^[^:：\d]{1,30}[:：]"#)

    private static func descriptionAfterBalance(in lines: [String]) -> String? {
        guard let index = lines.firstIndex(where: { !matches(of: balanceLine, in: fold($0)).isEmpty }),
              index + 1 < lines.count
        else { return nil }
        let line = lines[index + 1]
        guard matches(of: labeledLine, in: line).isEmpty else { return nil }
        let cleaned = clean(line)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static let referencePrefix = regex(#"^[A-Z]{2,12}(?:[.\-]\d{3,})+[.\-]\s*"#)
    private static let transferTail = regex(#"[\s.\-]+CT\s+(?:tu|den)\b.*$"#)
    /// After a period or an underscore: "… chuyen tien. Ma tham chieu 123456", "… _ So tien
    /// 2042000 VND _ Ngay 05/11/2026"; a bill's contract code ("… cho Ma HD PE0200…"); and the
    /// code after "CHUYEN KHOAN" ("…CHUYEN KHOAN-051126-14:26:22 6309…").
    private static let detailsTail = regex(
        #"(?:\.\s+|\s*_\s*)(?:m[aã] (?:tham chi[eế]u|gd|giao d[iị]ch)|s[oố] ti[eề]n|ng[aà]y|th[oờ]i gian|ref|trace)\b.*$"#
            + #"|\s+cho\s+m[aã]\s+(?:hd|hđ|h[oó]a [dđ][oơ]n|kh|kh[aá]ch h[aà]ng)\b.*$"#
            + #"|(?<=chuy[eể]n kho[aả]n)[\s\-]*\d.*$"#
    )
    private static let longNumber = regex(#"[^\s\p{L}]*\d{6,}[^\s\p{L}]*"#)

    /// A description without what banks add around it: a reference before it, such as
    /// "MBVCB.123456.789012.", the accounts, reference, amount or date after it ("CT tu 0011…
    /// NGUYEN VAN A", ". Ma tham chieu 123456"), and account, phone and reference numbers anywhere.
    public static func clean(_ description: String) -> String {
        var text = description
        for pattern in [referencePrefix, transferTail, detailsTail, longNumber] {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        let trimmed = Tags.tidy(text)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(["(", ")"])))
        return String(trimmed.prefix(descriptionMaximumLength))
    }

    // MARK: Words

    /// Lowercase, without diacritics, with đ as d, and one character for each in `text`.
    static func fold(_ text: String) -> String {
        String(text.map { character -> Character in
            if character == "đ" || character == "Đ" { return "d" }
            let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return folded.count == 1 ? folded.first! : character
        })
    }

    private static let wordPatterns: [String: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: Set(amountWords + balanceWords + moneyOutWords + moneyInWords).map { word in
            (word, regex(#"(?<![\p{L}\d])"# + NSRegularExpression.escapedPattern(for: word) + #"(?![\p{L}\d])"#))
        }
    )

    /// The word or phrase from `words` that comes last in `folded`, as whole words. A longer
    /// phrase at the same place wins, such as "so du kha dung" over "so du".
    private static func lastWord(of folded: String, in words: [String]) -> String? {
        var last: (position: String.Index, word: String)?
        for word in words {
            guard let pattern = wordPatterns[word] else { continue }
            for match in matches(of: pattern, in: folded) {
                if let current = last {
                    if match.start < current.position { continue }
                    if match.start == current.position, word.count <= current.word.count { continue }
                }
                last = (match.start, word)
            }
        }
        return last?.word
    }

    // MARK: Matching

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private struct Match {
        var start: String.Index
        var end: String.Index
        var groups: [String: String]

        subscript(name: String) -> String? { groups[name] }
    }

    private static let groupNames = ["sign1", "number1", "currency1", "sign3", "currency2", "sign2", "number2", "sign4", "number4",
                                     "day", "month", "year", "hour", "minute", "second"]

    private static func matches(of pattern: NSRegularExpression, in text: String) -> [Match] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            var groups: [String: String] = [:]
            for name in groupNames where pattern.pattern.contains("(?<\(name)>") {
                if let groupRange = Range(result.range(withName: name), in: text) {
                    groups[name] = String(text[groupRange])
                }
            }
            return Match(start: range.lowerBound, end: range.upperBound, groups: groups)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
