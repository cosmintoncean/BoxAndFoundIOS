import SwiftUI

/// One box and what is in it. Read-only at M2 — taking and returning arrive
/// with the rest of the writes at M3.
struct BoxDetailView: View {
    @State private var presenter: BoxDetailPresenter

    init(boxID: String, title: String) {
        _presenter = State(initialValue: BoxDetailPresenter(boxID: boxID, title: title))
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
                }
            }
            .padding(20)
        }
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
        HStack(spacing: 10) {
            Image(systemName: item.isTaken ? "circle.dashed" : "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.isTaken ? Color.bfTextMuted : Color.bfGreen)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
