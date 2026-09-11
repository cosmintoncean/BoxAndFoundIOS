import SwiftUI

/// One box and what is in it. Tapping an item takes it or puts it back.
struct BoxDetailView: View {
    @State private var presenter: BoxDetailPresenter
    @State private var isEditing = false

    private let boxID: String
    private let householdID: String
    private let userID: String

    init(boxID: String, title: String, householdID: String, userID: String) {
        self.boxID = boxID
        self.householdID = householdID
        self.userID = userID
        _presenter = State(
            initialValue: BoxDetailPresenter(
                boxID: boxID,
                title: title,
                householdID: householdID,
                userID: userID
            )
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
        .toolbar {
            if state.isEditVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .navigationDestination(isPresented: $isEditing) {
            BoxEditorView(householdID: householdID, boxID: boxID, userID: userID)
        }
        .sheet(isPresented: Binding(
            get: { presenter.viewState.nudgeSheet != nil },
            set: { if !$0 { presenter.dismissNudgeTapped() } }
        )) {
            if let sheet = presenter.viewState.nudgeSheet {
                nudgeSheet(sheet)
            }
        }
        .onChange(of: isEditing) { _, editing in
            // Coming back from the editor: the box may have been renamed, had
            // items added, or been deleted outright.
            if !editing { Task { await presenter.returnedToScreen() } }
        }
        .task { await presenter.appeared() }
    }

    @ViewBuilder
    private func content(_ state: BoxDetailViewState) -> some View {
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
        case .loaded(let box):
            loaded(box)
        }
    }

    private func loaded(_ box: BoxDetailViewState.Loaded) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(box.pendingNotes.enumerated()), id: \.offset) { _, note in
                    Label(note, systemImage: "hand.wave")
                        .font(.subheadline)
                        .foregroundStyle(Color.bfAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.bfAccentSoft, in: .rect(cornerRadius: 10))
                }

                if let notice = presenter.viewState.notice {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(Color.bfGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.bfGreenSoft, in: .rect(cornerRadius: 10))
                }

                if let url = box.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 12))
                }

                summary(box)

                if let message = box.emptyMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.bfTextMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(box.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider().background(Color.bfBorder)
                            }
                            itemRow(item)
                        }
                    }
                    .background(Color.bfSurface, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12).stroke(Color.bfBorder, lineWidth: 1)
                    }

                    Text("Tap an item to take it or put it back.")
                        .font(.caption)
                        .foregroundStyle(Color.bfTextMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
    }

    private func nudgeSheet(_ sheet: BoxDetailViewState.NudgeSheet) -> some View {
        NavigationStack {
            Form {
                if let cooldown = sheet.cooldownNote {
                    Section {
                        Text(cooldown)
                            .font(.subheadline)
                            .foregroundStyle(Color.bfTextMuted)
                    }
                }
                Section("Add a note") {
                    TextField("Optional", text: Binding(
                        get: { sheet.message },
                        set: { presenter.nudgeMessageChanged($0) }
                    ), axis: .vertical)
                    .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bfBg)
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presenter.dismissNudgeTapped() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ask") {
                        Task { await presenter.sendNudgeTapped() }
                    }
                    .disabled(!sheet.canSend)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func summary(_ box: BoxDetailViewState.Loaded) -> some View {
        HStack(spacing: 14) {
            Image(systemName: box.symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.bfAccent)
                .frame(width: 56, height: 56)
                .background(Color.bfAccentSoft, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(box.itemCount)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.bfText)
                if let location = box.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(Color.bfTextMuted)
                }
                if let taken = box.takenNote {
                    Text(taken)
                        .font(.caption)
                        .foregroundStyle(Color.bfAccent)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func itemRow(_ item: BoxDetailViewState.ItemRow) -> some View {
        Button {
            Task { await presenter.itemTapped(item.id) }
        } label: {
            HStack(spacing: 10) {
                if item.isBusy {
                    ProgressView().controlSize(.mini).frame(width: 14)
                } else {
                    Image(systemName: item.isTaken ? "circle.dashed" : "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(item.isTaken ? Color.bfTextMuted : Color.bfGreen)
                        .frame(width: 14)
                }

                Text(item.name)
                    .foregroundStyle(item.isTaken ? Color.bfTextMuted : Color.bfText)
                    .strikethrough(item.isTaken, color: .bfTextMuted)

                Spacer(minLength: 0)

                if let quantity = item.quantity {
                    Text(quantity)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.bfTextMuted)
                }
            }
            .contentShape(.rect)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(item.isBusy)
        .accessibilityLabel(item.isTaken ? "\(item.name), taken" : item.name)
        .accessibilityHint(item.isTaken ? "Put it back" : "Take it")
        .contextMenu {
            if item.canAskBack {
                Button {
                    Task { await presenter.askBackTapped(item.id) }
                } label: {
                    Label("Ask for it back", systemImage: "hand.wave")
                }
            }
        }
    }
}
