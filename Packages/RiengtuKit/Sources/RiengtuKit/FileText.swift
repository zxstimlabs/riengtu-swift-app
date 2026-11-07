import Foundation

/// Turns a file the person picks into messages for the inbox, one for each transaction in it, to
/// be read as a bank's notification is: what the rules can tell, then Apple Intelligence for
/// meaning. No format is one bank's or app's:
///
/// - CSV or TSV, such as a bank's or another app's export: a row each, as its columns' names and
///   values ("Ngày: 05/11/2026", "Ghi nợ: 33,000").
/// - JSON: an object each, from the longest list of objects in it, as its keys and values.
/// - Text, such as copied messages: a paragraph each, or a line each when the lines each have an
///   amount.
public enum FileText {
    /// The most taken from one file, so a huge file doesn't fill the inbox.
    public static let maximumCount = 500

    /// The messages in a file, by its extension, or by what it looks like when that doesn't say.
    public static func messages(in data: Data, fileExtension: String) -> [String] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { return [] }
        let messages: [String]
        switch fileExtension.lowercased() {
        case "json": messages = json(text) ?? paragraphs(text)
        case "csv", "tsv": messages = table(text) ?? paragraphs(text)
        default:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") || trimmed.hasPrefix("{"), let json = json(text) {
                messages = json
            } else if let table = table(text), table.count > 1 {
                messages = table
            } else {
                messages = paragraphs(text)
            }
        }
        return Array(messages.filter { $0.contains(where: \.isNumber) }.prefix(maximumCount))
    }

    // MARK: Tables

    /// A row each, as "column: value" lines, from a header row and the rows under it. `nil` when
    /// it doesn't look like a table.
    static func table(_ text: String) -> [String]? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1, let header = lines.first else { return nil }
        // The separator the header has most of.
        guard let separator = [Character("\t"), ";", ","].max(by: { a, b in header.count { $0 == a } < header.count { $0 == b } }),
              header.contains(separator)
        else { return nil }
        let columns = fields(header, separator: separator).map { $0.trimmingCharacters(in: .whitespaces) }
        // Columns' names, not a row of values such as "05/11 -45,000 VND", whose comma groups
        // digits; and most rows as many fields as there are columns.
        guard columns.count > 1, !header.contains(where: \.isNumber) else { return nil }
        let rows = lines.dropFirst()
        guard rows.count { fields($0, separator: separator).count == columns.count } * 5 >= rows.count * 4 else { return nil }
        return rows.map { line in
            zip(columns, fields(line, separator: separator))
                .map { ($0, $1.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.1.isEmpty }
                .map { $0.0.isEmpty ? $0.1 : "\($0.0): \($0.1)" }
                .joined(separator: "\n")
        }
    }

    /// A line's fields, where a field in double quotes can have the separator in it.
    static func fields(_ line: String, separator: Character) -> [String] {
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var previous: Character?
        for character in line {
            if character == "\"" {
                // Two quotes in a quoted field are one.
                if isQuoted, previous == "\"" { field.append("\"") }
                isQuoted.toggle()
            } else if character == separator, !isQuoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            previous = character
        }
        fields.append(field)
        return fields
    }

    // MARK: JSON

    /// An object each, from the longest list of objects anywhere in it.
    static func json(_ text: String) -> [String]? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        guard let list = longestList(in: root), !list.isEmpty else { return nil }
        return list.map { lines(of: $0).joined(separator: "\n") }
    }

    private static func longestList(in value: Any) -> [[String: Any]]? {
        var best: [[String: Any]]?
        func visit(_ value: Any) {
            if let array = value as? [Any] {
                let objects = array.compactMap { $0 as? [String: Any] }
                if objects.count == array.count, objects.count > (best?.count ?? 0) { best = objects }
                array.forEach(visit)
            } else if let object = value as? [String: Any] {
                object.values.forEach(visit)
            }
        }
        visit(value)
        return best
    }

    /// "key: value" for each value, keys sorted so the same object always reads the same; a nested
    /// object's as "key.inner: value".
    private static func lines(of object: [String: Any], prefix: String = "") -> [String] {
        object.keys.sorted().flatMap { key -> [String] in
            let name = prefix.isEmpty ? key : prefix + "." + key
            switch object[key] {
            case let inner as [String: Any]: return lines(of: inner, prefix: name)
            case let number as NSNumber:
                // Not a Bool's 1 or 0.
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return [] }
                return ["\(name): \(number.decimalValue)"]
            case let string as String: return string.isEmpty ? [] : ["\(name): \(string)"]
            default: return []
            }
        }
    }

    // MARK: Text

    /// A paragraph each, or, in one paragraph whose lines each have an amount, a line each.
    static func paragraphs(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.count == 1, let only = paragraphs.first {
            let lines = only.split(whereSeparator: \.isNewline).map(String.init)
            if lines.count > 1, lines.allSatisfy({ !TransactionText.amounts(in: $0).isEmpty }) { return lines }
        }
        return paragraphs
    }
}
