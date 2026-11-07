import Foundation

/// Finds the transactions on a screenshot of a bank app's history, such as Techcombank's "Biến
/// động số dư", in the lines of text recognized on it (`ScreenshotReader`), to add transactions
/// from before the inbox was set up.
///
/// A history groups transactions by day, under a heading such as "Thứ Ba, 3 Thg 11, 2026" or
/// "Hôm qua", with space between them. Each transaction is a block of lines with an amount, and
/// often its time on the right. Each block becomes a message for the inbox to read, as a bank's
/// notification would be.
public enum ScreenshotText {
    /// A line of text and where it is, from the top left, as fractions of the image's size.
    public struct Line: Equatable, Sendable {
        public var text: String
        public var minX: Double
        public var minY: Double
        public var maxY: Double

        public init(text: String, minX: Double, minY: Double, maxY: Double) {
            self.text = text
            self.minX = minX
            self.minY = minY
            self.maxY = maxY
        }
    }

    /// A transaction found on a screenshot.
    public struct Transaction: Equatable, Sendable {
        /// Its lines, a wrapped line joined up, without buttons, and its time on the last line.
        public var text: String
        /// Its day's heading and its time, or the start of its day without a time.
        public var date: Date
        /// Whether its day is a guess, since there was no heading above it on the screenshot.
        public var isDayGuessed: Bool
    }

    /// Buttons beside each transaction, which aren't part of it.
    private static let buttons: Set<String> = ["sao chep", "copy", "chia se", "share", "chi tiet", "details"]

    /// The transactions on a screenshot taken at `takenAt`, top to bottom.
    public static func transactions(in lines: [Line], takenAt: Date, timeZone: TimeZone) -> [Transaction] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let blocks = blocks(of: rows(of: lines.filter { !buttons.contains(clean($0.text)) })) { row in
            day(in: row.text, takenAt: takenAt, calendar: calendar) != nil
        }

        var found: [(text: String, day: Date?, time: DateComponents?)] = []
        var day: Date?
        var firstHeading: Date?
        for (index, block) in blocks.enumerated() {
            if block.count == 1, let heading = self.day(in: block[0].text, takenAt: takenAt, calendar: calendar) {
                day = heading
                firstHeading = firstHeading ?? heading
                continue
            }
            var time: DateComponents?
            var texts: [String] = []
            for row in block {
                var items = row.items
                if let index = items.lastIndex(where: { timeOfDay($0.text) != nil }), items.count > 1 || row.items[0].minX > 0.5 {
                    time = timeOfDay(items[index].text)
                    items.remove(at: index)
                }
                guard !items.isEmpty else { continue }
                let text = items.map(\.text).joined(separator: " ")
                // A line that wraps goes on from one without a label.
                if let last = texts.last, !isLabeled(last), !isLabeled(text), texts.count > 1 {
                    texts[texts.count - 1] = last + " " + text
                } else {
                    texts.append(text)
                }
            }
            let text = texts.joined(separator: "\n")
            guard TransactionText.amounts(in: text).contains(where: { !$0.isBalance }) else { continue }
            // Cut off at the bottom of the screen: whole on another screenshot, if anywhere.
            if time == nil, index == blocks.count - 1, block.last!.maxY > 0.95 { continue }
            let shownTime = time.map { String(format: "%02d:%02d", $0.hour!, $0.minute!) }
            // On its own line, so it isn't taken for part of the description.
            found.append((shownTime.map { text + "\n" + $0 } ?? text, day, time))
        }

        // Above the first heading, the day is the one after it, or the day it was taken.
        let takenDay = calendar.startOfDay(for: takenAt)
        let guessedDay = firstHeading.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }.map { min($0, takenDay) } ?? takenDay
        return found.map { item in
            let day = item.day ?? guessedDay
            let date = item.time.flatMap { calendar.date(bySettingHour: $0.hour!, minute: $0.minute!, second: 0, of: day) } ?? day
            return Transaction(text: item.text, date: date, isDayGuessed: item.day == nil)
        }
    }

    // MARK: Rows and blocks

    private struct Row {
        var minY: Double
        var maxY: Double
        var items: [Line]
        var text: String { items.map(\.text).joined(separator: " ") }
    }

    /// Lines side by side, such as a description and its time, make one row, left to right.
    private static func rows(of lines: [Line]) -> [Row] {
        var rows: [Row] = []
        for line in lines.sorted(by: { $0.minY < $1.minY }) {
            let height = line.maxY - line.minY
            if let last = rows.last, abs(line.minY - last.minY) < max(height, last.maxY - last.minY) * 0.5 {
                rows[rows.count - 1].items.append(line)
                rows[rows.count - 1].maxY = max(last.maxY, line.maxY)
            } else {
                rows.append(Row(minY: line.minY, maxY: line.maxY, items: [line]))
            }
        }
        return rows.map { row in
            var row = row
            row.items.sort { $0.minX < $1.minX }
            return row
        }
    }

    /// Rows with more space between them than between the lines of a transaction start a new
    /// block, and a day's heading is a block of its own. The space allowed is generous, since
    /// Vision sometimes misses a line.
    private static func blocks(of rows: [Row], isHeading: (Row) -> Bool) -> [[Row]] {
        guard rows.count > 1 else { return rows.map { [$0] } }
        let steps = zip(rows, rows.dropFirst()).map { $1.minY - $0.minY }
        let lineStep = steps.sorted()[steps.count / 2]
        var blocks: [[Row]] = [[rows[0]]]
        for (previous, row) in zip(rows, rows.dropFirst()) {
            if row.minY - previous.minY > max(lineStep * 2.2, 0.03) || isHeading(row) || isHeading(previous) {
                blocks.append([row])
            } else {
                blocks[blocks.count - 1].append(row)
            }
        }
        return blocks
    }

    // MARK: Lines

    private static func clean(_ text: String) -> String {
        TransactionText.fold(text.precomposedStringWithCanonicalMapping)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static let labeled = try! NSRegularExpression(pattern: #"^[^\d:：]{1,30}[:：]"#)

    /// Whether a line starts with a label, such as "Số dư:".
    private static func isLabeled(_ text: String) -> Bool {
        labeled.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let time = try! NSRegularExpression(pattern: #"^(\d{1,2})[:h](\d{2})$"#)

    /// The time a line is, such as "09:51", alone.
    private static func timeOfDay(_ text: String) -> DateComponents? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let match = time.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hour = Range(match.range(at: 1), in: text).flatMap({ Int(text[$0]) }),
              let minute = Range(match.range(at: 2), in: text).flatMap({ Int(text[$0]) }),
              hour < 24, minute < 60
        else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }

    // MARK: Days

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "Thứ Ba, 3 Thg 11, 2026", "3 tháng 11", "03/11/2026", "Tuesday, 3 November 2026" or
    /// "Nov 3, 2026", alone. Folded, so without diacritics.
    private static let dayPatterns = [
        #"^(?:[a-z ]+,\s*)?(?<day>\d{1,2})\s*(?:thg|thang)\s*(?<month>\d{1,2})(?:,?\s*(?<year>\d{4}))?$"#,
        #"^(?:[a-z ]+,\s*)?(?<day>\d{1,2})[/.\-](?<month>\d{1,2})(?:[/.\-](?<year>\d{4}))?$"#,
        #"^(?:[a-z]+,\s*)?(?<day>\d{1,2})\s+(?<monthName>[a-z]{3})[a-z]*,?(?:\s+(?<year>\d{4}))?$"#,
        #"^(?:[a-z]+,\s*)?(?<monthName>[a-z]{3})[a-z]*\s+(?<day>\d{1,2}),?(?:\s+(?<year>\d{4}))?$"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// The day a heading names, at its start, or `nil` if it isn't a heading.
    static func day(in heading: String, takenAt: Date, calendar: Calendar) -> Date? {
        let text = TransactionText.fold(heading.precomposedStringWithCanonicalMapping)
            .trimmingCharacters(in: .whitespaces)
        let takenDay = calendar.startOfDay(for: takenAt)
        switch text {
        case "hom nay", "today": return takenDay
        case "hom qua", "yesterday": return calendar.date(byAdding: .day, value: -1, to: takenDay)
        default: break
        }
        for pattern in dayPatterns {
            guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            func group(_ name: String) -> String? {
                Range(match.range(withName: name), in: text).map { String(text[$0]) }
            }
            let month = group("month").flatMap(Int.init)
                ?? group("monthName").flatMap { name in months.firstIndex(of: name).map { $0 + 1 } }
            guard let day = group("day").flatMap(Int.init), let month else { continue }
            var year = group("year").flatMap(Int.init) ?? calendar.component(.year, from: takenAt)
            // A heading without a year, for a month after this one, is from last year.
            if group("year") == nil, month > calendar.component(.month, from: takenAt) { year -= 1 }
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.day, from: date) == day
            else { continue }
            return date
        }
        return nil
    }
}
