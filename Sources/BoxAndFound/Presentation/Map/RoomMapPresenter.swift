import Foundation
import Observation

/// Drives one room's map.
///
/// Read-only. Maps are drawn on the web and on Android; this shows what they
/// drew, and says so rather than offering a canvas that cannot be edited.
@MainActor
@Observable
final class RoomMapPresenter: Presenter {

    private let roomID: String
    private let roomName: String
    private let householdID: String
    private let layouts: any RoomLayoutReading
    private let inventory: any InventoryReading
    private let unit: MeasurementUnit

    private var layout: RoomLayout?
    private var boxNames: [String: String] = [:]
    private var isLoading = true
    private var failure: InventoryFailure?

    init(
        roomID: String,
        roomName: String,
        householdID: String,
        layouts: any RoomLayoutReading = Dependencies.roomLayouts,
        inventory: any InventoryReading = Dependencies.inventoryReading,
        unit: MeasurementUnit = .metric
    ) {
        self.roomID = roomID
        self.roomName = roomName
        self.householdID = householdID
        self.layouts = layouts
        self.inventory = inventory
        self.unit = unit
    }

    var viewState: RoomMapViewState {
        RoomMapViewState(title: roomName, content: content)
    }

    private var content: RoomMapViewState.Content {
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }
        if isLoading { return .loading }
        guard
            let layout,
            let drawing = MapProjection.drawing(from: layout, boxNames: boxNames, unit: unit)
        else {
            return .empty(message: MapCopy.notMapped)
        }
        return .map(drawing)
    }

    func appeared() async {
        guard layout == nil else { return }
        await load()
    }

    func retryTapped() async {
        await load()
    }

    private func load() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            layout = try await layouts.layout(roomID: roomID)
            // Tokens carry a box id and nothing else, so the names come from
            // the inventory. A box moved to another room keeps its token until
            // someone redraws the map, which is why these are matched by id
            // rather than filtered by room.
            let boxes = try await inventory.boxes(householdID: householdID)
            boxNames = Dictionary(
                boxes.map { ($0.id, InventoryCopy.boxName($0.name)) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            failure = InventoryFailure.from(error)
        }
    }
}

enum MapCopy {
    static let notMapped = """
        This room has not been mapped yet. Maps are drawn in the web app or on \
        Android, and show up here.
        """
}
