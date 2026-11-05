import RiengtuKit
import SwiftUI

/// The person's tags as chips to tap on and off, with Apple Intelligence's suggestions marked,
/// and a chip to add a new tag. Starter tags show in the app's language (`Tags.displayName`).
struct TagPicker: View {
    @Binding var selection: [String]
    /// The person's tags.
    let tags: [String]
    var suggestion: TagSuggestion?

    @State private var addsTag = false
    @State private var newTagName = ""

    var body: some View {
        ChipFlow {
            ForEach(shownTags, id: \.self) { tag in
                TagChip(name: Tags.displayName(tag), style: style(for: tag)) { toggle(tag) }
            }
            if let newTag = suggestion?.newTag, Tags.match(newTag, in: shownTags) == nil {
                TagChip(name: Tags.displayName(newTag), style: .suggested) { toggle(Tags.stored(newTag)) }
            }
            Button {
                newTagName = ""
                addsTag = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                    Text("New Tag")
                }
                .chipShape(fill: AnyShapeStyle(.fill.tertiary))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
        .alert("New Tag", isPresented: $addsTag) {
            TextField("Name", text: $newTagName)
            Button("Add") {
                let name = Tags.stored(newTagName)
                if !name.isEmpty {
                    let tag = Tags.match(name, in: shownTags) ?? name
                    if !selection.contains(tag) { selection.append(tag) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The person's tags, and ones added in this editor that aren't saved yet.
    private var shownTags: [String] {
        tags + selection.filter { Tags.match($0, in: tags) == nil }
    }

    private func style(for tag: String) -> TagChip.Style {
        if selection.contains(tag) { return .selected }
        if suggestion?.tags.contains(tag) == true { return .suggested }
        return .plain
    }

    private func toggle(_ tag: String) {
        if let index = selection.firstIndex(of: tag) {
            selection.remove(at: index)
        } else {
            selection.append(tag)
        }
    }
}

/// A tag as a capsule: filled when chosen, and tinted with a sparkle when Apple Intelligence
/// suggests it.
struct TagChip: View {
    enum Style {
        case plain, selected, suggested
    }

    let name: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if style == .suggested {
                    Image(systemName: "sparkles")
                        .imageScale(.small)
                        .accessibilityLabel(Text("Suggested"))
                }
                Text(verbatim: name)
                    .fontWeight(style == .selected ? .semibold : .regular)
            }
            .chipShape(fill: fill)
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(style == .selected ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .plain: AnyShapeStyle(.fill.tertiary)
        case .selected: AnyShapeStyle(.tint)
        case .suggested: AnyShapeStyle(.tint.opacity(0.15))
        }
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .plain: AnyShapeStyle(.primary)
        case .selected: AnyShapeStyle(.white)
        case .suggested: AnyShapeStyle(.tint)
        }
    }
}

private extension View {
    func chipShape(fill: AnyShapeStyle) -> some View {
        font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(fill, in: .capsule)
            .contentShape(.capsule)
    }
}

/// Lays its views out in rows, starting a new row when the next view doesn't fit.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(of: subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            // A view wider than the row gets the row's width, and wraps its text.
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

#Preview {
    @Previewable @State var selection = ["Work"]
    Form {
        TagPicker(
            selection: $selection,
            tags: ["Personal", "Family", "Work", "Gift", "Trip"],
            suggestion: TagSuggestion(category: .travel, tags: ["Trip"], newTag: "Phú Quốc trip")
        )
    }
}
