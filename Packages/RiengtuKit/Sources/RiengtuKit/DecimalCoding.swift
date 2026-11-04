import Foundation

/// Amounts, quantities and prices are stored as text, such as `"125000"` or `"12.5"`, so no digits
/// are lost on the way through a binary floating-point number.
private let numberLocale = Locale(identifier: "en_US_POSIX")

extension KeyedDecodingContainer {
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        let text = try decode(String.self, forKey: key)
        guard let number = Decimal(string: text, locale: numberLocale) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "Not a number: \(text)"
            )
        }
        return number
    }
}

extension KeyedEncodingContainer {
    mutating func encodeDecimal(_ number: Decimal, forKey key: Key) throws {
        try encode(number.description, forKey: key)
    }
}
