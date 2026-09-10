import Foundation
import Observation

/// Creates a box, or edits one. The same screen either way — the difference is
/// whether there is a row behind it.
@MainActor
@Observable
final class BoxEditorPresenter: Presenter {

    /// An item as this screen holds it. `serverID` is nil until the row
    /// exists; `id` is local and stable so SwiftUI can identify a row that
    /// has never been saved.
    private struct EditorItem: Identifiable {
        let id: String
        var serverID: String?
        var name: String
        var quantity: Int
        var isTaken: Bool
        var takenAt: String?
        var takenBy: String?
    }

    private let householdID: String
    private let boxID: String?
    private let userID: String
    private let reader: any InventoryReading
    private let writer: any InventoryWriting
    private let imageURLs: BoxImageURLs

    private var loadedBox: Box?
    private var rooms: [Room] = []
    private var isLoading: Bool
    private var isSaving = false
    private var notice: BoxEditorViewState.Notice?
    private var isFinished = false

    private var name = ""
    private var location = ""
    private var icon = BoxIcons.defaultKey
    private var roomID: String?
    private var items: [EditorItem] = []
    private var newItemName = ""

    /// The photo already on the box, once signed.
    private var existingPhotoURL: URL?
    /// Chosen in this session, not uploaded until save.
    private var pickedPhoto: (data: Data, fileExtension: String)?
    private var photoCleared = false

    init(
        householdID: String,
        boxID: String? = nil,
        userID: String,
        reader: any InventoryReading = InventoryRepository(),
        writer: any InventoryWriting = InventoryWriteRepository(),
        imageURLs: BoxImageURLs = BoxImageURLs()
    ) {
        self.householdID = householdID
        self.boxID = boxID
        self.userID = userID
        self.reader = reader
        self.writer = writer
        self.imageURLs = imageURLs
        // Creating a box has nothing to fetch but the room list, and an empty
        // form is more useful to look at than a spinner.
        self.isLoading = boxID != nil
    }

    // MARK: - What the view draws

    var viewState: BoxEditorViewState {
        BoxEditorViewState(
            title: boxID == nil ? "New box" : "Edit box",
            isLoading: isLoading,
            name: name,
            location: location,
            icons: BoxIcons.keys.map {
                .init(key: $0, symbol: BoxSymbols.symbol(forIconKey: $0), isSelected: $0 == icon)
            },
            rooms: roomOptions,
            items: items.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    quantity: $0.quantity,
                    quantityLabel: $0.quantity > 1 ? "×\($0.quantity)" : nil,
                    isTaken: $0.isTaken
                )
            },
            newItemName: newItemName,
            photo: photo,
            saveTitle: boxID == nil ? "Create box" : "Save changes",
            // A box with no name is unfindable in a list sorted by name.
            isSaveEnabled: !isSaving && !name.trimmed.isEmpty,
            isSaving: isSaving,
            isDeleteVisible: boxID != nil,
            notice: notice,
            isFinished: isFinished
        )
    }

    private var roomOptions: [BoxEditorViewState.RoomOption] {
        let none = BoxEditorViewState.RoomOption(
            id: "",
            name: InventoryCopy.unassignedRoom,
            isSelected: roomID == nil
        )
        return [none] + rooms.map {
            .init(
                id: $0.id,
                name: InventoryCopy.roomName($0.name),
                isSelected: $0.id == roomID
            )
        }
    }

    private var photo: BoxEditorViewState.Photo {
        if pickedPhoto != nil { return .picked }
        if photoCleared { return .none }
        guard loadedBox?.imageURL?.trimmed.nilIfEmpty != nil else { return .none }
        return .existing(existingPhotoURL)
    }

    // MARK: - Intents

    func appeared() async {
        guard rooms.isEmpty, loadedBox == nil else { return }
        await load()
    }

    func nameChanged(_ value: String) { name = value }
    func locationChanged(_ value: String) { location = value }
    func iconSelected(_ key: String) { icon = BoxIcons.normalise(key) }
    func roomSelected(_ id: String) { roomID = id.nilIfEmpty }
    func newItemNameChanged(_ value: String) { newItemName = value }

    func addItemTapped() {
        let trimmed = newItemName.trimmed
        guard !trimmed.isEmpty else { return }
        items.append(
            EditorItem(id: UUID().uuidString, serverID: nil, name: trimmed, quantity: 1, isTaken: false)
        )
        newItemName = ""
    }

    func itemNameChanged(_ id: String, to value: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = value
    }

    func itemQuantityChanged(_ id: String, by delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].quantity = max(1, items[index].quantity + delta)
    }

    func itemRemoved(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// Reordering is the reason positions are diffed rather than assumed: the
    /// new order is whatever this list ends up as.
    func itemsMoved(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func photoPicked(data: Data, fileExtension: String) {
        pickedPhoto = (data, fileExtension)
        photoCleared = false
    }

    func photoRemoved() {
        pickedPhoto = nil
        photoCleared = true
    }

    func saveTapped() async {
        guard !isSaving, !name.trimmed.isEmpty else { return }
        isSaving = true
        notice = nil
        defer { isSaving = false }

        do {
            let uploadedPath = try await uploadPhotoIfPicked()
            if let boxID {
                try await save(existing: boxID, uploadedPath: uploadedPath)
            } else {
                try await create(uploadedPath: uploadedPath)
            }
            isFinished = true
        } catch {
            notice = .init(kind: .error, text: InventoryCopy.message(for: InventoryFailure.from(error)))
        }
    }

    func deleteTapped() async {
        guard let boxID, !isSaving else { return }
        isSaving = true
        notice = nil
        defer { isSaving = false }

        do {
            try await writer.deleteBox(id: boxID)
            isFinished = true
        } catch {
            notice = .init(kind: .error, text: InventoryCopy.message(for: InventoryFailure.from(error)))
        }
    }

    // MARK: -

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let rooms = reader.rooms(householdID: householdID)
            self.rooms = try await rooms

            guard let boxID else { return }
            let box = try await reader.box(id: boxID)
            loadedBox = box
            name = box.name ?? ""
            location = box.location ?? ""
            icon = BoxIcons.normalise(box.icon)
            roomID = box.roomID
            items = box.items.map {
                EditorItem(
                    id: $0.id,
                    serverID: $0.id,
                    name: $0.name ?? "",
                    quantity: $0.quantity,
                    isTaken: $0.isTaken,
                    takenAt: $0.takenAt,
                    takenBy: $0.takenBy
                )
            }
            existingPhotoURL = await imageURLs.resolve(box.imageURL)
        } catch {
            notice = .init(kind: .error, text: InventoryCopy.message(for: InventoryFailure.from(error)))
        }
    }

    /// Nil when there is nothing new to upload. The distinction between "no
    /// change" and "cleared" is carried by `photoCleared`, not by this.
    private func uploadPhotoIfPicked() async throws -> String? {
        guard let picked = pickedPhoto else { return nil }
        return try await writer.uploadBoxPhoto(
            householdID: householdID,
            data: picked.data,
            fileExtension: picked.fileExtension
        )
    }

    private func create(uploadedPath: String?) async throws {
        let box = try await writer.createBox(
            householdID: householdID,
            name: name,
            icon: icon,
            location: location.trimmed.nilIfEmpty,
            roomID: roomID,
            imageURL: uploadedPath
        )
        let plan = ItemSync.plan(
            existing: [],
            desired: drafts,
            currentUserID: userID
        )
        try await writer.applyItemPlan(boxID: box.id, plan: plan)
    }

    private func save(existing boxID: String, uploadedPath: String?) async throws {
        var changes = BoxChanges()
        let box = loadedBox

        if name.trimmed != (box?.name ?? "") { changes.name = .set(name.trimmed) }
        if icon != BoxIcons.normalise(box?.icon) { changes.icon = .set(icon) }
        if location.trimmed.nilIfEmpty != box?.location?.trimmed.nilIfEmpty {
            changes.location = .set(location.trimmed.nilIfEmpty)
        }
        if roomID != box?.roomID { changes.roomID = .set(roomID) }
        if let uploadedPath {
            changes.imageURL = .set(uploadedPath)
        } else if photoCleared, box?.imageURL != nil {
            changes.imageURL = .set(nil)
        }

        try await writer.updateBox(id: boxID, changes: changes)

        let plan = ItemSync.plan(
            existing: box?.items ?? [],
            desired: drafts,
            currentUserID: userID
        )
        try await writer.applyItemPlan(boxID: boxID, plan: plan)
    }

    private var drafts: [DraftItem] {
        items.map {
            DraftItem(
                id: $0.serverID,
                name: $0.name,
                quantity: $0.quantity,
                isTaken: $0.isTaken,
                takenAt: $0.takenAt,
                takenBy: $0.takenBy
            )
        }
    }
}
