import SwiftUI

/// The notification feed.
struct NotificationsView: View {
    @State private var presenter = NotificationsPresenter()
    @State private var isShowingSettings = false

    var body: some View {
        let state = presenter.viewState

        ZStack {
            Color.bfBg.ignoresSafeArea()
            content(state)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Notification settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") {
                    Task { await presenter.markAllReadTapped() }
                }
                .font(.subheadline)
                .disabled(!state.isMarkAllEnabled)
            }
        }
        .navigationDestination(isPresented: $isShowingSettings) {
            NotificationSettingsView()
        }
        .task { await presenter.appeared() }
        .onDisappear { presenter.disappeared() }
    }

    @ViewBuilder
    private func content(_ state: NotificationsViewState) -> some View {
        switch state.content {
        case .loading:
            ProgressView()
        case .empty(let message), .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.bfTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        case .rows(let rows):
            List {
                ForEach(rows) { row in
                    Button {
                        Task { await presenter.rowTapped(row.id) }
                    } label: {
                        notificationRow(row)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bfSurface)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await presenter.deleteTapped(row.id) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bfBg)
            .refreshable { await presenter.refreshed() }
        }
    }

    private func notificationRow(_ row: NotificationsViewState.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbol)
                .font(.body)
                .foregroundStyle(row.isUnread ? Color.bfAccent : Color.bfTextMuted)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body.weight(row.isUnread ? .semibold : .regular))
                    .foregroundStyle(Color.bfText)
                if let body = row.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Color.bfTextMuted)
                }
                Text(row.timeAgo)
                    .font(.caption)
                    .foregroundStyle(Color.bfTextMuted)
            }

            Spacer(minLength: 0)

            if row.isUnread {
                Circle()
                    .fill(Color.bfAccent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityLabel("Unread")
            }
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
    }
}

/// Per-type preferences.
struct NotificationSettingsView: View {
    @State private var presenter = NotificationSettingsPresenter()

    var body: some View {
        let state = presenter.viewState

        Form {
            if let notice = state.notice {
                Section {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(Color.bfDanger)
                }
            }

            Section {
                ForEach(state.toggles) { item in
                    Toggle(isOn: Binding(
                        get: { item.isOn },
                        set: { on in Task { await presenter.toggled(item.id, to: on) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).foregroundStyle(Color.bfText)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(Color.bfTextMuted)
                        }
                    }
                    .tint(.bfAccent)
                }
            } footer: {
                Text("These apply everywhere you are signed in — the web app and Android too.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bfBg)
        .navigationTitle("Notification settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await presenter.appeared() }
    }
}
