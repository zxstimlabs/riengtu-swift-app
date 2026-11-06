import RiengtuKit
import SwiftUI

/// The person's tags, with how many entries have each. Tap one to rename it, swipe to delete it.
struct TagsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var addsTag = false
    @State private var renaming: String?
    @State private var deleting: String?
    @State private var name = ""
    @State private var saveFailed = false

    var body: some View {
        let tags = store.ledger.tags
        List {
            ForEach(tags, id: \.self) { tag in
                Button {
                    name = Tags.displayName(tag)
                    renaming = tag
                } label: {
                    LabeledContent {
                        Text(store.ledger.entryCount(taggedWith: tag), format: .number)
                    } label: {
                        Text(verbatim: Tags.displayName(tag))
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleting = tag
                    }
                }
            }
        }
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView {
                    Label("No Tags", systemImage: "tag")
                } description: {
                    Text("Tags say what money was spent or received for, such as work or a trip.")
                }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Tag", systemImage: "plus") {
                    name = ""
                    addsTag = true
                }
            }
        }
        .alert("New Tag", isPresented: $addsTag) {
            TextField("Name", text: $name)
            Button("Add") { change { try store.addTag(Tags.stored(name)) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Tag", isPresented: isPresent($renaming), presenting: renaming) { tag in
            TextField("Name", text: $name)
            Button("Rename") { change { try store.renameTag(tag, to: Tags.stored(name)) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this tag?", isPresented: isPresent($deleting), titleVisibility: .visible, presenting: deleting) { tag in
            Button("Delete Tag", role: .destructive) { change { try store.deleteTag(tag) } }
        } message: { tag in
            Text("“\(Tags.displayName(tag))” comes off every transaction that has it. The transactions stay.")
        }
        .alert("Couldn’t Save", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
        }
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            saveFailed = true
        }
    }

    /// Whether `value` is set, as a binding that clears it when set to false.
    private func isPresent(_ value: Binding<String?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

#Preview {
    NavigationStack {
        TagsView()
    }
    .previewEnvironment()
}
