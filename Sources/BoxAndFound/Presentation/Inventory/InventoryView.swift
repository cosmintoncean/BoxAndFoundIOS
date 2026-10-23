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
    private let pendingInviteCode: String?
    private let onInviteConsumed: @MainActor () -> Void

    private enum Route: Hashable {
        case box(InventoryViewState.BoxRow)
        case newBox
        /// Carries the invite code when the app was opened by a link, so the
        /// households screen can look it up without being asked twice.
        case households(inviteCode: String?)
        case notifications
        case map(roomID: String, roomName: String)
        /// One level of storage: a room’s own level, or the inside of a
        /// container.
        case storage(StorageTarget)
    }

    init(
        userID: String,
        pendingInviteCode: String? = nil,
        onInviteConsumed: @escaping @MainActor () -> Void = {},
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.userID = userID
        self.pendingInviteCode = pendingInviteCode
        self.onInviteConsumed = onInviteConsumed
        _presenter = State(initialValue: InventoryPresenter(userID: userID, signOut: signOut))
    }

    var body: some View {
        let state = presenter.viewState

        NavigationStack(path: $path) {
            // The bar sits outside the content rather than at the top of the
            // list, because a tag can filter every box out of view — on a
            // household whose only use of it is on something loose in a
            // container, say — and a bar that vanished with the list would
            // leave no way to clear the filter that emptied it.
            //
            // A safe-area inset rather than a VStack: in a VStack the bar laid
            // out at its full height and drew nothing at all, which the first
            // gallery caught as a band of empty space above the list. An inset
            // is what a navigation stack expects a bar over a scrolling list
            // to be, and it keeps the list's own insets honest underneath it.
            content(state)
                .safeAreaInset(edge: .top, spacing: 0) { tagBar(state) }
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
        .task {
            await presenter.appeared()
            // An invite is why the app was opened, so it goes in front of the
            // box list rather than waiting to be found.
            if let code = pendingInviteCode {
                onInviteConsumed()
                path.append(.households(inviteCode: code))
            }
        }
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
                Button("Notifications") {
                    path.append(.notifications)
                }
                Button("Households") {
                    path.append(.households(inviteCode: nil))
                }
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
        case .households(let inviteCode):
            HouseholdsView(userID: userID, pendingInviteCode: inviteCode)
        case .notifications:
            NotificationsView()
        case .storage(let target):
            StorageView(
                target: target,
                householdID: householdID ?? "",
                userID: userID
            )
        case .map(let roomID, let roomName):
            RoomMapView(
                roomID: roomID,
                roomName: roomName,
                householdID: householdID ?? "",
                userID: userID
            )
        }
    }

    /// Every tag in use, newest household first in the sense that there is
    /// usually nothing here at all: most households tag nothing for a while,
    /// and an empty bar should take up no room rather than a little.
    @ViewBuilder
    private func tagBar(_ state: InventoryViewState) -> some View {
        if !state.tags.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(state.tags) { tag in
                        Button {
                            presenter.tagTapped(tag.label)
                        } label: {
                            HStack(spacing: 4) {
                                if tag.isDerived {
                                    Image(systemName: "hand.raised")
                                        .font(.caption2)
                                }
                                Text(tag.label)
                                    .font(.caption.weight(.medium))
                                Text("\(tag.count)")
                                    .font(.caption2)
                                    .foregroundStyle(
                                        tag.isActive ? Color.bfBg : Color.bfTextMuted
                                    )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(tag.isActive ? Color.bfAccent : Color.bfSurface)
                            )
                            .foregroundStyle(tag.isActive ? Color.bfBg : Color.bfText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            tag.isActive ? "\(tag.label), filtering" : tag.label
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .background(Color.bfBg)
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
                        HStack {
                            Text(section.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.bfTextMuted)
                            Spacer(minLength: 0)
                            if let roomID = section.roomID {
                                Button {
                                    path.append(.storage(.room(id: roomID, name: section.title)))
                                } label: {
                                    Image(systemName: "square.stack.3d.up")
                                        .font(.footnote)
                                }
                                .accessibilityLabel("Storage in \(section.title)")

                                Button {
                                    path.append(.map(roomID: roomID, roomName: section.title))
                                } label: {
                                    Image(systemName: "map")
                                        .font(.footnote)
                                }
                                .accessibilityLabel("Map of \(section.title)")
                            }
                        }
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
