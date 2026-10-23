import SwiftUI

/// One level of storage. Passive, like every view here — see `Presenter`.
struct StorageView: View {
    @State private var presenter: StoragePresenter

    private let householdID: String
    private let userID: String

    init(target: StorageTarget, householdID: String, userID: String) {
        self.householdID = householdID
        self.userID = userID
        _presenter = State(
            initialValue: StoragePresenter(target: target, householdID: householdID)
        )
    }

    var body: some View {
        let state = presenter.viewState

        ZStack {
            Color.bfBg.ignoresSafeArea()
            content(state)
        }
        .navigationTitle(state.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(state) }
        .sheet(
            isPresented: Binding(
                get: { state.containerDraft != nil },
                set: { if !$0 { presenter.dismissContainerDraft() } }
            )
        ) {
            if let draft = state.containerDraft {
                containerSheet(draft)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { state.itemDraft != nil },
                set: { if !$0 { presenter.dismissItemDraft() } }
            )
        ) {
            if let draft = state.itemDraft {
                itemSheet(draft)
            }
        }
        .confirmationDialog(
            state.deletePrompt?.title ?? "",
            isPresented: Binding(
                get: { state.deletePrompt != nil },
                set: { if !$0 { presenter.dismissDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await presenter.confirmDeleteTapped() }
            }
            Button("Cancel", role: .cancel) { presenter.dismissDelete() }
        } message: {
            if let prompt = state.deletePrompt {
                Text(prompt.message)
            }
        }
        .task { await presenter.appeared() }
    }

    @ToolbarContentBuilder
    private func toolbar(_ state: StorageViewState) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    presenter.newItemTapped()
                } label: {
                    Label("Add an item here", systemImage: "plus.circle")
                }
                if state.canAddContainer {
                    Button {
                        presenter.newContainerTapped()
                    } label: {
                        Label("New container", systemImage: "square.stack.3d.up")
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add")
        }
    }

    private func containerSheet(_ draft: StorageViewState.ContainerDraft) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Name",
                        text: Binding(
                            get: { draft.name },
                            set: { presenter.containerNameChanged($0) }
                        )
                    )
                }
                Section("Kind") {
                    // A plain list rather than a picker: eleven kinds with
                    // their own symbols read faster laid out than spun
                    // through.
                    ForEach(draft.types) { option in
                        Button {
                            presenter.containerTypeChanged(option.id)
                        } label: {
                            HStack {
                                Image(systemName: option.symbol)
                                    .foregroundStyle(Color.bfAccent)
                                    .frame(width: 28)
                                Text(option.label)
                                    .foregroundStyle(Color.bfText)
                                Spacer(minLength: 0)
                                if option.id == draft.type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.bfAccent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let message = draft.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.bfAccent)
                    }
                }
            }
            .navigationTitle("New container")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presenter.dismissContainerDraft() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await presenter.createContainerTapped() }
                    }
                    .disabled(!draft.canSave)
                }
            }
        }
    }

    private func itemSheet(_ draft: StorageViewState.ItemDraft) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "What is it",
                        text: Binding(
                            get: { draft.name },
                            set: { presenter.itemNameChanged($0) }
                        )
                    )
                    Stepper(
                        "Quantity: \(draft.quantity)",
                        value: Binding(
                            get: { draft.quantity },
                            set: { presenter.itemQuantityChanged($0) }
                        ),
                        in: 1...999
                    )
                } footer: {
                    Text("Things that are not in a box: a drill on a shelf, a bike against the wall.")
                }
                if let message = draft.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.bfAccent)
                    }
                }
            }
            .navigationTitle("Add an item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presenter.dismissItemDraft() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await presenter.addItemTapped() }
                    }
                    .disabled(!draft.canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ state: StorageViewState) -> some View {
        switch state.content {
        case .loading:
            ProgressView()
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.bfTextMuted)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await presenter.retryTapped() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bfAccent)
            }
            .padding(.horizontal, 32)
        case .contents(let contents):
            list(contents)
        }
    }

    private func list(_ contents: StorageViewState.Contents) -> some View {
        List {
            if !contents.path.isEmpty {
                Section {
                    // Where this sits, for someone who arrived four levels in
                    // and cannot see the stack behind them.
                    Text(contents.path.joined(separator: " › "))
                        .font(.caption)
                        .foregroundStyle(Color.bfTextMuted)
                }
                .listRowBackground(Color.bfSurface)
            }

            if let message = contents.emptyMessage {
                Section {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.bfTextMuted)
                }
                .listRowBackground(Color.bfSurface)
            }

            if !contents.containers.isEmpty {
                Section("Containers") {
                    ForEach(contents.containers) { row in
                        NavigationLink {
                            // Erased on purpose. A container opens another
                            // level of this same screen, and a destination
                            // typed as `StorageView` would make this view's
                            // body type contain itself — a type the compiler
                            // cannot finish building. `AnyView` is what stops
                            // the recursion being a static one.
                            AnyView(
                                StorageView(
                                    target: .container(id: row.id),
                                    householdID: householdID,
                                    userID: userID
                                )
                            )
                        } label: {
                            placeRow(row)
                        }
                        .listRowBackground(Color.bfSurface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                presenter.deleteTapped(id: row.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !contents.boxes.isEmpty {
                Section("Boxes") {
                    ForEach(contents.boxes) { row in
                        NavigationLink {
                            BoxDetailView(
                                boxID: row.id,
                                title: row.name,
                                householdID: householdID,
                                userID: userID
                            )
                        } label: {
                            placeRow(row)
                        }
                        .listRowBackground(Color.bfSurface)
                    }
                }
            }

            if !contents.looseItems.isEmpty {
                Section("Loose items") {
                    ForEach(contents.looseItems) { item in
                        looseRow(item)
                            .listRowBackground(Color.bfSurface)
                    }
                }
            }

            if let note = contents.depthNote {
                Section {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color.bfTextMuted)
                }
                .listRowBackground(Color.bfSurface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await presenter.refresh() }
    }

    private func placeRow(_ row: StorageViewState.PlaceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.title3)
                .foregroundStyle(Color.bfAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.bfText)

                HStack(spacing: 6) {
                    if let kind = row.kindLabel {
                        Text(kind)
                        Text("·")
                    }
                    Text(row.detail)
                }
                .font(.caption)
                .foregroundStyle(Color.bfTextMuted)
            }
        }
        .padding(.vertical, 2)
    }

    private func looseRow(_ item: StorageViewState.LooseItemRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isTaken ? "circle.dashed" : "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.isTaken ? Color.bfTextMuted : Color.bfGreen)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .foregroundStyle(item.isTaken ? Color.bfTextMuted : Color.bfText)
                    .strikethrough(item.isTaken, color: .bfTextMuted)

                if !item.tags.isEmpty {
                    Text(item.tags.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Color.bfTextMuted)
                }
            }

            Spacer(minLength: 0)

            if let quantity = item.quantity {
                Text(quantity)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.bfTextMuted)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isTaken ? "\(item.name), taken" : item.name)
    }
}
