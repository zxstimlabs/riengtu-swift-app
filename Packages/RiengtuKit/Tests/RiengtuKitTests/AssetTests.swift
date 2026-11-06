import Foundation
import Testing
@testable import RiengtuKit

struct AssetTests {
    static let date = Date(timeIntervalSince1970: 1_793_000_000)

    static func asset(
        _ kind: AssetKind, name: String = "", currency: String = "VND", _ value: Asset.Value
    ) -> Asset {
        Asset(kind: kind, name: name, currencyCode: currency, value: value, valuedAt: date)
    }

    @Test func isWorthItsAmount() {
        #expect(Self.asset(.bankAccount, .amount(25_000_000)).worth == 25_000_000)
    }

    @Test func isWorthItsQuantityTimesItsPrice() {
        let shares = Self.asset(.stock, name: "FPT", .holding(quantity: 1_000, price: 125_500))
        #expect(shares.worth == 125_500_000)
    }

    @Test(arguments: [
        // 5 chỉ is half a lượng.
        (Decimal(5), GoldUnit.chi, Decimal(150_000_000), GoldUnit.luong, Decimal(75_000_000)),
        (Decimal(2), .luong, 15_000_000, .chi, 300_000_000),
        (Decimal(10), .gram, 150_000_000, .luong, 40_000_000),
        (Decimal(string: "1.5")!, .chi, 15_000_000, .chi, 22_500_000),
    ])
    func isWorthItsGoldsWeightAtItsPrice(
        weight: Decimal, unit: GoldUnit, price: Decimal, priceUnit: GoldUnit, worth: Decimal
    ) {
        let gold = Self.asset(.gold, .gold(weight: weight, unit: unit, price: price, priceUnit: priceUnit))
        #expect(gold.worth == worth)
    }

    @Test func roundsItsWorthToTheCurrencysDigits() {
        // A gram is 1/37.5 of a lượng: 2.666.666,67 ₫, and the đồng has no fraction.
        let gram = Self.asset(.gold, .gold(weight: 1, unit: .gram, price: 100_000_000, priceUnit: .luong))
        #expect(gram.worth == 2_666_667)

        let coins = Self.asset(.crypto, name: "BTC", currency: "USD", .holding(quantity: Decimal(string: "0.12345678")!, price: 68_000))
        #expect(coins.worth == Decimal(string: "8395.06")!)
    }

    @Test(arguments: [
        Asset.Value.amount(Decimal(string: "1234567890123.45")!),
        .holding(quantity: Decimal(string: "0.00012345")!, price: Decimal(string: "68123.45")!),
        .gold(weight: Decimal(string: "2.5")!, unit: .chi, price: 148_500_000, priceUnit: .luong),
    ])
    func roundTripsThroughJSONWithoutLosingDigits(value: Asset.Value) throws {
        let asset = Asset(kind: .other, name: "Tên", currencyCode: "USD", value: value, valuedAt: Self.date, note: "Ghi chú")
        let decoded = try JSONDecoder().decode(Asset.self, from: JSONEncoder().encode(asset))
        #expect(decoded == asset)
    }

    @Test func storesGoldWithItsUnits() throws {
        let gold = Self.asset(.gold, .gold(weight: 5, unit: .chi, price: 148_500_000, priceUnit: .luong))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(gold)) as! [String: Any]
        #expect(json["weight"] as? String == "5")
        #expect(json["weightUnit"] as? String == "chi")
        #expect(json["price"] as? String == "148500000")
        #expect(json["priceUnit"] as? String == "luong")
        #expect(json["currency"] as? String == "VND")
        #expect(json["name"] == nil)
        #expect(json["note"] == nil)
    }

    @Test func readsAnUnknownKindAsOtherAndKeepsItsValue() throws {
        let json = #"""
        {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "kind": "artwork", "currency": "VND",
         "amount": "50000000", "valuedAt": 0}
        """#
        let asset = try JSONDecoder().decode(Asset.self, from: Data(json.utf8))
        #expect(asset.kind == .other)
        #expect(asset.value == .amount(50_000_000))
    }

    @Test func groupsEveryKind() {
        for group in AssetKind.Group.allCases {
            #expect(!AssetKind.kinds(in: group).isEmpty)
        }
        let grouped = AssetKind.Group.allCases.flatMap(AssetKind.kinds(in:))
        #expect(grouped == AssetKind.allCases)
    }
}

struct LedgerAssetTests {
    static func asset(_ kind: AssetKind, name: String = "", currency: String = "VND", amount: Decimal = 1_000_000) -> Asset {
        Asset(kind: kind, name: name, currencyCode: currency, value: .amount(amount), valuedAt: AssetTests.date)
    }

    @Test func addsAssetsAndReplacesOneWithTheSameIDWhereItIs() {
        var ledger = Ledger()
        var first = Self.asset(.cash)
        let second = Self.asset(.vehicle)
        ledger.save(first)
        ledger.save(second)

        first.value = .amount(2_000_000)
        ledger.save(first)

        #expect(ledger.assets == [first, second])
        #expect(ledger.asset(id: first.id)?.worth == 2_000_000)
    }

    @Test func deletesAnAsset() {
        var ledger = Ledger()
        let kept = Self.asset(.cash)
        let deleted = Self.asset(.property)
        ledger.save(kept)
        ledger.save(deleted)
        ledger.deleteAsset(id: deleted.id)
        #expect(ledger.assets == [kept])
    }

    @Test func leavesTheRecentCurrenciesAlone() {
        var ledger = Ledger(recentCurrencyCodes: ["VND"])
        ledger.save(Self.asset(.cash, currency: "USD"))
        #expect(ledger.recentCurrencyCodes == ["VND"])
    }

    @Test func listsAssetsByGroupThenKindThenName() {
        let car = Self.asset(.vehicle, name: "Xe hơi")
        let vcb = Self.asset(.bankAccount, name: "Vietcombank")
        let acb = Self.asset(.bankAccount, name: "ACB")
        let wallet = Self.asset(.cash, name: "Ví")
        let fpt = Self.asset(.stock, name: "FPT")
        let ledger = Ledger(assets: [car, vcb, fpt, acb, wallet])

        let sections = ledger.assetSections()

        #expect(sections.map(\.group) == [.money, .investments, .things])
        #expect(sections.map { $0.assets.map(\.name) } == [["Ví", "ACB", "Vietcombank"], ["FPT"], ["Xe hơi"]])
    }

    @Test func leavesOutGroupsWithNoAssets() {
        let ledger = Ledger(assets: [Self.asset(.property)])
        #expect(ledger.assetSections().map(\.group) == [.things])
        #expect(Ledger().assetSections().isEmpty)
    }

    @Test func totalsEachCurrencyOnItsOwn() {
        let ledger = Ledger(assets: [
            Self.asset(.cash, currency: "USD", amount: 200),
            Self.asset(.bankAccount, amount: 25_000_000),
            Asset(kind: .stock, name: "FPT", currencyCode: "VND", value: .holding(quantity: 100, price: 125_500), valuedAt: AssetTests.date),
            Self.asset(.cash, currency: "USD", amount: Decimal(string: "0.5")!),
            Self.asset(.savings, amount: 100_000_000),
        ])

        #expect(ledger.assetTotals() == [
            Ledger.Total(currencyCode: "VND", amount: 137_550_000),
            Ledger.Total(currencyCode: "USD", amount: Decimal(string: "200.5")!),
        ])
        #expect(Ledger().assetTotals().isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let ledger = Ledger(
            entries: [LedgerTests.expense(day: 1)],
            assets: [Self.asset(.cash), Self.asset(.gold, name: "SJC")],
            recentCurrencyCodes: ["VND"]
        )
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
    }
}
