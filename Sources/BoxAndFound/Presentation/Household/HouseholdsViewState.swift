import Foundation

/// Everything the households screen draws.
struct HouseholdsViewState: Equatable {

    struct Row: Equatable, Identifiable {
        let id: String
        let name: String
        /// "Owner" or "Member" — decided here so no view compares ids.
        let roleNote: String
        let isActive: Bool
        /// Owners only: members cannot see a code they cannot rotate.
        let inviteCode: String?
        /// The link to hand someone, already built.
        let shareURL: String?
        /// An owner deletes; a member leaves. Never both.
        let canDelete: Bool
        let canLeave: Bool
    }

    /// An invite waiting to be accepted, whether it arrived by link or by
    /// someone typing the code.
    struct InviteCard: Equatable {
        let title: String
        let detail: String
        let acceptTitle: String
        let canAccept: Bool
    }

    struct Notice: Equatable {
        enum Kind: Equatable { case error, success }
        let kind: Kind
        let text: String
    }

    var isLoading: Bool
    var rows: [Row]
    var emptyMessage: String?

    var newHouseholdName: String
    var isCreateEnabled: Bool

    var joinCode: String
    var isJoinEnabled: Bool
    var invite: InviteCard?

    /// A write is in flight; every button that starts one is shut.
    var isBusy: Bool
    var notice: Notice?
}
