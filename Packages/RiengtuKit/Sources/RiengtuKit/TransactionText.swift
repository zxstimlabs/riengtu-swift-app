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

    private struct Amount {
        var value: Decimal
        var currencyCode: String
        var direction: Direction?
        var score: Int
    }

    private static let number = #"(?<![\d.,])(?:\d{1,3}(?:[.,  ]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    private static let currency = #"VNĐ|VND|đồng|dong|đ|₫|USD|US\$|\$|EUR|€"#

    /// A number then its currency, such as "-150,000 VND", or a currency then its number, such as
    /// "VND 150,000" or "$12.50".
    private static let amountPattern = regex(
        #"(?<sign1>[+\-−])?[  ]*(?<number1>"# + number + #")[  ]*(?<currency1>"# + currency + #")(?!\p{L})"#
            + #"|(?<!\p{L})(?<currency2>"# + currency + #")[  ]*(?<sign2>[+\-−])?[  ]*(?<number2>"# + number + #")(?!\d)"#
    )

    /// The amount that moved, not the balance: one with a sign, or after words like "số tiền",
    /// wins over one after "số dư".
    private static func bestAmount(in text: String) -> Amount? {
        var best: Amount?
        for match in matches(of: amountPattern, in: text) {
            guard let numberText = match["number1"] ?? match["number2"],
                  let code = (match["currency1"] ?? match["currency2"]).flatMap(currencyCode(for:)),
                  let value = parseNumber(numberText, fractionDigits: Currencies.fractionDigits(for: code)),
                  value > 0
            else { continue }
            let sign = match["sign1"] ?? match["sign2"]

            // The words just before the amount say what it is.
            let from: String.Index = text.index(match.start, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            let before = fold(String(text[from..<match.start]))
            var score = 0
            var direction: Direction?
            if let sign {
                score += 3
                direction = sign == "+" ? .moneyIn : .moneyOut
            }
            if lastWord(of: before, in: amountWords) != nil { score += 2 }
            if let last = lastWord(of: before, in: balanceWords + amountWords), balanceWords.contains(last) {
                score -= 5
            }
            direction = direction ?? self.direction(in: before)
            if best.map({ score > $0.score }) ?? true {
                best = Amount(value: value, currencyCode: code, direction: direction, score: score)
            }
        }
        return best
    }

    private static let amountWords = [
        "so tien", "so tien giao dich", "ps", "phat sinh", "giao dich", "gd", "thanh toan", "chuyen",
        "amount", "transaction", "payment", "paid", "debit", "credit", "ghi no", "ghi co",
    ]
    private static let balanceWords = ["so du", "sd", "so du kha dung", "balance", "available balance", "kha dung"]

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
        let separators: Set<Character> = [".", ",", " ", "\u{00A0}"]
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
    ].map { regex(#"(?:^|[^\p{L}])"# + NSRegularExpression.escapedPattern(for: $0) + #"\s*[:：]\s*"#) }

    /// The text after a label such as "Nội dung:" or "ND:", to the end of its line.
    private static func description(in text: String) -> String {
        var best: (rank: Int, value: String)?
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let folded = fold(line)
            for (rank, label) in descriptionLabels.enumerated() where best.map({ rank < $0.rank }) ?? true {
                guard let match = matches(of: label, in: folded).first else { continue }
                // Folding keeps one character for each, so the offset carries over to the line.
                let offset = folded.distance(from: folded.startIndex, to: match.end)
                let value = line.dropFirst(offset)
                    .prefix { !"|;".contains($0) }
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(["(", ")"])))
                let cleaned = clean(String(value))
                if !cleaned.isEmpty {
                    best = (rank, cleaned)
                }
            }
        }
        return best?.value ?? ""
    }

    private static let referencePrefix = regex(#"^[A-Z]{2,12}(?:[.\-]\d{3,})+[.\-]\s*"#)
    private static let transferTail = regex(#"[\s.\-]+CT\s+(?:tu|den)\b.*$"#)
    private static let longNumber = regex(#"[^\s\p{L}]*\d{6,}[^\s\p{L}]*"#)

    /// A description without what banks add around it: a reference before it, such as
    /// "MBVCB.123456.789012.", the accounts after it ("CT tu 0011… NGUYEN VAN A"), and account,
    /// phone and reference numbers anywhere.
    public static func clean(_ description: String) -> String {
        var text = description
        for pattern in [referencePrefix, transferTail, longNumber] {
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

    private static let groupNames = ["sign1", "number1", "currency1", "currency2", "sign2", "number2",
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
