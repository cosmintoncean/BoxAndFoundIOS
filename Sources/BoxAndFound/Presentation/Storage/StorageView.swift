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
        .task { await presenter.appeared() }
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
