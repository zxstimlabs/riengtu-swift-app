import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Suggests a category and tags for an expense from its note, with the Apple Intelligence model
/// on the device.
///
/// Nothing leaves the device: this uses only `SystemLanguageModel`, never a model in the cloud
/// such as Private Cloud Compute. The model needs iOS 26 and a device that runs Apple
/// Intelligence, with it turned on; anywhere else, `availability` says why not.
public enum ExpenseTagger {
    public enum Availability: Equatable, Sendable {
        case available
        /// Apple Intelligence is turned off in Settings.
        case appleIntelligenceOff
        /// The model is still downloading, or not ready for another reason.
        case notReady
        /// The device can't run Apple Intelligence, or its system is earlier than iOS 26.
        case unsupported
    }

    /// Thrown by `suggest` where the model isn't available.
    public struct UnavailableError: Error {}

    /// How long the model gets to answer one question, here and in `TransactionReader`, before
    /// `TimedOutError`. It answers in a second or two, and a few more the first time, while it
    /// loads; one that hasn't answered by then may never.
    public static let timeLimit: Duration = .seconds(20)

    public static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
                case .modelNotReady: return .notReady
                case .deviceNotEligible: return .unsupported
                @unknown default: return .notReady
                }
            }
        }
        #endif
        return .unsupported
    }

    /// Suggests a category for the expense, tags from `list` that fit what it was for, and maybe
    /// a new tag. Throws if the model isn't available or can't answer, such as for a note in a
    /// language it doesn't support, and `TimedOutError` if it doesn't answer in `timeLimit`.
    public static func suggest(
        note: String, amount: Decimal?, currencyCode: String, tags list: [String]
    ) async throws -> TagSuggestion {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let prompt = prompt(note: note, amount: amount, currencyCode: currencyCode)
            let schema = try schema(tags: list)
            let content = try await ModelQueue.shared.run(within: timeLimit) {
                try await LanguageModelSession(model: model, instructions: instructions).respond(
                    to: prompt,
                    schema: schema,
                    // The same note gets the same suggestion, and a runaway answer stops.
                    options: TransactionReader.options(maximumTokens: 150)
                ).content
            }
            return TagSuggestion(
                category: try? content.value(String.self, forProperty: "category"),
                tags: list.isEmpty ? [] : (try? content.value([String].self, forProperty: "tags")) ?? [],
                // It sometimes writes "none" here too.
                newTag: ((try? content.value(String?.self, forProperty: "newTag")) ?? nil)
                    .flatMap { Tags.match($0, in: [noTag]) == nil ? $0 : nil },
                list: list,
                note: note
            )
        }
        #endif
        throw UnavailableError()
    }

    static func prompt(note: String, amount: Decimal?, currencyCode: String) -> String {
        var lines = ["Note: \(note)"]
        if let amount {
            lines.append("Amount: \(amount) \(currencyCode)")
        }
        return lines.joined(separator: "\n")
    }

    /// Tested on sample notes against the model: the general model follows these better than
    /// the one tuned for tagging, which tags nearly everything, and offering "none" stops it
    /// picking a tag when the note doesn't say. The instructions don't name any tags, since the
    /// person can rename them.
    static let instructions = """
        You sort the expenses someone records in a private budgeting app. First choose the \
        category that fits the expense best. Then choose tags from the person's own list, but \
        only when the note says or clearly implies what the expense was for, such as who it was \
        for, an occasion, or a trip. When the note doesn't say, choose "\(noTag)". Most expenses \
        need one tag at most. Give a new tag only when the note names a specific trip or event \
        that the list doesn't have, in one to three words in the language of the note; \
        otherwise leave it out. Notes are often in Vietnamese.
        """

    /// The choice that means no tag fits. Dropped from the answer, since it isn't in the list.
    static let noTag = "none"

    /// One line per category, so the model can tell close ones apart, such as transport and
    /// vehicle, or shopping and the kinds of things bought. Vietnamese words in brackets are
    /// what people write. Tested on 75 sample notes in both languages: 73 were right, and the
    /// two misses were close calls (a train ticket as transport, running shoes as fashion).
    /// Worship has its own category because the model read "charity" as donations only.
    static let categoryDescription = """
        food: meals out, restaurants, street food (cơm, phở, bún), food delivery such as GrabFood. \
        drinks: coffee, cafés, milk tea (trà sữa), juice, beer. \
        groceries: supermarkets, markets (chợ), convenience stores, food to cook at home. \
        transport: ride-hailing such as Grab or Xanh SM, taxis, buses, metro, trains, fuel \
        (xăng), parking (gửi xe), tolls. \
        vehicle: a motorbike or car of one's own: repairs, servicing, oil, tyres, washing, \
        registration. \
        housing: rent (tiền nhà, tiền trọ), mortgage, building fees (phí quản lý), repairs to \
        the home. \
        household: furniture, appliances, kitchenware, cleaning supplies. \
        bills: electricity (tiền điện), water (tiền nước), gas, internet, mobile plans and \
        top-ups (nạp tiền điện thoại), but not phones or their accessories. \
        subscriptions: apps and services paid every month or year, such as Netflix, Spotify, \
        iCloud or YouTube Premium. \
        shopping: online shopping such as Shopee, Lazada or Tiki, and things that fit no other \
        kind. \
        fashion: clothes, shoes, bags, jewellery. \
        electronics: phones, computers, headphones, chargers and cables (sạc, cáp), gadgets. \
        beauty: haircuts, salons, spas, nails, massage, cosmetics, skincare. \
        health: doctors, hospitals, dentists, medicine, pharmacies (nhà thuốc). \
        fitness: gym, yoga, swimming, football or badminton courts, sports gear. \
        insurance: health, life, car and motorbike insurance (bảo hiểm). \
        education: school fees (học phí), extra classes (học thêm), courses, books. \
        entertainment: cinema, concerts, games, karaoke, hobbies. \
        travel: hotels (khách sạn), homestays, flights, tours, trips away from home. \
        family: money for parents and relatives (gửi tiền về nhà). \
        kids: anything for babies and children (cho bé, cho con): formula milk (sữa bột), \
        diapers (bỉm), toys, babysitting. \
        pets: anything for a dog or cat: pet food, vets (thú y), grooming. \
        gifts: presents for people, birthdays, weddings (đám cưới), funerals (đám hiếu), lucky \
        money (lì xì) at Tết, but not offerings for worship. \
        charity: donations to people in need, disaster relief, charities (từ thiện, ủng hộ). \
        worship: offerings (đồ cúng, vàng mã, hoa quả cúng) for rằm, mùng một or giỗ, visits \
        and gifts to temples and pagodas (đi lễ chùa, công đức). \
        fees: bank, card and transfer fees, such as a card's yearly fee (phí thường niên), \
        taxes (thuế), fines (phạt). \
        loans: loan repayments, installments (trả góp), paying back money borrowed. \
        other: anything else.
        """

    #if canImport(FoundationModels)
    /// The on-device model.
    @available(iOS 26.0, macOS 26.0, *)
    private static var model: SystemLanguageModel {
        SystemLanguageModel.default
    }

    /// What the model answers: a category, tags from the list (left out when the list is
    /// empty), and an optional new tag. The model can only give values the schema allows.
    @available(iOS 26.0, macOS 26.0, *)
    static func schema(tags list: [String]) throws -> GenerationSchema {
        var properties = [
            DynamicGenerationSchema.Property(
                name: "category",
                description: categoryDescription,
                schema: DynamicGenerationSchema(name: "Category", anyOf: ExpenseCategory.allCases.map(\.rawValue))
            ),
        ]
        if !list.isEmpty {
            properties.append(DynamicGenerationSchema.Property(
                name: "tags",
                description: "Tags from the person's list that say what the expense was for, or \"\(noTag)\" when the note doesn't say.",
                schema: DynamicGenerationSchema(
                    arrayOf: DynamicGenerationSchema(name: "Tag", anyOf: list + (Tags.match(noTag, in: list) == nil ? [noTag] : [])),
                    maximumElements: TagSuggestion.maximumTags
                )
            ))
        }
        properties.append(DynamicGenerationSchema.Property(
            name: "newTag",
            description: "Only when the note names a specific trip or event the list lacks, such as \"Phú Quốc trip\". Otherwise leave it out.",
            schema: DynamicGenerationSchema(type: String.self),
            isOptional: true
        ))
        return try GenerationSchema(
            root: DynamicGenerationSchema(name: "ExpenseTags", properties: properties),
            dependencies: []
        )
    }
    #endif
}
