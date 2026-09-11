import Foundation
import Observation

/// Drives one box: what is in it, what is out, taking or returning it, and
/// asking someone else for it back.
@MainActor
@Observable
final class BoxDetailPresenter: Presenter {

    private let boxID: String
    private let householdID: String
    private let userID: String
    private let reader: any InventoryReading
    private let writer: any InventoryWriting
    private let nudges: any NudgeManaging
    private let imageURLs: BoxImageURLs

    /// The row the list already had, so the screen can open with a title
    /// instead of a spinner and a blank bar.
    private let placeholderTitle: String

    private var box: Box?
    private var photoURL: URL?
    private var failure: InventoryFailure?
    /// Items with a write in flight, so a second tap cannot race the first.
    private var busyItemIDs: Set<String> = []

    private var pending: [Nudge] = []
    private var nudgeItemID: String?
    private var nudgeAvailability: NudgeAvailability = .available
    private var nudgeMessage = ""
    private var isSendingNudge = false
    private var notice: String?

    init(
        boxID: String,
        title: String,
        householdID: String,
        userID: String,
        reader: any InventoryReading = Dependencies.inventoryReading,
        writer: any InventoryWriting = Dependencies.inventoryWriting,
        nudges: any NudgeManaging = Dependencies.nudges,
        imageURLs: BoxImageURLs = BoxImageURLs()
    ) {
        self.boxID = boxID
        self.placeholderTitle = title
        self.householdID = householdID
        self.userID = userID
        self.reader = reader
        self.writer = writer
        self.nudges = nudges
        self.imageURLs = imageURLs
    }

    var viewState: BoxDetailViewState {
        BoxDetailViewState(
            title: box.map { InventoryCopy.boxName($0.name) } ?? placeholderTitle,
            isEditVisible: box != nil,
            content: content,
            nudgeSheet: nudgeSheet,
            notice: notice
        )
    }

    private var content: BoxDetailViewState.Content {
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }
        guard let box else { return .loading }

        return .loaded(
            BoxDetailViewState.Loaded(
                symbol: BoxSymbols.symbol(forIconKey: box.icon),
                location: box.location?.trimmed.nilIfEmpty,
                imageURL: photoURL,
                itemCount: InventoryCopy.itemCount(box.items.count),
                takenNote: InventoryCopy.takenNote(box.items.filter(\.isTaken).count),
                items: box.items.map { item in
                    BoxDetailViewState.ItemRow(
                        id: item.id,
                        name: InventoryCopy.itemName(item.name),
                        quantity: item.quantity > 1 ? "×\(item.quantity)" : nil,
                        isTaken: item.isTaken,
                        isBusy: busyItemIDs.contains(item.id),
                        // Asking yourself for something back is not a feature,
                        // and an item nobody has taken is already here.
                        canAskBack: item.isTaken
                            && item.takenBy != nil
                            && item.takenBy != userID
                    )
                },
                emptyMessage: box.items.isEmpty ? InventoryCopy.emptyBox : nil,
                pendingNotes: pending.map {
                    NudgeCopy.pendingNote(itemName: $0.itemName, message: $0.message)
                }
            )
        )
    }

    private var nudgeSheet: BoxDetailViewState.NudgeSheet? {
        guard
            let nudgeItemID,
            let item = box?.items.first(where: { $0.id == nudgeItemID })
        else { return nil }

        return BoxDetailViewState.NudgeSheet(
            itemID: nudgeItemID,
            title: NudgeCopy.sheetTitle(InventoryCopy.itemName(item.name)),
            message: nudgeMessage,
            cooldownNote: NudgeCopy.cooldownNote(nudgeAvailability),
            canSend: nudgeAvailability == .available && !isSendingNudge,
            isSending: isSendingNudge
        )
    }

    // MARK: - Intents

    func appeared() async {
        guard box == nil else { return }
        await load()
    }

    /// Reloads after the editor has been and gone.
    func returnedToScreen() async {
        await load()
    }

    func retryTapped() async {
        await load()
    }

    /// Taking or returning one item. Written straight through rather than
    /// batched into a save: this is a one-tap action on a screen with no save
    /// button, and the row it touches is the row being looked at.
    func itemTapped(_ itemID: String) async {
        guard let box, let item = box.items.first(where: { $0.id == itemID }) else { return }
        guard !busyItemIDs.contains(itemID) else { return }

        busyItemIDs.insert(itemID)
        defer { busyItemIDs.remove(itemID) }

        do {
            try await writer.setItemTaken(itemID: itemID, isTaken: !item.isTaken, userID: userID)
            await load()
        } catch {
            failure = InventoryFailure.from(error)
        }
    }

    /// Opens the sheet, and asks the server whether the window is clear before
    /// offering a button that would fail.
    func askBackTapped(_ itemID: String) async {
        nudgeItemID = itemID
        nudgeMessage = ""
        notice = nil
        nudgeAvailability = .available
        do {
            nudgeAvailability = try await nudges.availability(itemID: itemID, now: Date())
        } catch {
            // A cooldown that cannot be read should not block the ask: the
            // server enforces the window anyway, and refusing on a failed
            // lookup would be stricter than the rule.
            nudgeAvailability = .available
        }
    }

    func nudgeMessageChanged(_ value: String) { nudgeMessage = value }

    func dismissNudgeTapped() {
        nudgeItemID = nil
        nudgeMessage = ""
    }

    func sendNudgeTapped() async {
        guard
            let nudgeItemID,
            let box,
            let item = box.items.first(where: { $0.id == nudgeItemID }),
            let recipient = item.takenBy,
            nudgeAvailability == .available,
            !isSendingNudge
        else { return }

        isSendingNudge = true
        defer { isSendingNudge = false }

        do {
            try await nudges.send(
                itemID: item.id,
                boxID: box.id,
                householdID: householdID,
                senderID: userID,
                recipientID: recipient,
                // Snapshotted here as well as server-side, so the message
                // still reads correctly after a rename.
                itemName: InventoryCopy.itemName(item.name),
                boxName: box.name,
                message: nudgeMessage
            )
            self.nudgeItemID = nil
            nudgeMessage = ""
            notice = NotificationCopy.nudgeSent
        } catch {
            notice = NotificationCopy.message(for: NotificationFailure.from(error))
        }
    }

    func noticeDismissed() { notice = nil }

    private func load() async {
        failure = nil
        do {
            let box = try await reader.box(id: boxID)
            self.box = box
            photoURL = await imageURLs.resolve(box.imageURL)
        } catch {
            failure = InventoryFailure.from(error)
        }

        // Requests pointed at this person, narrowed to this box. A failure
        // here is not worth a message: the box itself loaded, and an absent
        // banner is a smaller loss than an error over a screen that works.
        let mine = try? await nudges.pending(recipientID: userID, householdID: householdID)
        pending = (mine ?? []).filter { $0.boxID == boxID }
    }
}
