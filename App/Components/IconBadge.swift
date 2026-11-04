import SwiftUI

/// A symbol in a circle of its color, for expense categories and kinds of asset.
struct IconBadge: View {
    let symbolName: String
    let color: Color
    var isSelected = false

    @ScaledMetric(relativeTo: .body) private var size = 36

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(color))
            .frame(width: size, height: size)
            .background(color.opacity(isSelected ? 1 : 0.15), in: .circle)
            .accessibilityHidden(true)
    }
}
