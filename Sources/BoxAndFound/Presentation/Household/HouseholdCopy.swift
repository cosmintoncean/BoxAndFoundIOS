import Foundation

/// Where households and invites become words.
enum HouseholdCopy {

    static let owner = "Owner"
    static let member = "Member"
    static let noHouseholds = "You are not in a household yet. Create one, or join with a code."

    static func message(for failure: HouseholdFailure) -> String {
        switch failure {
        case .network:
            "No connection. Check your network and try again."
        case .unknownInviteCode:
            "That code does not match a household. Check it and try again."
        case .deleteFunctionMissing:
            // Names the migration on purpose: this one is the project's fault,
            // not the person's, and the person reading it is the developer.
            "This project is missing delete_household. Run MIGRATION_delete_household_fn.sql."
        case .unknown:
            "Something went wrong. Try again."
        }
    }

    static func inviteTitle(_ householdName: String?) -> String {
        guard let name = householdName?.trimmed, !name.isEmpty else { return "Join this household?" }
        return "Join \(name)?"
    }

    /// "3 members · invited by Cosmin", with either half left out when it is
    /// not known — an invite with neither still gets a card worth reading.
    static func inviteDetail(memberCount: Int, ownerName: String?) -> String {
        var parts: [String] = []
        parts.append(memberCount == 1 ? "1 member" : "\(memberCount) members")
        if let owner = ownerName?.trimmed, !owner.isEmpty {
            parts.append("invited by \(owner)")
        }
        return parts.joined(separator: " · ")
    }

    static func acceptTitle(isAlreadyMember: Bool) -> String {
        isAlreadyMember ? "You are already a member" : "Join household"
    }

    static func joined(_ householdName: String?) -> String {
        guard let name = householdName?.trimmed, !name.isEmpty else { return "Joined." }
        return "Joined \(name)."
    }

    static let left = "You have left that household."
    static let deleted = "Household deleted."
    static let codeRotated = "New code. Any link you shared before has stopped working."
}
