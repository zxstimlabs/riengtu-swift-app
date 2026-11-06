import Foundation

/// Everything Riengtu keeps: the person's entries (what they spent and received, and what moved
/// between their assets), newest first, their tags, what they own, and the currencies they use.
///
/// An asset keeps the value the person last set by hand, as of `Asset.valuedAt`. What it holds now
/// is that value with the changes of the entries dated after it (`current(_:at:)`), so entries
/// never change an asset themselves, and entries added on two devices both count once synced.
///
/// `LedgerDatabase` keeps it, one record per entry, asset and tag. Records a later version of
/// Riêng Tư wrote are kept as they are: shown but not changed (`newerIDs`), or, when this version
/// can't read them at all, left out (`unreadableRecordCount`).
public struct Ledger: Equatable, Sendable {
    /// The version of the JSON file earlier builds kept the ledger in (`LedgerFile`), which is now
    /// read once, to move it to the database. A file from a later version isn't read.
    ///
    /// - 1: expenses.
    /// - 2: assets too. A version 1 file reads as having none.
    /// - 3: tags too. An earlier file reads as having none, and as needing the starter tags.
    /// - 4: more expense categories, such as drinks and fees. An earlier file reads as it is.
    /// - 5: entries instead of expenses: income, transfers and changes to assets' values too, and
    ///   expenses and income can come from or go to an asset. An earlier file's expenses read as
    ///   entries that touch no asset. Its assets' values included what entries had changed.
    public static let currentVersion = 5

    /// How many recently used currencies the ledger remembers.
    public static let recentCurrencyLimit = 5

    /// Newest first. Entries on the same date keep the order they were added, latest first.
    public private(set) var entries: [Entry]
    /// In the order they were added.
    public private(set) var assets: [Asset]
    /// The currencies of the expenses and income saved most recently, most recent first. Assets
    /// and transfers don't change it, so the currency a new entry starts in is always one the
    /// person spent or received money in.
    public private(set) var recentCurrencyCodes: [String]
    /// The person's tags, or `nil` before the starter tags were added, so that tags the person
    /// deleted don't come back.
    private var storedTags: [String]?
    /// The entries and assets a later version of Riêng Tư wrote. They're shown, but this version
    /// doesn't change them, since it could lose what it doesn't understand.
    public internal(set) var newerIDs: Set<UUID> = []
    /// How many records a later version wrote that this one can't read, such as a new kind of
    /// entry. They're kept, and read once Riêng Tư is updated.
    public internal(set) var unreadableRecordCount = 0

    /// A ledger as it was saved: the assets' values already include what the entries changed.
    public init(
        entries: [Entry] = [],
        assets: [Asset] = [],
        recentCurrencyCodes: [String] = [],
        tags: [String]? = nil
    ) {
        self.entries = entries.sorted { $0.date > $1.date }
        self.assets = assets
        self.recentCurrencyCodes = Array(recentCurrencyCodes.prefix(Self.recentCurrencyLimit))
        self.storedTags = tags.map { Tags.unique($0.map(Tags.tidy).filter { !$0.isEmpty }) }
    }

    // MARK: Entries

    public func entry(id: Entry.ID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Adds the entry, or replaces the one with the same ID. Expenses and income remember their
    /// currency. What it changes in the assets counts from then on (`current(_:at:)`).
    ///
    /// Its tags are spelled as in the tag list, and ones the list doesn't have are added to it.
    public mutating func save(_ entry: Entry) {
        var entry = entry
        entry.tags = Tags.unique(entry.tags.compactMap { addTag($0) })
        insert(entry)

        guard entry.flow != .neither else { return }
        recentCurrencyCodes.removeAll { $0 == entry.currencyCode }
        recentCurrencyCodes.insert(entry.currencyCode, at: 0)
        if recentCurrencyCodes.count > Self.recentCurrencyLimit {
            recentCurrencyCodes.removeLast(recentCurrencyCodes.count - Self.recentCurrencyLimit)
        }
    }

    /// Deletes the entry, so what it changed in the assets no longer counts. Deleting an
    /// adjustment leaves the asset as it is.
    public mutating func deleteEntry(id: Entry.ID) {
        entries.removeAll { $0.id == id }
    }

    /// Puts the entry in its place by date, replacing the one with the same ID.
    private mutating func insert(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        let index = entries.firstIndex { $0.date <= entry.date } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

    /// The currency a new entry starts in: the one used last, or `fallback` before there is one.
    public func preferredCurrencyCode(fallback: String) -> String {
        recentCurrencyCodes.first ?? fallback
    }

    /// The account the latest expense came from (`.moneyOut`), or the latest income went to
    /// (`.moneyIn`), if there was one and it's still there.
    public func lastAccount(for flow: Entry.Flow) -> Asset.ID? {
        for entry in entries {
            switch (entry.kind, flow) {
            case (.expense(_, let account), .moneyOut), (.income(_, let account), .moneyIn):
                return account.flatMap { asset(id: $0)?.id }
            default:
                continue
            }
        }
        return nil
    }

    /// The entries grouped by the day they're on in `calendar`, newest day first: only the ones
    /// during `interval`, and with `tag`, when they're given.
    public func days(in calendar: Calendar, during interval: DateInterval? = nil, taggedWith tag: String? = nil) -> [Day] {
        var days: [Day] = []
        for entry in entries where Self.includes(entry, during: interval, taggedWith: tag) {
            let start = calendar.startOfDay(for: entry.date)
            if days.last?.date == start {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(Day(date: start, entries: [entry]))
            }
        }
        return days
    }

    /// One day's entries, newest first.
    public struct Day: Identifiable, Equatable, Sendable {
        /// The start of the day.
        public var date: Date
        public var entries: [Entry]

        public var id: Date { date }
    }

    /// The income and spending during `interval`, and with `tag` when it's given, in each
    /// currency. Transfers and adjustments aren't counted: the money was the person's already.
    /// The currency with the most entries comes first.
    public func flows(during interval: DateInterval, taggedWith tag: String? = nil) -> [MoneyFlow] {
        var flows: [String: (flow: MoneyFlow, count: Int)] = [:]
        for entry in entries where entry.flow != .neither && Self.includes(entry, during: interval, taggedWith: tag) {
            let code = entry.currencyCode
            flows[code, default: (MoneyFlow(currencyCode: code), 0)].count += 1
            if entry.flow == .moneyIn {
                flows[code]!.flow.moneyIn += entry.amount
            } else {
                flows[code]!.flow.moneyOut += entry.amount
            }
        }
        return flows.values
            .sorted { a, b in a.count != b.count ? a.count > b.count : a.flow.currencyCode < b.flow.currencyCode }
            .map(\.flow)
    }

    /// The money that came in and went out in one currency.
    public struct MoneyFlow: Identifiable, Equatable, Sendable {
        public var currencyCode: String
        public var moneyIn: Decimal
        public var moneyOut: Decimal

        public init(currencyCode: String, moneyIn: Decimal = 0, moneyOut: Decimal = 0) {
            self.currencyCode = currencyCode
            self.moneyIn = moneyIn
            self.moneyOut = moneyOut
        }

        /// What came in less what went out, below zero when more went out.
        public var net: Decimal { moneyIn - moneyOut }

        public var id: String { currencyCode }
    }

    /// When the earliest and the latest entries are, or `nil` when there are none.
    public var dateRange: ClosedRange<Date>? {
        guard let earliest = entries.last?.date, let latest = entries.first?.date else { return nil }
        return earliest...latest
    }

    /// Whether the entry is during `interval`, counting its start but not its end, so an entry
    /// at midnight is in only one month, and has `tag`.
    private static func includes(_ entry: Entry, during interval: DateInterval?, taggedWith tag: String?) -> Bool {
        if let interval, !(interval.start <= entry.date && entry.date < interval.end) { return false }
        if let tag, !entry.tags.contains(tag) { return false }
        return true
    }

    // MARK: Tags

    /// The person's tags, in the order they were added.
    public var tags: [String] {
        storedTags ?? []
    }

    /// Whether the starter tags (`Tags.starter`) haven't been added yet.
    public var needsStarterTags: Bool {
        storedTags == nil
    }

    /// Adds the starter tags, once.
    public mutating func addStarterTags() {
        guard needsStarterTags else { return }
        storedTags = Tags.starter
    }

    /// Adds a tag, unless the list has it already. Returns the tag as the list spells it, or `nil`
    /// if `name` is blank.
    @discardableResult
    public mutating func addTag(_ name: String) -> String? {
        let name = Tags.tidy(name)
        guard !name.isEmpty else { return nil }
        if let existing = Tags.match(name, in: tags) {
            return existing
        }
        storedTags = tags + [name]
        return name
    }

    /// Renames a tag on every entry that has it. If another tag already has the new name, the
    /// two become one.
    public mutating func renameTag(_ name: String, to newName: String) {
        let newName = Tags.tidy(newName)
        guard !newName.isEmpty, let old = Tags.match(name, in: tags) else { return }
        let replacement: String
        if let other = Tags.match(newName, in: tags), other != old {
            replacement = other
            storedTags = tags.filter { $0 != old }
        } else {
            replacement = newName
            storedTags = tags.map { $0 == old ? newName : $0 }
        }
        replaceTag(old, with: [replacement])
    }

    /// Deletes a tag, and takes it off every entry. The entries stay.
    public mutating func deleteTag(_ name: String) {
        guard let old = Tags.match(name, in: tags) else { return }
        storedTags = tags.filter { $0 != old }
        replaceTag(old, with: [])
    }

    /// How many entries have the tag.
    public func entryCount(taggedWith tag: String) -> Int {
        entries.count { $0.tags.contains(tag) }
    }

    /// Puts `replacement`, which can be empty, in place of `tag` on every entry that has it.
    private mutating func replaceTag(_ tag: String, with replacement: [String]) {
        for index in entries.indices where entries[index].tags.contains(tag) {
            entries[index].tags = Tags.unique(entries[index].tags.flatMap { $0 == tag ? replacement : [$0] })
        }
    }

    // MARK: Assets

    /// The asset as the person last set it by hand. `current(_:at:)` adds what entries changed
    /// since.
    public func asset(id: Asset.ID) -> Asset? {
        assets.first { $0.id == id }
    }

    /// The asset with what entries changed after its value was set, up to `date`: its balance
    /// now, or its quantity or weight now. Entries dated later, such as ones typed in ahead,
    /// count once their date comes. `valuedAt` stays when the value was set.
    public func current(_ asset: Asset, at date: Date = .now) -> Asset {
        var change: Decimal = 0
        // Newest first, so the ones after the asset's value was set come first.
        for entry in entries {
            guard entry.date > asset.valuedAt else { break }
            guard entry.date <= date else { continue }
            for (id, amount) in entry.assetChanges where id == asset.id {
                change += amount
            }
        }
        var current = asset
        if change != 0 { current.value = asset.value.adding(change) }
        return current
    }

    /// Adds the asset, or replaces the one with the same ID where it is. The asset's value is
    /// the one set by hand, as of its `valuedAt`.
    ///
    /// With a `date`, a change the person made to an existing asset's worth is recorded as an
    /// adjustment on that date, so the ledger shows it: from what the asset held then
    /// (`current(_:at:)`) to its new value. Without one, as for prices fetched automatically,
    /// which would fill the ledger, nothing is recorded. A change of currency isn't recorded
    /// either, since the two worths can't be compared.
    public mutating func save(_ asset: Asset, recordingChangeOn date: Date? = nil) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else {
            assets.append(asset)
            return
        }
        let old = assets[index]
        assets[index] = asset
        guard let date, old.currencyCode == asset.currencyCode else { return }
        let change = current(asset, at: date).worth - current(old, at: date).worth
        guard change != 0 else { return }
        insert(Entry(
            kind: .adjustment(asset: asset.id, isIncrease: change > 0),
            amount: abs(change),
            currencyCode: asset.currencyCode,
            date: date
        ))
    }

    /// Makes every asset's value the one as of `date`, at the latest, for values that already
    /// include what entries changed.
    mutating func valueAssets(at date: Date) {
        for index in assets.indices where assets[index].valuedAt < date {
            assets[index].valuedAt = date
        }
    }

    /// Deletes the asset and the records of its changes. Entries that took money from it or put
    /// money in it stay as they are, and show it as removed.
    public mutating func deleteAsset(id: Asset.ID) {
        assets.removeAll { $0.id == id }
        entries.removeAll { entry in
            if case .adjustment(id, _) = entry.kind { true } else { false }
        }
    }

    /// The assets in each group that has any, in the groups' order, as they are at `date`
    /// (`current(_:at:)`). Within a group, they're in the kinds' order, then by name.
    public func assetSections(at date: Date = .now) -> [AssetSection] {
        let order = Dictionary(uniqueKeysWithValues: AssetKind.allCases.enumerated().map { ($1, $0) })
        let sorted = assets.map { current($0, at: date) }.sorted { a, b in
            if a.kind != b.kind { return order[a.kind]! < order[b.kind]! }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return AssetKind.Group.allCases.compactMap { group in
            let assets = sorted.filter { $0.kind.group == group }
            return assets.isEmpty ? nil : AssetSection(group: group, assets: assets)
        }
    }

    /// What the assets are worth at `date` in each currency they're in. Amounts in different
    /// currencies aren't added together. The currency with the most assets comes first.
    public func assetTotals(at date: Date = .now) -> [Total] {
        var totals: [String: (amount: Decimal, count: Int)] = [:]
        for asset in assets.map({ current($0, at: date) }) {
            totals[asset.currencyCode, default: (0, 0)].amount += asset.worth
            totals[asset.currencyCode, default: (0, 0)].count += 1
        }
        return totals
            .sorted { a, b in a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key }
            .map { Total(currencyCode: $0.key, amount: $0.value.amount) }
    }

    /// One group's assets.
    public struct AssetSection: Identifiable, Equatable, Sendable {
        public var group: AssetKind.Group
        public var assets: [Asset]

        public var id: AssetKind.Group { group }
    }

    /// An amount in one currency.
    public struct Total: Identifiable, Equatable, Sendable {
        public var currencyCode: String
        public var amount: Decimal

        public var id: String { currencyCode }
    }
}

extension Ledger: Codable {
    private enum CodingKeys: String, CodingKey {
        /// `expenses` before version 5.
        case version, entries, expenses, assets, recentCurrencyCodes, tags
    }

    /// Reads a ledger of this version or an earlier one. `LedgerFile` checks the version first.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries)
            ?? container.decode([Entry].self, forKey: .expenses)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        recentCurrencyCodes = try container.decode([String].self, forKey: .recentCurrencyCodes)
        storedTags = try container.decodeIfPresent([String].self, forKey: .tags)
    }

    /// Writes the current version. Only tests write files now, to read them as earlier builds
    /// left them.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(assets, forKey: .assets)
        try container.encode(recentCurrencyCodes, forKey: .recentCurrencyCodes)
        try container.encodeIfPresent(storedTags, forKey: .tags)
    }
}
