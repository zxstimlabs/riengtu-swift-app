import Foundation
import ImageIO
import Vision

/// Reads the text on a screenshot with Vision, on the device, in Vietnamese and English, for
/// `ScreenshotText`. Apple Intelligence's model reads text, not images.
public enum ScreenshotReader {
    /// The lines of text on an image, and when it was taken, if its data says.
    public static func read(_ data: Data) async throws -> (lines: [ScreenshotText.Line], takenAt: Date?) {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "vi-VN"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: data)
        let lines = observations.compactMap { observation -> ScreenshotText.Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision's boxes start at the bottom left.
            let box = observation.boundingBox
            return ScreenshotText.Line(text: text, minX: box.origin.x, minY: 1 - box.origin.y - box.height, maxY: 1 - box.origin.y)
        }
        return (lines, takenAt(data))
    }

    /// When the image was taken, from its EXIF or PNG data, which a screenshot has.
    static func takenAt(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let text = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? png?[kCGImagePropertyPNGCreationTime] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // The device's time zone, which the photo's time is in.
        formatter.timeZone = .current
        for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
