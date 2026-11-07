import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a bank's notification, email or message with the Apple Intelligence model on the device:
/// what the money was for and the amount, what kind of transaction it was, and where income came
/// from. `InboxStore` checks the amount, and which way the money went, with the rules in
/// `TransactionText`.
///
/// It asks one question at a time, since the model on the device answered each better on its own
/// than all of them at once, which also made it invent descriptions. Like `ExpenseTagger`, it
/// uses only the model on the device. The app runs it while it's open, not when a message is
/// forwarded in the background.
///
/// Where the money went or came from is chosen in plain text, with the guardrails meant for
/// reading text the person gave (`permissiveContentTransformations`): asked for a structured
/// answer, the default guardrails refused some ordinary notices, such as a top-up of MoMo.
public enum TransactionReader {
    /// The longest text read, which is plenty for a notice and leaves out long footers.
    static let maximumLength = 4_000

    /// The raw values are what the model chooses from. Not "transfer" for money moved between the
    /// person's own accounts, which the model took for any "chuyển tiền" (transfer of money).
    public enum Kind: String, CaseIterable, Sendable {
        /// Paying for something, or sending money to someone else.
        case spending
        /// Money from someone else.
        case income
        /// Money moved between the person's own accounts, cards or wallets.
        case transfer = "ownAccounts"
    }

    /// What the model read, checked.
    public struct Answer: Equatable, Sendable {
        /// What the money was for, in the message's words. Empty when it doesn't say.
        public var description: String
        public var amount: Decimal?
        public var currencyCode: String?
        public var kind: Kind
        /// Where income came from. `nil` for anything else.
        public var incomeCategory: IncomeCategory?

        public init(
            description: String, amount: Decimal?, currencyCode: String?, kind: Kind, incomeCategory: IncomeCategory? = nil
        ) {
            self.description = description
            self.amount = amount
            self.currencyCode = currencyCode
            self.kind = kind
            self.incomeCategory = kind == .income ? incomeCategory : nil
        }
    }

    /// `direction` is which way the money went, where the rules can tell, which helps the model
    /// tell what kind it is.
    /// Reads a message as the rules sorted it (`TransactionText.notice(for:)`), not as it came:
    /// the model then can't take the balance for the amount, and reads less.
    public static func read(_ text: String) async throws -> Answer {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let sorted = TransactionText.notice(for: text)
            let direction = sorted.direction
            let notice = "Notice:\n" + sorted.prompt.prefix(maximumLength)
            // Each question can fail on its own, such as for a language the model doesn't support,
            // and the rules fill in what it didn't answer. Where the rules have the amount and a
            // label gives what it was for, the first question isn't needed.
            let facts = sorted.amount != nil && sorted.labeledDescription != nil ? nil : try await unlessItCantNow {
                try await LanguageModelSession(model: SystemLanguageModel.default, instructions: factsInstructions)
                    .respond(to: notice, generating: Facts.self, options: options).content
            }

            // Where the rules know which way the money went, the model picks where it went to or
            // came from, which says the kind, and for income, the category. Asked whether money
            // moved between the person's own accounts, it nearly always said yes, and asked to
            // choose from the three kinds, it took money that came in for spending.
            var kind: Kind
            var incomeCategory: IncomeCategory?
            switch direction {
            case .moneyOut:
                let choice = try await unlessItCantNow {
                    try await choose(from: Array(moneyOutChoices.keys), instructions: moneyOutInstructions, notice: notice)
                } ?? nil
                kind = choice.flatMap { moneyOutChoices[$0] } ?? .spending
            case .moneyIn:
                let choice = try await unlessItCantNow {
                    try await choose(from: Array(moneyInChoices.keys), instructions: moneyInInstructions, notice: notice)
                } ?? nil
                (kind, incomeCategory) = choice.flatMap { moneyInChoices[$0] } ?? (.income, .other)
            case nil:
                let choice = try await unlessItCantNow {
                    try await choose(from: Kind.allCases.map(\.rawValue), instructions: kindInstructions, notice: notice)
                } ?? nil
                kind = choice.flatMap(Kind.init(rawValue:)) ?? .spending
                if kind == .income {
                    let category = try await unlessItCantNow {
                        try await choose(from: IncomeCategory.allCases.map(\.rawValue), instructions: incomeInstructions, notice: notice)
                    } ?? nil
                    incomeCategory = category.flatMap(IncomeCategory.init(rawValue:)) ?? .other
                }
            }
            return checked(
                summary: facts?.summary ?? "", amount: facts?.amount, currency: facts?.currency,
                kind: kind.rawValue, incomeCategory: incomeCategory?.rawValue
            )
        }
        #endif
        throw ExpenseTagger.UnavailableError()
    }

    /// Loads the model ahead of the first question, which otherwise waits several seconds for it.
    public static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), ExpenseTagger.availability == .available {
            LanguageModelSession(model: SystemLanguageModel.default, instructions: factsInstructions).prewarm()
        }
        #endif
    }

    /// Thrown when the model can't answer now but could later, such as when iOS limits its use
    /// by an app in the background, on battery. What wasn't read waits until it can be.
    public struct TryLaterError: Error {}

    /// The answer, or `nil` where the model can't give one for this message, such as for a
    /// language it doesn't support, so the rules read it. Throws `TryLaterError` where it can't
    /// answer now.
    static func unlessItCantNow<T>(_ question: () async throws -> T) async throws -> T? {
        do {
            return try await question()
        } catch is CancellationError {
            throw CancellationError()
        } catch where isTemporary(error) {
            throw TryLaterError()
        } catch {
            return nil
        }
    }

    /// Whether the model refused only for now: rate limited, busy, or its assets not ready.
    public static func isTemporary(_ error: any Error) -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError, case .rateLimited = error {
            return true
        }
        if #available(iOS 26.0, macOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests, .assetsUnavailable: return true
            default: return false
            }
        }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static var options: GenerationOptions {
        GenerationOptions(samplingMode: .greedy)
    }

    /// Asks the model to choose one of `choices` for the notice, in a word.
    @available(iOS 26.0, macOS 26.0, *)
    private static func choose(from choices: [String], instructions: String, notice: String) async throws -> String? {
        let session = LanguageModelSession(
            model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
            instructions: instructions + " Answer with only the one word."
        )
        return choice(in: try await session.respond(to: notice, options: options).content, from: choices)
    }
    #endif

    /// The first word of the model's answer that's one of `choices`, whatever its case.
    static func choice(in answer: String, from choices: [String]) -> String? {
        for word in answer.split(whereSeparator: { !$0.isLetter }) {
            if let choice = choices.first(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                return choice
            }
        }
        return nil
    }

    /// Checks what the model answered.
    static func checked(summary: String, amount: String?, currency: String?, kind: String, incomeCategory: String?) -> Answer {
        let code = currency.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .flatMap { Currencies.all.contains($0) ? $0 : nil }
        let amount = amount.flatMap {
            TransactionText.parseNumber($0.filter { $0.isNumber || $0 == "." || $0 == "," }, fractionDigits: Currencies.fractionDigits(for: code ?? "VND"))
        }
        return Answer(
            description: TransactionText.clean(TransactionText.withoutTokens(summary)),
            amount: amount.flatMap { $0 > 0 ? $0 : nil },
            currencyCode: code,
            kind: Kind(rawValue: kind) ?? .spending,
            incomeCategory: incomeCategory.map { IncomeCategory(rawValue: $0) ?? .other }
        )
    }

    /// Tested on sample notices: without "copy the words", it translated descriptions into
    /// English and summed them up loosely. Its amounts are checked with the rules, since it
    /// sometimes gives the balance.
    static let factsInstructions = """
        You read a bank's notice about one transaction and pull out two facts. First, what the \
        money was for: copy the words of the transfer's content (nội dung) if it has one, \
        otherwise the merchant or the bill, in the notice's own language. Don't translate or \
        explain them. Leave out codes, reference numbers, account and phone numbers, dates, and \
        the names of the sender and the bank. Second, the amount of money that moved and its \
        currency. Never give the balance (số dư, SD). Notices are often in Vietnamese.
        """

    /// For a notice that doesn't say which way the money went.
    static let kindInstructions = """
        You read a bank's notice about one transaction on the person's account, and say what \
        kind it is. ownAccounts: the money only moved between the person's own accounts, cards \
        or wallets: paying off their own credit card (thanh toán nợ thẻ tín dụng, thanh toán dư \
        nợ thẻ), topping up their own e-wallet (nạp tiền vào ví MoMo, ZaloPay), putting money \
        into savings or taking it out (gửi tiết kiệm, tất toán), or taking out cash (rút tiền \
        mặt). spending: money that went out to anyone or anything else: a shop, a bill, or \
        another person, including money sent with chuyển tiền or chuyển khoản. income: money \
        that came in from anyone else: pay, interest, a refund, or another person sending money, \
        including with chuyển tiền. Notices are often in Vietnamese.
        """

    /// Where money that went out went, and the kind of entry each makes.
    static let moneyOutChoices: [String: Kind] = [
        "shop": .spending, "bill": .spending, "person": .spending, "loan": .spending, "other": .spending,
        "ownCard": .transfer, "ownWallet": .transfer, "ownSavings": .transfer, "cash": .transfer,
    ]

    static let moneyOutInstructions = """
        You read a bank's notice about money that went out of the person's account, and say \
        where it went. shop: a shop, restaurant, café or service, in person, online or by QR. \
        bill: a bill, such as electricity (tiền điện), water, internet, phone or school fees. \
        person: another person, by transfer (chuyển tiền, chuyển khoản). A content of only a \
        name and "chuyen tien" is what the bank writes for a QR payment or a transfer to someone \
        else, so it's person. loan: paying back a loan or an installment (trả góp), but never a \
        credit card. ownCard: paying off the person's own credit card (thanh toán nợ thẻ tín \
        dụng, thanh toán dư nợ thẻ). ownWallet: topping up the person's own e-wallet (nạp tiền vào ví MoMo, ZaloPay). \
        ownSavings: into the person's own savings deposit (gửi tiết kiệm). cash: cash taken out \
        (rút tiền mặt, ATM). other: anything else. Notices are often in Vietnamese.
        """

    /// Where money that came in came from, the kind of entry each makes, and its category.
    static let moneyInChoices: [String: (Kind, IncomeCategory?)] = [
        "pay": (.income, .salary), "bonus": (.income, .bonus), "interest": (.income, .investment),
        "refund": (.income, .refunds), "person": (.income, .other), "other": (.income, .other),
        "ownSavings": (.transfer, nil), "ownAccount": (.transfer, nil),
    ]

    static let moneyInInstructions = """
        You read a bank's notice about money that came into the person's account, and say where \
        it came from. pay: pay from an employer or a company (lương, trả lương, tra luong). \
        bonus: a bonus (thưởng). interest: \
        interest, dividends or profit on savings or investments (lãi, cổ tức, lợi nhuận, sinh \
        lời). refund: a refund or cashback (hoàn tiền, hoàn trả, giao dịch hoàn trả). person: \
        another person, by transfer (chuyển tiền, chuyển khoản), such as paying them back. A \
        content of only a name and "chuyen tien" or "chuyen khoan" is a transfer from someone, so \
        it's person, not pay. ownSavings: the person's own \
        savings deposit closed or paid out (tất toán). ownAccount: the person's own account at \
        another bank or e-wallet. other: anything else. Notices are often in Vietnamese.
        """

    /// One line per category, like `ExpenseTagger.categoryDescription`. Money that came in from
    /// the inbox is often someone paying back, which is "other".
    static let incomeInstructions = """
        You read a bank's notice about money that came into the person's account, and say where \
        it came from. salary: pay (lương), from an employer. bonus: bonuses, the 13th month's \
        pay, Tết bonuses (thưởng). business: takings from the person's own shop or business. \
        sideJob: freelance work, jobs on the side. investment: interest (lãi, lãi tiền gửi), \
        dividends (cổ tức), profit on savings or investments (sinh lời). rental: rent received \
        (tiền thuê nhà). gifts: presents, lucky money (lì xì), wedding money (mừng cưới). family: \
        money from parents or relatives. refunds: refunds (hoàn tiền), cashback. selling: things \
        sold, such as used goods. other: anything else, such as someone paying back money they \
        owed or sharing a bill. Notices are often in Vietnamese.
        """

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct Facts {
        @Guide(description: "What the money was for, in the notice's own words and language, without codes or numbers.")
        var summary: String
        @Guide(description: "The amount that moved, digits only, with a dot before any decimals. Not the balance.")
        var amount: String?
        @Guide(description: "The amount's ISO 4217 currency code, such as VND or USD.")
        var currency: String?
    }

    #endif
}
