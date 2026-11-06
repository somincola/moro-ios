import Foundation

/// Authoring data, deliberately separate from Account's rendered HTML.
nonisolated struct EditableProfile: Decodable {
    let id: String
    let displayName: String
    let note: String
    let fields: [AccountField]
    var showMedia: Bool?
    var showMediaReplies: Bool?
    var showFeatured: Bool?
    var hideCollections: Bool?

    nonisolated enum CodingKeys: String, CodingKey {
        case id, note, fields
        case displayName = "display_name"
        case showMedia = "show_media"
        case showMediaReplies = "show_media_replies"
        case showFeatured = "show_featured"
        case hideCollections = "hide_collections"
    }

    static func credentials(_ account: Account) throws -> Self {
        guard let source = account.source, let note = source.note, let fields = source.fields else {
            throw ProfileEditingError.sourceUnavailable
        }
        return Self(id: account.id, displayName: account.displayName, note: note, fields: fields,
                    hideCollections: account.credentialHideCollections)
    }
}

nonisolated struct ProfileDisplayUpdate: Encodable {
    var showMedia: Bool?
    var showMediaReplies: Bool?
    var showFeatured: Bool?
    var hideCollections: Bool?

    nonisolated enum CodingKeys: String, CodingKey {
        case showMedia = "show_media"
        case showMediaReplies = "show_media_replies"
        case showFeatured = "show_featured"
        case hideCollections = "hide_collections"
    }
}

nonisolated struct ProfileLimits: Codable {
    var maxProfileFields: Int? = nil
    var profileFieldNameLimit: Int? = nil
    var profileFieldValueLimit: Int? = nil
    var maxNoteLength: Int? = nil
    var maxDisplayNameLength: Int? = nil
    var maxFeaturedTags: Int? = nil

    var fieldCount: Int { max(0, maxProfileFields ?? 4) }
    var fieldNameLength: Int { max(1, profileFieldNameLimit ?? 255) }
    var fieldValueLength: Int { max(1, profileFieldValueLimit ?? 255) }
    var noteLength: Int { max(1, maxNoteLength ?? 500) }
    var displayNameLength: Int { max(1, maxDisplayNameLength ?? 30) }
    var featuredTagCount: Int { max(0, maxFeaturedTags ?? 10) }

    nonisolated enum CodingKeys: String, CodingKey {
        case maxProfileFields = "max_profile_fields"
        case profileFieldNameLimit = "profile_field_name_limit"
        case profileFieldValueLimit = "profile_field_value_limit"
        case maxNoteLength = "max_note_length"
        case maxDisplayNameLength = "max_display_name_length"
        case maxFeaturedTags = "max_featured_tags"
    }
}

nonisolated struct FeaturedTag: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let statusesCount: Int

    nonisolated enum CodingKeys: String, CodingKey {
        case id, name
        case statusesCount = "statuses_count"
    }

    init(id: String, name: String, statusesCount: Int = 0) {
        self.id = id
        self.name = name
        self.statusesCount = statusesCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        if let count = try? values.decode(Int.self, forKey: .statusesCount) {
            statusesCount = count
        } else {
            statusesCount = Int(try values.decodeIfPresent(String.self, forKey: .statusesCount) ?? "0") ?? 0
        }
    }
}

nonisolated enum ProfileEditingError: LocalizedError {
    case sourceUnavailable
    case fieldsChangedElsewhere
    case unsupported

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: MoroL10n.ProfileEditing.sourceUnavailable
        case .fieldsChangedElsewhere: MoroL10n.ProfileEditing.fieldsChangedElsewhere
        case .unsupported: MoroL10n.ProfileEditing.unsupported
        }
    }
}
