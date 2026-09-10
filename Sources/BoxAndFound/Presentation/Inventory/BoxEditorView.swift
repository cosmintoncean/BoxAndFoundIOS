import PhotosUI
import SwiftUI

/// Creating a box, or editing one.
struct BoxEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var presenter: BoxEditorPresenter
    /// The picker's own binding. Like `@FocusState`, this is the system asking
    /// the view to hold something on its behalf, not screen state — the chosen
    /// bytes go straight to the presenter and are never read back from here.
    @State private var pickedItem: PhotosPickerItem?
    @State private var isConfirmingDelete = false

    init(householdID: String, boxID: String? = nil, userID: String) {
        _presenter = State(
            initialValue: BoxEditorPresenter(
                householdID: householdID,
                boxID: boxID,
                userID: userID
            )
        )
    }

    var body: some View {
        let state = presenter.viewState

        Form {
            if state.isLoading {
                Section { centredProgress }
            } else {
                detailsSection(state)
                photoSection(state)
                itemsSection(state)
                actionsSection(state)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bfBg)
        .navigationTitle(state.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // onMove is how item positions get reordered, and it is unreachable
            // without a way into edit mode.
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(state.saveTitle) {
                    Task { await presenter.saveTapped() }
                }
                .disabled(!state.isSaveEnabled)
            }
        }
        .task { await presenter.appeared() }
        .onChange(of: pickedItem) { _, item in
            Task { await load(item) }
        }
        .onChange(of: state.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .confirmationDialog(
            "Delete this box?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete box", role: .destructive) {
                Task { await presenter.deleteTapped() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everything in it goes too. This cannot be undone.")
        }
    }

    // MARK: - Sections

    private func detailsSection(_ state: BoxEditorViewState) -> some View {
        Section("Box") {
            TextField("Name", text: binding(state.name, presenter.nameChanged))
            TextField("Location", text: binding(state.location, presenter.locationChanged))

            Picker("Room", selection: Binding(
                get: { state.rooms.first(where: \.isSelected)?.id ?? "" },
                set: { presenter.roomSelected($0) }
            )) {
                ForEach(state.rooms) { room in
                    Text(room.name).tag(room.id)
                }
            }

            iconPicker(state)
        }
    }

    private func iconPicker(_ state: BoxEditorViewState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.bfTextMuted)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(state.icons) { option in
                    Button {
                        presenter.iconSelected(option.key)
                    } label: {
                        Image(systemName: option.symbol)
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(option.isSelected ? Color.white : Color.bfText)
                            .background(
                                option.isSelected ? Color.bfAccent : Color.bfSurface2,
                                in: .rect(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.key)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func photoSection(_ state: BoxEditorViewState) -> some View {
        Section("Photo") {
            switch state.photo {
            case .none:
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Add a photo", systemImage: "photo.badge.plus")
                }
            case .picked:
                Label("New photo ready to upload", systemImage: "checkmark.circle")
                    .foregroundStyle(Color.bfGreen)
                removePhotoButton
            case .existing(let url):
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        centredProgress
                    }
                    .frame(height: 160)
                    .clipShape(.rect(cornerRadius: 10))
                    .listRowInsets(EdgeInsets())
                } else {
                    // Signing failed — a deleted object, or a household this
                    // account has left. The box glyph already stands in.
                    Label("Photo unavailable", systemImage: "photo")
                        .foregroundStyle(Color.bfTextMuted)
                }
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Replace photo", systemImage: "photo.badge.plus")
                }
                removePhotoButton
            }
        }
    }

    private var removePhotoButton: some View {
        Button(role: .destructive) {
            pickedItem = nil
            presenter.photoRemoved()
        } label: {
            Label("Remove photo", systemImage: "trash")
        }
    }

    private func itemsSection(_ state: BoxEditorViewState) -> some View {
        Section("Items") {
            ForEach(state.items) { item in
                HStack(spacing: 8) {
                    TextField(
                        "Item",
                        text: binding(item.name) { presenter.itemNameChanged(item.id, to: $0) }
                    )

                    Stepper(
                        value: Binding(
                            get: { item.quantity },
                            set: { presenter.itemQuantityChanged(item.id, by: $0 - item.quantity) }
                        ),
                        in: 1...999
                    ) {
                        Text(item.quantityLabel ?? "×1")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.bfTextMuted)
                            .monospacedDigit()
                    }
                    .fixedSize()

                    if item.isTaken {
                        Image(systemName: "circle.dashed")
                            .font(.caption2)
                            .foregroundStyle(Color.bfTextMuted)
                            .accessibilityLabel("Taken")
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets where state.items.indices.contains(index) {
                    presenter.itemRemoved(state.items[index].id)
                }
            }
            .onMove { presenter.itemsMoved(from: $0, to: $1) }

            HStack {
                TextField("Add an item", text: binding(state.newItemName, presenter.newItemNameChanged))
                    .onSubmit { presenter.addItemTapped() }
                Button("Add") { presenter.addItemTapped() }
                    .disabled(state.newItemName.trimmed.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ state: BoxEditorViewState) -> some View {
        if let notice = state.notice {
            Section {
                Text(notice.text)
                    .font(.subheadline)
                    .foregroundStyle(notice.kind == .error ? Color.bfDanger : Color.bfGreen)
            }
        }

        if state.isDeleteVisible {
            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete box", systemImage: "trash")
                }
                .disabled(state.isSaving)
            }
        }
    }

    private var centredProgress: some View {
        ProgressView().frame(maxWidth: .infinity)
    }

    // MARK: -

    /// The one-way binding every field here uses: read the state, write an
    /// intent. Never a two-way binding into the presenter.
    private func binding(_ value: String, _ set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { value }, set: set)
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        presenter.photoPicked(data: data, fileExtension: ext)
    }
}
