import Foundation
import Testing
@testable import RiengtuKit

/// Income, spending and transfers, and what they change in the assets.
struct EntryTests {
    static let cash = Asset(kind: .cash, currencyCode: "VND", value: .amount(3_000_000), valuedAt: AssetTests.date)
    static let bank = Asset(kind: .bankAccount, name: "Vietcombank", currencyCode: "VND", value: .amount(80_000_000), valuedAt: AssetTests.date)
    static let dollars = Asset(kind: .cash, currencyCode: "USD", value: .amount(500), valuedAt: AssetTests.date)
    static let shares = Asset(kind: .stock, name: "FPT", currencyCode: "VND", value: .holding(quantity: 100, price: 120_000), valuedAt: AssetTests.date)
    static let gold = Asset(kind: .gold, name: "SJC", currencyCode: "VND", value: .gold(weight: 5, unit: .chi, price: 150_000_000, priceUnit: .luong), valuedAt: AssetTests.date)

    static func ledger() -> Ledger {
        Ledger(assets: [cash, bank, dollars, shares, gold])
    }

    static func expense(_ amount: Decimal, from account: Asset.ID? = nil, day: Int = 5, currency: String = "VND") -> Entry {
        Entry(kind: .expense(.food, account: account), amount: amount, currencyCode: currency, date: LedgerTests.date(day))
    }

    static func income(_ amount: Decimal, into account: Asset.ID? = nil, day: Int = 5, currency: String = "VND") -> Entry {
        Entry(kind: .income(.salary, account: account), amount: amount, currencyCode: currency, date: LedgerTests.date(day))
    }

    static func transfer(_ amount: Decimal, from: Entry.Leg?, to: Entry.Leg?, day: Int = 5) -> Entry {
        Entry(kind: .transfer(from: from, to: to), amount: amount, currencyCode: "VND", date: LedgerTests.date(day))
    }

    // MARK: What entries change in assets

    /// The asset's value with what entries changed, late in the month, after every test entry.
    static func value(of asset: Asset, in ledger: Ledger, at date: Date = LedgerTests.date(30)) -> Asset.Value? {
        ledger.asset(id: asset.id).map { ledger.current($0, at: date).value }
    }

    @Test func takesAnExpenseFromItsAccountAndPutsIncomeInIts() {
        var ledger = Self.ledger()
        ledger.save(Self.expense(45_000, from: Self.cash.id))
        ledger.save(Self.income(25_000_000, into: Self.bank.id))
        ledger.save(Self.expense(10_000))

        #expect(Self.value(of: Self.cash, in: ledger) == .amount(2_955_000))
        #expect(Self.value(of: Self.bank, in: ledger) == .amount(105_000_000))
        // The asset itself stays as it was set by hand.
        #expect(ledger.asset(id: Self.cash.id) == Self.cash)
        #expect(ledger.current(Self.cash, at: LedgerTests.date(30)).valuedAt == AssetTests.date)
    }

    @Test func countsAnEntryAsItsSavedNow() {
        var ledger = Self.ledger()
        var entry = Self.expense(45_000, from: Self.cash.id)
        ledger.save(entry)

        entry.amount = 60_000
        ledger.save(entry)
        #expect(Self.value(of: Self.cash, in: ledger) == .amount(2_940_000))

        entry.kind = .expense(.food, account: Self.bank.id)
        ledger.save(entry)
        #expect(Self.value(of: Self.cash, in: ledger) == .amount(3_000_000))
        #expect(Self.value(of: Self.bank, in: ledger) == .amount(79_940_000))

        entry.kind = .income(.refunds, account: Self.bank.id)
        ledger.save(entry)
        #expect(Self.value(of: Self.bank, in: ledger) == .amount(80_060_000))
    }

    @Test func stopsCountingAnEntryThatsDeleted() {
        var ledger = Self.ledger()
        let entry = Self.income(1_000_000, into: Self.bank.id)
        ledger.save(entry)
        ledger.deleteEntry(id: entry.id)
        #expect(Self.value(of: Self.bank, in: ledger) == Self.bank.value)
        #expect(ledger.entries.isEmpty)
    }

    @Test func countsOnlyEntriesAfterTheValueWasSetAndUpToTheDate() {
        var ledger = Self.ledger()
        var cash = Self.cash
        cash.valuedAt = LedgerTests.date(10)
        ledger.save(cash)
        // Already in the value the person typed on the 10th.
        ledger.save(Self.expense(100_000, from: cash.id, day: 9))
        ledger.save(Self.expense(20_000, from: cash.id, day: 11))
        // Typed in ahead.
        ledger.save(Self.expense(5_000, from: cash.id, day: 25))

        #expect(Self.value(of: cash, in: ledger, at: LedgerTests.date(20)) == .amount(2_980_000))
        #expect(Self.value(of: cash, in: ledger, at: LedgerTests.date(25)) == .amount(2_975_000))
    }

    @Test func letsABalanceGoBelowZero() {
        var ledger = Self.ledger()
        ledger.save(Self.expense(3_500_000, from: Self.cash.id))
        #expect(Self.value(of: Self.cash, in: ledger) == .amount(-500_000))
        #expect(ledger.current(Self.cash, at: LedgerTests.date(30)).worth == -500_000)
    }

    @Test func movesMoneyBetweenAccounts() {
        var ledger = Self.ledger()
        // An ATM withdrawal.
        ledger.save(Self.transfer(
            2_000_000,
            from: Entry.Leg(asset: Self.bank.id, change: 2_000_000),
            to: Entry.Leg(asset: Self.cash.id, change: 2_000_000)
        ))
        #expect(Self.value(of: Self.bank, in: ledger) == .amount(78_000_000))
        #expect(Self.value(of: Self.cash, in: ledger) == .amount(5_000_000))

        // Dollars changed into đồng, each side in its own currency.
        ledger.save(Entry(
            kind: .transfer(from: Entry.Leg(asset: Self.dollars.id, change: 100), to: Entry.Leg(asset: Self.cash.id, change: 2_540_000)),
            amount: 100, currencyCode: "USD", date: LedgerTests.date(6)
        ))
        #expect(Self.value(of: Self.dollars, in: ledger) == .amount(400))
        #expect(Self.value(of: Self.cash, in: ledger) == .amount(7_540_000))
    }

    @Test func buysAndSellsSharesAndGoldByQuantity() {
        var ledger = Self.ledger()
        ledger.save(Self.transfer(
            12_000_000,
            from: Entry.Leg(asset: Self.bank.id, change: 12_000_000),
            to: Entry.Leg(asset: Self.shares.id, change: 100)
        ))
        ledger.save(Self.transfer(
            30_000_000,
            from: Entry.Leg(asset: Self.gold.id, change: 2),
            to: Entry.Leg(asset: Self.cash.id, change: 30_000_000)
        ))

        #expect(Self.value(of: Self.bank, in: ledger) == .amount(68_000_000))
        // The price stays as it was set.
        #expect(Self.value(of: Self.shares, in: ledger) == .holding(quantity: 200, price: 120_000))
        #expect(Self.value(of: Self.gold, in: ledger) == .gold(weight: 3, unit: .chi, price: 150_000_000, priceUnit: .luong))
        #expect(Self.value(of: Self.cash, in: ledger) == .amount(33_000_000))
    }

    @Test func totalsAndListsAssetsWithWhatEntriesChanged() {
        var ledger = Ledger(assets: [Self.cash, Self.bank])
        ledger.save(Self.expense(45_000, from: Self.cash.id))
        let date = LedgerTests.date(30)
        #expect(ledger.assetTotals(at: date) == [Ledger.Total(currencyCode: "VND", amount: 82_955_000)])
        #expect(ledger.assetSections(at: date).first?.assets.first?.value == .amount(2_955_000))
    }

    @Test func leavesOutAnAssetThatsGone() {
        var ledger = Ledger()
        ledger.save(Self.expense(45_000, from: UUID()))
        #expect(ledger.entries.count == 1)
        #expect(ledger.assets.isEmpty)
    }

    // MARK: Recording changes to assets

    @Test func recordsAChangeToAnAssetsWorthMadeByHand() throws {
        var ledger = Self.ledger()
        var shares = Self.shares
        shares.value = .holding(quantity: 100, price: 125_000)
        shares.valuedAt = LedgerTests.date(7)
        ledger.save(shares, recordingChangeOn: LedgerTests.date(7))

        let entry = try #require(ledger.entries.first)
        #expect(entry.kind == .adjustment(asset: shares.id, isIncrease: true))
        #expect(entry.amount == 500_000)
        #expect(entry.currencyCode == "VND")
        #expect(entry.date == LedgerTests.date(7))
        #expect(entry.flow == .neither)
        #expect(entry.assetChanges.isEmpty)
    }

    @Test func recordsAChangeFromWhatEntriesLeft() throws {
        var ledger = Self.ledger()
        ledger.save(Self.expense(500_000, from: Self.cash.id, day: 5))
        // The person counts 2.8 million in their wallet on the 8th.
        var cash = Self.cash
        cash.value = .amount(2_800_000)
        cash.valuedAt = LedgerTests.date(8)
        ledger.save(cash, recordingChangeOn: LedgerTests.date(8))

        #expect(ledger.entries.first?.kind == .adjustment(asset: cash.id, isIncrease: true))
        #expect(ledger.entries.first?.amount == 300_000)
        // The expense on the 5th is in what they counted.
        #expect(Self.value(of: cash, in: ledger) == .amount(2_800_000))
    }

    @Test(arguments: [
        // A new asset, which is what the person owns, not a change.
        (Asset(kind: .cash, currencyCode: "VND", value: .amount(1), valuedAt: AssetTests.date), true),
        // The same worth, such as a new note.
        (Asset(id: EntryTests.cash.id, kind: .cash, currencyCode: "VND", value: .amount(3_000_000), valuedAt: AssetTests.date, note: "Ví"), true),
        // A worth in another currency, which can't be compared.
        (Asset(id: EntryTests.cash.id, kind: .cash, currencyCode: "USD", value: .amount(120), valuedAt: AssetTests.date), true),
        // No date, as for prices fetched automatically.
        (Asset(id: EntryTests.shares.id, kind: .stock, name: "FPT", currencyCode: "VND", value: .holding(quantity: 100, price: 130_000), valuedAt: AssetTests.date), false),
    ])
    func recordsNoOtherChange(asset: Asset, withDate: Bool) {
        var ledger = Self.ledger()
        ledger.save(asset, recordingChangeOn: withDate ? LedgerTests.date(7) : nil)
        #expect(ledger.entries.isEmpty)
    }

    @Test func leavesTheAssetAsItIsWhenItsChangeIsDeleted() throws {
        var ledger = Self.ledger()
        var cash = Self.cash
        cash.value = .amount(4_000_000)
        cash.valuedAt = LedgerTests.date(7)
        ledger.save(cash, recordingChangeOn: LedgerTests.date(7))
        let adjustment = try #require(ledger.entries.first)

        ledger.deleteEntry(id: adjustment.id)
        #expect(ledger.entries.isEmpty)
        #expect(Self.value(of: cash, in: ledger) == .amount(4_000_000))
    }

    @Test func keepsEntriesOfAnAssetThatsDeleted() throws {
        var ledger = Self.ledger()
        let expense = Self.expense(45_000, from: Self.cash.id)
        let transfer = Self.transfer(
            1_000_000,
            from: Entry.Leg(asset: Self.bank.id, change: 1_000_000),
            to: Entry.Leg(asset: Self.cash.id, change: 1_000_000)
        )
        ledger.save(expense)
        ledger.save(transfer)
        var cash = Self.cash
        cash.value = .amount(0)
        cash.valuedAt = LedgerTests.date(9)
        ledger.save(cash, recordingChangeOn: LedgerTests.date(9))

        ledger.deleteAsset(id: Self.cash.id)

        // Its adjustment goes, and the others stay as they were.
        #expect(Set(ledger.entries.map(\.id)) == [expense.id, transfer.id])
        #expect(ledger.entries.contains(transfer))
        #expect(Self.value(of: Self.bank, in: ledger) == .amount(79_000_000))
    }

    // MARK: Months

    static let november = LedgerTests.calendar.dateInterval(of: .month, for: LedgerTests.date(15))!

    @Test func totalsIncomeAndSpendingInEachCurrency() {
        let ledger = Ledger(entries: [
            Self.income(25_000_000),
            Self.expense(45_000),
            Self.expense(1_000_000, day: 20),
            Self.expense(Decimal(string: "12.5")!, currency: "USD"),
            Self.transfer(2_000_000, from: nil, to: nil),
            Entry(kind: .adjustment(asset: Self.cash.id, isIncrease: true), amount: 5_000_000, currencyCode: "VND", date: LedgerTests.date(5)),
        ])

        let flows = ledger.flows(during: Self.november)

        #expect(flows == [
            Ledger.MoneyFlow(currencyCode: "VND", moneyIn: 25_000_000, moneyOut: 1_045_000),
            Ledger.MoneyFlow(currencyCode: "USD", moneyIn: 0, moneyOut: Decimal(string: "12.5")!),
        ])
        #expect(flows.first?.net == 23_955_000)
        #expect(flows.last?.net == Decimal(string: "-12.5")!)
    }

    @Test func countsAnEntryAtMidnightInTheMonthItStarts() {
        let firstOfDecember = LedgerTests.calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        let lastOfOctober = LedgerTests.calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 59))!
        let ledger = Ledger(entries: [
            Entry(kind: .expense(.food, account: nil), amount: 1, currencyCode: "VND", date: firstOfDecember),
            Entry(kind: .expense(.food, account: nil), amount: 2, currencyCode: "VND", date: lastOfOctober),
            Self.expense(4, day: 1, currency: "VND"),
        ])

        #expect(ledger.flows(during: Self.november).first?.moneyOut == 4)
        #expect(ledger.days(in: LedgerTests.calendar, during: Self.november).count == 1)
        #expect(ledger.dateRange == lastOfOctober...firstOfDecember)
        #expect(Ledger().dateRange == nil)
    }

    @Test func totalsOnlyTheTaggedEntries() {
        var ledger = Ledger(tags: ["Trip"])
        var tagged = Self.expense(3_000_000)
        tagged.tags = ["Trip"]
        ledger.save(tagged)
        ledger.save(Self.expense(45_000))

        #expect(ledger.flows(during: Self.november, taggedWith: "Trip") == [Ledger.MoneyFlow(currencyCode: "VND", moneyOut: 3_000_000)])
        #expect(ledger.flows(during: Self.november, taggedWith: "Work").isEmpty)
    }

    // MARK: Remembering

    @Test func remembersTheCurrenciesOfIncomeAndSpendingButNotTransfers() {
        var ledger = Self.ledger()
        ledger.save(Self.expense(1, currency: "VND"))
        ledger.save(Self.income(1, currency: "USD"))
        ledger.save(Entry(
            kind: .transfer(from: Entry.Leg(asset: Self.dollars.id, change: 1), to: nil),
            amount: 1, currencyCode: "EUR", date: LedgerTests.date(5)
        ))
        #expect(ledger.recentCurrencyCodes == ["USD", "VND"])
    }

    @Test func remembersTheLatestAccountsThatStillExist() {
        var ledger = Self.ledger()
        #expect(ledger.lastAccount(for: .moneyOut) == nil)

        ledger.save(Self.expense(1, from: Self.cash.id, day: 3))
        ledger.save(Self.expense(1, from: Self.bank.id, day: 4))
        ledger.save(Self.income(1, into: Self.bank.id, day: 6))
        #expect(ledger.lastAccount(for: .moneyOut) == Self.bank.id)
        #expect(ledger.lastAccount(for: .moneyIn) == Self.bank.id)

        // The latest expense paid from no account.
        ledger.save(Self.expense(1, day: 5))
        #expect(ledger.lastAccount(for: .moneyOut) == nil)

        ledger.save(Self.income(1, into: Self.cash.id, day: 7))
        ledger.deleteAsset(id: Self.cash.id)
        #expect(ledger.lastAccount(for: .moneyIn) == nil)
    }

    // MARK: The file

    @Test(arguments: [
        Entry.Kind.expense(.drinks, account: EntryTests.cash.id),
        .expense(.other, account: nil),
        .income(.sideJob, account: EntryTests.bank.id),
        .income(.gifts, account: nil),
        .transfer(from: Entry.Leg(asset: EntryTests.bank.id, change: Decimal(string: "12000000.5")!), to: Entry.Leg(asset: EntryTests.shares.id, change: Decimal(string: "0.0001")!)),
        .transfer(from: nil, to: Entry.Leg(asset: EntryTests.gold.id, change: 1)),
        .transfer(from: nil, to: nil),
        .adjustment(asset: EntryTests.gold.id, isIncrease: false),
    ])
    func roundTripsThroughJSON(kind: Entry.Kind) throws {
        let entry = Entry(kind: kind, amount: Decimal(string: "1234567.89")!, currencyCode: "USD", date: LedgerTests.date(5), note: "Ghi chú", tags: ["Work"])
        let decoded = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
    }

    @Test func readsAnExpenseFromBeforeEntries() throws {
        let json = #"""
        {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "amount": "45000", "currency": "VND",
         "category": "food", "date": 0, "note": "Phở"}
        """#
        let entry = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
        #expect(entry.kind == .expense(.food, account: nil))
        #expect(entry.amount == 45_000)
        #expect(entry.note == "Phở")
    }

    @Test func readsAnUnknownIncomeCategoryAsOther() throws {
        let categories = try JSONDecoder().decode([IncomeCategory].self, from: Data(#"["salary", "lottery"]"#.utf8))
        #expect(categories == [.salary, .other])
    }
}

/// Who the money went to or came from, kept with the entry.
struct EntryPartyTests {
    @Test func keepsItsParty() throws {
        let entry = Entry(
            kind: .income(.other, account: nil), amount: 10_000, currencyCode: "VND", date: Date(timeIntervalSinceReferenceDate: 0),
            note: "chuyen tien", party: "PHAM THI THU LAN"
        )
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(Entry.self, from: data) == entry)
    }

    /// One without a party is saved as before, and one from before reads with none.
    @Test func leavesOutAnEmptyParty() throws {
        let entry = Entry(kind: .expense(.food, account: nil), amount: 45_000, currencyCode: "VND", date: Date(timeIntervalSinceReferenceDate: 0))
        let json = try #require(String(data: try JSONEncoder().encode(entry), encoding: .utf8))
        #expect(!json.contains("party"))
        #expect(try JSONDecoder().decode(Entry.self, from: Data(json.utf8)).party == "")
    }
}
