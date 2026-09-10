import SwiftUI

/// The box list: a household switcher, a search field, and boxes grouped by
/// room. Passive, like every view here — see `Presenter`.
struct InventoryView: View {
    @State private var presenter: InventoryPresenter
    /// Navigation is genuinely the view's: the stack owns it, and the
    /// presenter has no opinion about how a screen got here. It is watched
    /// only so returning to the list can reload what the pushed screen wrote.
    @State private var path: [Route] = []

    private let userID: String

    private enum Route: Hashable {
        case box(InventoryViewState.BoxRow)
        case newBox
    }

    init(userID: String, signOut: @escaping @MainActor () async -> Void) {
        self.userID = userID
        _presenter = State(initialValue: InventoryPresenter(userID: userID, signOut: signOut))
    }

    var body: some View {
        let state = presenter.viewState

        NavigationStack(path: $path) {
            content(state)
                .navigationTitle(state.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(state) }
                .navigationDestination(for: Route.self) { route in
                    destination(route, householdID: state.activeHouseholdID)
                }
                .searchableWhen(
                    state.isSearchVisible,
                    text: Binding(
                        get: { state.searchTerm },
                        set: { presenter.searchChanged($0) }
                    ),
                    prompt: "Search boxes and items"
                )
                .refreshable { await presenter.refresh() }
        }
        .tint(.bfAccent)
        .task { await presenter.appeared() }
        .onChange(of: path) { previous, current in
            // Back at the list. Whatever the pushed screen wrote — a taken
            // item, a renamed box, a deleted one — the counts here are stale.
            if current.isEmpty && !previous.isEmpty {
                Task { await presenter.refresh() }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ state: InventoryViewState) -> some ToolbarContent {
        if state.isHouseholdSwitcherVisible {
            ToolbarItem(placement: .topBarLeading) {
                householdMenu(state)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                path.append(.newBox)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New box")
            .disabled(state.activeHouseholdID == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Sign out", role: .destructive) {
                    Task { await presenter.signOutTapped() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    @ViewBuilder
    private func destination(_ route: Route, householdID: String?) -> some View {
        switch route {
        case .box(let box):
            BoxDetailView(
                boxID: box.id,
                title: box.name,
                householdID: householdID ?? "",
                userID: userID
            )
        case .newBox:
            BoxEditorView(householdID: householdID ?? "", userID: userID)
        }
    }

    @ViewBuilder
    private func content(_ state: InventoryViewState) -> some View {
        switch state.content {
        case .loading:
            centred { ProgressView() }
        case .empty(let message):
            centred {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.bfTextMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        case .failed(let message):
            centred {
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
            }
        case .sections(let sections):
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.boxes) { box in
                            NavigationLink(value: Route.box(box)) {
                                boxRow(box)
                            }
                            .listRowBackground(Color.bfSurface)
                        }
                    } header: {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.bfTextMuted)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bfBg)
        }
    }

    private func boxRow(_ box: InventoryViewState.BoxRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: box.symbol)
                .font(.title3)
                .foregroundStyle(Color.bfAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(box.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.bfText)

                HStack(spacing: 6) {
                    Text(box.itemCount)
                    if let location = box.location {
                        Text("·")
                        Text(location)
                    }
                    if let taken = box.takenNote {
                        Text("·")
                        Text(taken).foregroundStyle(Color.bfAccent)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.bfTextMuted)

                if let match = box.matchNote {
                    Text(match)
                        .font(.caption)
                        .foregroundStyle(Color.bfGreen)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func householdMenu(_ state: InventoryViewState) -> some View {
        Menu {
            ForEach(state.households) { household in
                Button {
                    Task { await presenter.householdSelected(household.id) }
                } label: {
                    if household.id == state.activeHouseholdID {
                        Label(household.name, systemImage: "checkmark")
                    } else {
                        Text(household.name)
                    }
                }
            }
        } label: {
            Image(systemName: "house")
        }
        .accessibilityLabel("Switch household")
    }

    private func centred<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.bfBg.ignoresSafeArea()
            content()
        }
    }
}
