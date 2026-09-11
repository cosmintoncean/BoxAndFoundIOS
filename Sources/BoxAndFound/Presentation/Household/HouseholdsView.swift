import SwiftUI

/// Households: what you are in, what you can join, what you can hand on.
struct HouseholdsView: View {
    @State private var presenter: HouseholdsPresenter
    @State private var confirming: Confirmation?

    /// Leaving and deleting are both one-way, so both ask first.
    private struct Confirmation: Identifiable {
        enum Kind { case leave, delete }
        let kind: Kind
        let householdID: String
        let name: String
        var id: String { "\(householdID)-\(kind)" }
    }

    /// An invite that arrived as a link, handed in from the root.
    private let pendingInviteCode: String?

    init(userID: String, pendingInviteCode: String? = nil) {
        self.pendingInviteCode = pendingInviteCode
        _presenter = State(initialValue: HouseholdsPresenter(userID: userID))
    }

    var body: some View {
        let state = presenter.viewState

        Form {
            if let notice = state.notice {
                Section {
                    Text(notice.text)
                        .font(.subheadline)
                        .foregroundStyle(notice.kind == .error ? Color.bfDanger : Color.bfGreen)
                }
            }

            if let card = state.invite {
                inviteSection(card)
            }

            householdsSection(state)
            joinSection(state)
            createSection(state)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bfBg)
        .navigationTitle("Households")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await presenter.appeared()
            if let code = pendingInviteCode {
                await presenter.inviteArrived(code: code)
            }
        }
        .confirmationDialog(
            confirming.map(title) ?? "",
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirming
        ) { item in
            Button(item.kind == .delete ? "Delete household" : "Leave", role: .destructive) {
                Task {
                    switch item.kind {
                    case .delete: await presenter.deleteTapped(item.householdID)
                    case .leave: await presenter.leaveTapped(item.householdID)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(
                item.kind == .delete
                    ? "Every room, box and item in it goes too. This cannot be undone."
                    : "You will lose access to everything in it."
            )
        }
    }

    private func title(_ item: Confirmation) -> String {
        item.kind == .delete ? "Delete \(item.name)?" : "Leave \(item.name)?"
    }

    // MARK: - Sections

    @ViewBuilder
    private func householdsSection(_ state: HouseholdsViewState) -> some View {
        Section("Your households") {
            if state.isLoading && state.rows.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let message = state.emptyMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.bfTextMuted)
            } else {
                ForEach(state.rows) { row in
                    householdRow(row, isBusy: state.isBusy)
                }
            }
        }
    }

    private func householdRow(_ row: HouseholdsViewState.Row, isBusy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.bfText)
                    Text(row.roleNote)
                        .font(.caption)
                        .foregroundStyle(Color.bfTextMuted)
                }
                Spacer(minLength: 0)
                if row.isActive {
                    Text("Open")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.bfAccent)
                }
            }

            if let code = row.inviteCode {
                HStack(spacing: 10) {
                    Text(code)
                        .font(.footnote.monospaced().weight(.semibold))
                        .foregroundStyle(Color.bfText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.bfAccentSoft, in: .rect(cornerRadius: 6))

                    if let share = row.shareURL, let url = URL(string: share) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                    }

                    Button("New code") {
                        Task { await presenter.rotateCodeTapped(row.id) }
                    }
                    .font(.caption)
                    .disabled(isBusy)
                }
            }

            HStack(spacing: 16) {
                if row.canLeave {
                    Button("Leave", role: .destructive) {
                        confirming = .init(kind: .leave, householdID: row.id, name: row.name)
                    }
                    .font(.caption)
                    .disabled(isBusy)
                }
                if row.canDelete {
                    Button("Delete", role: .destructive) {
                        confirming = .init(kind: .delete, householdID: row.id, name: row.name)
                    }
                    .font(.caption)
                    .disabled(isBusy)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func inviteSection(_ card: HouseholdsViewState.InviteCard) -> some View {
        Section("Invitation") {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.bfText)
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(Color.bfTextMuted)
            }
            Button(card.acceptTitle) {
                Task { await presenter.acceptTapped() }
            }
            .disabled(!card.canAccept)
            Button("Not now", role: .cancel) {
                presenter.dismissInviteTapped()
            }
        }
    }

    private func joinSection(_ state: HouseholdsViewState) -> some View {
        Section("Join with a code") {
            TextField("ABC123", text: Binding(
                get: { state.joinCode },
                set: { presenter.joinCodeChanged($0) }
            ))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.body.monospaced())

            Button("Look up code") {
                Task { await presenter.previewTapped() }
            }
            .disabled(!state.isJoinEnabled)
        }
    }

    private func createSection(_ state: HouseholdsViewState) -> some View {
        Section("Create a household") {
            TextField("Name", text: Binding(
                get: { state.newHouseholdName },
                set: { presenter.newHouseholdNameChanged($0) }
            ))
            Button("Create household") {
                Task { await presenter.createTapped() }
            }
            .disabled(!state.isCreateEnabled)
        }
    }
}
