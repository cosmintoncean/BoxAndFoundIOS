import SwiftUI

/// One room's map, drawn from what the web or Android saved.
struct RoomMapView: View {
    @State private var presenter: RoomMapPresenter

    private let householdID: String
    private let userID: String

    init(roomID: String, roomName: String, householdID: String, userID: String) {
        self.householdID = householdID
        self.userID = userID
        _presenter = State(
            initialValue: RoomMapPresenter(
                roomID: roomID,
                roomName: roomName,
                householdID: householdID
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
        .task { await presenter.appeared() }
    }

    @ViewBuilder
    private func content(_ state: RoomMapViewState) -> some View {
        switch state.content {
        case .loading:
            ProgressView()
        case .empty(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.bfTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
        case .map(let drawing):
            map(drawing)
        }
    }

    private func map(_ drawing: RoomMapViewState.Drawing) -> some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                // Letterboxed to the map's own aspect ratio so nothing is
                // stretched: sizes were normalised against width alone, and
                // a non-uniform scale would make every token an oval.
                let rect = fitted(in: proxy.size, aspectRatio: drawing.aspectRatio)

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(drawing, in: rect, context: &context)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)

                    ForEach(drawing.boxes) { box in
                        tokenLabel(box, in: rect)
                    }
                }
            }
            .padding(16)

            Text(drawing.sizeNote)
                .font(.caption)
                .foregroundStyle(Color.bfTextMuted)
                .padding(.bottom, 12)
        }
    }

    /// The largest rectangle of the right shape that fits, centred.
    private func fitted(in size: CGSize, aspectRatio: Double) -> CGRect {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return .zero }
        var width = size.width
        var height = width / aspectRatio
        if height > size.height {
            height = size.height
            width = height * aspectRatio
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func place(_ point: RoomMapViewState.NormalPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func draw(
        _ drawing: RoomMapViewState.Drawing,
        in rect: CGRect,
        context: inout GraphicsContext
    ) {
        for floor in drawing.floors where floor.points.count > 2 {
            var path = Path()
            path.move(to: place(floor.points[0], in: rect))
            for point in floor.points.dropFirst() {
                path.addLine(to: place(point, in: rect))
            }
            path.closeSubpath()
            context.fill(path, with: .color(.bfSurface2))
        }

        for wall in drawing.walls {
            var path = Path()
            path.move(to: place(wall.from, in: rect))
            path.addLine(to: place(wall.to, in: rect))
            context.stroke(
                path,
                with: .color(.bfBorderStrong),
                style: StrokeStyle(lineWidth: max(1, wall.thickness * rect.width), lineCap: .round)
            )
        }

        for piece in drawing.furniture {
            let origin = place(piece.origin, in: rect)
            let box = CGRect(
                x: origin.x,
                y: origin.y,
                width: piece.width * rect.width,
                height: piece.height * rect.width
            )
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(.bfSurface3))
        }

        for door in drawing.doors {
            let centre = place(door.centre, in: rect)
            let length = max(2, door.width * rect.width)
            var path = Path()
            path.move(to: CGPoint(x: -length / 2, y: 0))
            path.addLine(to: CGPoint(x: length / 2, y: 0))
            let placed = path
                .applying(CGAffineTransform(rotationAngle: door.angle * .pi / 180))
                .applying(CGAffineTransform(translationX: centre.x, y: centre.y))
            context.stroke(
                placed,
                with: .color(.bfAccent),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
        }

        for box in drawing.boxes {
            let centre = place(box.centre, in: rect)
            let size = CGSize(width: box.width * rect.width, height: box.height * rect.width)
            let frame = CGRect(
                x: centre.x - size.width / 2,
                y: centre.y - size.height / 2,
                width: max(6, size.width),
                height: max(6, size.height)
            )
            context.fill(Path(roundedRect: frame, cornerRadius: 4), with: .color(.bfAccentSoft))
            context.stroke(
                Path(roundedRect: frame, cornerRadius: 4),
                with: .color(.bfAccent),
                lineWidth: 1.5
            )
        }
    }

    /// Labels sit outside the `Canvas` because text there cannot be tapped,
    /// and a token you cannot open is a picture of a box rather than a way to
    /// reach one.
    private func tokenLabel(_ box: RoomMapViewState.BoxMark, in rect: CGRect) -> some View {
        let centre = place(box.centre, in: rect)
        let width = max(44, box.width * rect.width)

        return NavigationLink {
            BoxDetailView(
                boxID: box.id,
                title: box.label,
                householdID: householdID,
                userID: userID
            )
        } label: {
            Text(box.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.bfText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .position(x: centre.x, y: centre.y)
    }
}
