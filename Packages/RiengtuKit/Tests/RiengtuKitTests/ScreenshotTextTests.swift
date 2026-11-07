import Foundation
import Testing
@testable import RiengtuKit

/// The lines Vision reads on screenshots of Techcombank's history, with the account number, card
/// number and name changed.
struct ScreenshotTextTests {
    static let vietnam = TransactionTextTests.vietnam

    static func line(_ text: String, _ x: Double, _ y: Double) -> ScreenshotText.Line {
        ScreenshotText.Line(text: text, minX: x, minY: y, maxY: y + 0.012)
    }

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        TransactionTextTests.date(day, hour, minute)
    }

    /// Taken on 6 November at 11:43.
    static let takenAt = date(6, 11, 43)

    /// The top of the account's history: today's heading scrolled away, then yesterday's.
    static let accountHistory = [
        line("11:43", 0.108, 0.019), line("Biến động số dư", 0.054, 0.117),
        line("Tài khoản", 0.103, 0.179), line("Thẻ tín dụng", 0.379, 0.183),
        line("Tài khoàn 1234567890", 0.042, 0.233), line("Sao chép", 0.817, 0.233),
        line("Số tiền GD: - 90,000", 0.042, 0.250), line("Số dư: 16,091,570", 0.042, 0.267),
        line("NGUYEN VAN AN chuyen tien", 0.042, 0.283), line("10:35", 0.867, 0.281),
        line("Tài khoản 1234567890", 0.042, 0.335), line("Sao chép", 0.817, 0.333),
        line("Số tiền GD: - 25,000", 0.042, 0.352), line("Số dư: 16,181,570", 0.042, 0.365),
        line("NGUYEN VAN AN chuyen tien. Ma tham", 0.042, 0.383), line("chieu 123456", 0.042, 0.400), line("08:19", 0.862, 0.398),
        line("Hôm qua", 0.042, 0.463),
        line("Tài khoàn 1234567890", 0.042, 0.504), line("Sao chép", 0.816, 0.505),
        line("Số tiền GD: - 2,042,000", 0.042, 0.521), line("Số dư: 16,206,570", 0.041, 0.535),
        line("Thanh toan no the tin dung _ So tien 2042000 VND", 0.042, 0.552), line("_ Ngay 05/11/2026", 0.042, 0.569),
        line("23:06", 0.862, 0.571),
        // Cut off at the bottom.
        line("Tài khoản 1234567890", 0.042, 0.944), line("Sao chép", 0.817, 0.944),
        line("Số tiền GD: + 1,690", 0.041, 0.959), line("Số dư: 18,328,570", 0.041, 0.976),
    ]

    @Test func findsTheTransactionsOnAHistory() throws {
        let found = ScreenshotText.transactions(in: Self.accountHistory, takenAt: Self.takenAt, timeZone: Self.vietnam)
        #expect(found.map(\.date) == [Self.date(6, 10, 35), Self.date(6, 8, 19), Self.date(5, 23, 6)])
        #expect(found.map(\.isDayGuessed) == [true, true, false])
        #expect(found[1].text == "Tài khoản 1234567890\nSố tiền GD: - 25,000\nSố dư: 16,181,570\nNGUYEN VAN AN chuyen tien. Ma tham chieu 123456\n08:19")
        #expect(found[2].text.contains("Thanh toan no the tin dung _ So tien 2042000 VND _ Ngay 05/11/2026"))
    }

    /// A card's history, where Vision missed a transaction's first line.
    @Test func keepsATransactionTogetherWhenALineIsMissing() throws {
        let lines = [
            Self.line("Thứ Hai, 2 Thg 11, 2026", 0.042, 0.529),
            Self.line("Thẻ: 4 .... .... 1234", 0.049, 0.575), Self.line("Sao chép", 0.817, 0.573),
            Self.line("Số tiền: + VND 51,000", 0.049, 0.589), Self.line("Giao dịch hoàn trà từ .OP*Green SM", 0.042, 0.606),
            Self.line("21:30", 0.867, 0.608),
            Self.line("Th tiển : - VND 35,000", 0.037, 0.760), Self.line("Sao chép", 0.817, 0.760),
            Self.line("Hạn mức khà dụng tạm tính: VND 66,925,000", 0.042, 0.790),
            Self.line("Thanh toán tại .OP*Green SM", 0.042, 0.812), Self.line("13:37", 0.867, 0.810),
        ]
        let found = ScreenshotText.transactions(in: lines, takenAt: Self.takenAt, timeZone: Self.vietnam)
        #expect(found.map(\.date) == [Self.date(2, 21, 30), Self.date(2, 13, 37)])
        #expect(found[1].text.contains("Thanh toán tại .OP*Green SM"))
        #expect(TransactionText.read(found[1].text).amount == 35_000)
    }

    @Test(arguments: [
        ("Thứ Ba, 3 Thg 11, 2026", 3), ("Chủ Nhật, 1 Thg 11, 2026", 1), ("03/11/2026", 3), ("3 tháng 11", 3),
        ("Tuesday, 3 November 2026", 3), ("Nov 3, 2026", 3), ("Hôm nay", 6), ("Hôm qua", 5), ("Yesterday", 5),
    ])
    func readsADaysHeading(heading: String, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.vietnam
        #expect(ScreenshotText.day(in: heading, takenAt: Self.takenAt, calendar: calendar) == Self.date(day))
    }

    @Test(arguments: ["Thanh toán tại .OP*Green SM", "Số dư: 18,384,880", "Biến động số dư", "11:43"])
    func readsNoDayFromOtherLines(text: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.vietnam
        #expect(ScreenshotText.day(in: text, takenAt: Self.takenAt, calendar: calendar) == nil)
    }
}
