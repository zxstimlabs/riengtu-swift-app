import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a bank's email or message with the Apple Intelligence model on the device, for what the
/// rules in `TransactionText` can't: a short, clean description of what the money was for, and
/// the amount where the rules found none.
///
/// Like `ExpenseTagger`, it uses only the model on the device. The app runs it while it's open,
/// not when a message is captured in the background.
public enum TransactionReader {
    /// The longest text read, which is plenty for a notice and leaves out long footers.
    static let maximumLength = 4_000

    public static func read(_ text: String) async throws -> TransactionText.Reading {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let answer = try await session.respond(
                to: "Notice:\n" + text.prefix(maximumLength),
                generating: Answer.self,
                options: GenerationOptions(samplingMode: .greedy)
            ).content
            return reading(description: answer.summary, amount: answer.amount, currency: answer.currency)
        }
        #endif
        throw ExpenseTagger.UnavailableError()
    }

    /// Checks what the model answered.
    static func reading(description: String, amount: String?, currency: String?) -> TransactionText.Reading {
        let code = currency.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .flatMap { Currencies.all.contains($0) ? $0 : nil }
        let amount = amount.flatMap {
            TransactionText.parseNumber($0.filter { $0.isNumber || $0 == "." || $0 == "," }, fractionDigits: Currencies.fractionDigits(for: code ?? "VND"))
        }
        return TransactionText.Reading(
            amount: amount.flatMap { $0 > 0 ? $0 : nil },
            currencyCode: code,
            description: TransactionText.clean(description)
        )
    }

    /// Tested on sample notices: without "copy the words", it translated descriptions into
    /// English and summed them up loosely. Its amounts are only used where the rules found none,
    /// since it sometimes gives the balance.
    static let instructions = """
        You read a bank's notice about one transaction and pull out two facts. First, what the \
        money was for: copy the words of the transfer's content (nội dung) if it has one, \
        otherwise the merchant or the bill, in the notice's own language. Don't translate or \
        explain them. Leave out codes, reference numbers, account and phone numbers, dates, and \
        the names of the sender and the bank. Second, the amount of money that moved and its \
        currency. Never give the balance (số dư, SD). Notices are often in Vietnamese.
        """

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct Answer {
        @Guide(description: "What the money was for, in the notice's own words and language, without codes or numbers.")
        var summary: String
        @Guide(description: "The amount that moved, digits only, with a dot before any decimals. Not the balance.")
        var amount: String?
        @Guide(description: "The amount's ISO 4217 currency code, such as VND or USD.")
        var currency: String?
    }
    #endif
}
