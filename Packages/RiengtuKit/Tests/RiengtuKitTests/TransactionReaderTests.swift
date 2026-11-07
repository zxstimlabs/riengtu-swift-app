import Foundation
import Testing
@testable import RiengtuKit

/// Runs the Apple Intelligence model on sample notices, on a Mac with it turned on. Checks what
/// matters for Add All: what kind it is, and where income came from. The inbox checks
/// the amount with the rules (`InboxTests`).
@Suite(.enabled(if: ExpenseTagger.availability == .available, "Needs Apple Intelligence"))
struct TransactionReaderTests {
    struct Sample: CustomTestStringConvertible, Sendable {
        var text: String
        var kind: TransactionReader.Kind
        var incomeCategory: IncomeCategory? = nil

        var testDescription: String { String(text.prefix(40)) }
    }

    static let samples: [Sample] = [
        Sample(text: """
            - VND 25,000
            Tài khoản: 1234567890
            Số dư: VND 16,181,570
            NGUYEN VAN AN chuyen tien. Ma tham chieu 123456
            """, kind: .spending), // A QR payment, which the bank words like this.
        Sample(text: """
            - VND 2,042,000
            Tài khoản: 1234567890
            Số dư: VND 16,206,570
            Thanh toan no the tin dung _ So tien 2042000 VND _ Ngay 05/11/2026
            """, kind: .transfer),
        Sample(text: """
            + VND 15,000,000
            Tài khoản: 1234567890
            Số dư: VND 31,206,570
            CONG TY TNHH ABC tra luong thang 10
            """, kind: .income, incomeCategory: .salary),
        Sample(text: """
            + VND 500,000
            Tài khoản: 1234567890
            Số dư: VND 16,706,570
            TRAN THI BINH chuyen tien tra tien an toi
            """, kind: .income, incomeCategory: .other),
        // From Techcombank's history, as Vision reads a screenshot of it, "trả" misread.
        Sample(text: """
            Thẻ: 4 .... .... 1234
            Số tiền: + VND 51,000
            Giao dịch hoàn trà từ .OP*Green SM
            21:30
            """, kind: .income),
        Sample(text: """
            Tài khoản 1234567890
            Số tiền GD: - 1,504,246
            Số dư: 18,475,880
            Thanh toan dich vu Dien cho CONG TY DIEN LUC SAI GON cho Ma HD PE02000123456 - 1504246 VND - 03/11/2026 06:19:40
            06:19
            """, kind: .spending),
        Sample(text: """
            Thẻ: 4 .... .... 1234
            Số tiền: - VND 90,000
            Hạn mức khả dụng tạm tính: VND 66,766,000
            Thanh toán tại .OP*Green SM
            22:00
            """, kind: .spending),
        // Techcombank's "Sinh lời tự động" profit.
        Sample(text: """
            + VND 1,890
            Ting ting! Lợi nhuận Sinh lời tự động đã về
            """, kind: .income, incomeCategory: .investment),
        Sample(text: """
            Số tiền giao dịch: -150,000 VND
            Số dư hiện tại: 12,345,678 VND
            Thời gian: 05/11/2026 12:30:01
            Nội dung giao dịch: CHUYEN TIEN AN TRUA
            """, kind: .spending),
        Sample(text: """
            TK 1234567890 -2,000,000 VND luc 05-11-2026 09:00. SD 10,000,000 VND. ND: Nap tien vao vi MoMo
            """, kind: .transfer),
        Sample(text: """
            TK 1234567890 -1,200,000 VND luc 05-11-2026 18:20. SD 8,800,000 VND. ND: Thanh toan tien dien thang 10 EVN
            """, kind: .spending),
        Sample(text: """
            TK 1234567890 +35,000 VND luc 05-11-2026 08:00. SD 8,835,000 VND. ND: Lai tien gui thang 10
            """, kind: .income, incomeCategory: .investment),
    ]

    @Test(arguments: samples)
    func readsWhichWayAndWhatKind(sample: Sample) async throws {
        // As the inbox asks it.
        let answer = try await TransactionReader.read(sample.text)
        print("ANSWER", sample.testDescription.replacingOccurrences(of: "\n", with: " | "), "→", answer)
        #expect(answer.kind == sample.kind)
        if let category = sample.incomeCategory {
            #expect(answer.incomeCategory == category)
        }
    }
}
