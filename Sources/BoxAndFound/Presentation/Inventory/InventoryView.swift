import SwiftUI

/// The box list: a household switcher, a search field, and boxes grouped by
/// room. Passive, like every view here — see `Presenter`.
struct InventoryView: View {
    @State private var presenter: InventoryPresenter

    init(userID: String, signOut: @escaping @MainActor () async -> Void) {
        _presenter = State(initialValue: InventoryPresenter(userID: userID, signOut: signOut))
    }

    var body: some View {
        let state = presenter.viewState

        NavigationStack {
            content(state)
                .navigationTitle(state.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if state.isHouseholdSwitcherVisible {
                        ToolbarItem(placement: .topBarLeading) {
                            householdMenu(state)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign out") {
                            Task { await presenter.signOutTapped() }
                        }
                        .font(.subheadline)
                    }
                }
                .navigationDestination(for: InventoryViewState.BoxRow.self) { row in
                    BoxDetailView(boxID: row.id, title: row.name)
                }
                .searchableWhen(
                    state.isSearchVisible,
                    text: Binding(
                        get: { state.searchTerm },
                        set: { presenter.searchChanged($0) }
                    ),
                    prompt: "Search boxes and items"
                )
        }
        .tint(.bfAccent)
        .task { await presenter.appeared() }
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
                            NavigationLink(value: box) {
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
    }

    private func centred<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.bfBg.ignoresSafeArea()
            content()
        }
    }
}
