import RiengtuKit
import SwiftUI

extension Tags {
    /// A tag as the person reads it: a starter tag, stored in English, in the app's language, and
    /// a tag the person made as they named it.
    static func displayName(_ tag: String) -> String {
        switch match(tag, in: starter) {
        case "Personal": String(localized: "Personal")
        case "Family": String(localized: "Family")
        case "Work": String(localized: "Work")
        case "Gift": String(localized: "Gift")
        case "Trip": String(localized: "Trip")
        default: tag
        }
    }

    /// The tag a name the person typed stands for: a starter tag when it's that tag's name in
    /// English or in the app's language, so "Công việc" is "Work", and otherwise the name.
    static func stored(_ name: String) -> String {
        let name = tidy(name)
        return match(name, in: starter)
            ?? starter.first { match(name, in: [displayName($0)]) != nil }
            ?? name
    }
}
