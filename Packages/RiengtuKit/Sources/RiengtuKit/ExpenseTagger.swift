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
    /// language it doesn't support.
    public static func suggest(
        note: String, amount: Decimal?, currencyCode: String, tags list: [String]
    ) async throws -> TagSuggestion {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: prompt(note: note, amount: amount, currencyCode: currencyCode),
                schema: try schema(tags: list),
                // The same note gets the same suggestion.
                options: GenerationOptions(samplingMode: .greedy)
            )
            let content = response.content
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

    static let categoryDescription = """
        food: meals, drinks, restaurants, cafés, street food. \
        groceries: supermarkets and markets, food to cook at home. \
        transport: fuel, taxis, ride-hailing such as Grab, buses, parking, tolls, repairs. \
        shopping: clothes, electronics, things for the home. \
        housing: rent, repairs, furniture. \
        bills: electricity, water, internet, phone, subscriptions for the home. \
        health: doctors, medicine, insurance, gym. \
        education: school fees, courses, books. \
        entertainment: films, games, music, streaming. \
        travel: hotels (khách sạn), flights, tours, trips away from home. \
        family: children, parents, relatives. \
        gifts: presents, weddings, funerals, lucky money (lì xì) at Tết. \
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
