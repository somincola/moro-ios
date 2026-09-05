//
//  MastodonClient.swift
//  moro
//
//  URLSession-backed implementation of MastodonAPI.
//

import Foundation

struct MastodonClient: MastodonAPI {
    private struct DecodeTypeBox<T: Decodable>: @unchecked Sendable {
        let type: T.Type
    }

    private static let decodeQueue = DispatchQueue(
        label: "com.moro.network.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let heavyDecodePayloadThreshold = 64 * 1024  // 64 KB
    private static let apiDateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom {
        decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        if let date = DateFormatting.parseISO8601(dateString) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode ISO8601 date string: \(dateString)"
        )
    }

    private let session: URLSession
    private let builder: MastodonRequestBuilder
    private let authInterceptor: AuthInterceptor
    private let logger: NetworkLogger
    let instanceMetadataCacheKey: String?

    /// Shorter timeouts than `URLSession.shared`'s 60s default so the error UI
    /// surfaces quickly on flaky networks instead of leaving a long spinner.
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private struct StatusPayload: Encodable {
        let status: String
        let visibility: MastodonVisibility
        let mediaIDs: [String]?
        let inReplyToID: String?
        let spoilerText: String?
        let sensitive: Bool?
        let quoteID: String?
        let quoteApprovalPolicy: MastodonQuoteApprovalPolicy?
        let language: String?
        let scheduledAt: String?
        let poll: StatusPollPayload?

        enum CodingKeys: String, CodingKey {
            case status
            case visibility
            case mediaIDs = "media_ids"
            case inReplyToID = "in_reply_to_id"
            case spoilerText = "spoiler_text"
            case sensitive
            case quoteID = "quoted_status_id"
            case quoteApprovalPolicy = "quote_approval_policy"
            case language
            case scheduledAt = "scheduled_at"
            case poll
        }
    }

    /// Editing must not re-send creation-only fields or reset an existing quote.
    private struct StatusEditPayload: Encodable {
        let status: String
        let mediaIDs: [String]?
        let spoilerText: String?
        let sensitive: Bool?
        let language: String?
        let poll: StatusPollPayload?

        enum CodingKeys: String, CodingKey {
            case status, sensitive, language, poll
            case mediaIDs = "media_ids"
            case spoilerText = "spoiler_text"
        }
    }

    init(
        baseURL: URL = AppEnvironment.apiBaseURL,
        session: URLSession = MastodonClient.defaultSession,
        authInterceptor: AuthInterceptor,
        loggerConfig: NetworkLoggerConfiguration = .default
    ) {
        self.session = session
        self.builder = MastodonRequestBuilder(baseURL: baseURL)
        self.authInterceptor = authInterceptor
        self.logger = NetworkLogger(configuration: loggerConfig)
        self.instanceMetadataCacheKey = baseURL.absoluteString
    }

    // MARK: - OAuth & Instance

    func fetchInstance() async throws -> MastodonInstance {
        let endpoint = MastodonEndpoint.instance
        let request = try builder.makeRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchInstanceV2() async throws -> MastodonInstanceV2 {
        let endpoint = MastodonEndpoint.instanceV2
        let request = try builder.makeRequest(for: endpoint)
        return try await perform(request)
    }

    func createOAuthApp(clientName: String, redirectURIs: String, scopes: String, website: String?)
        async throws -> OAuthApp
    {
        let endpoint = MastodonEndpoint.createOAuthApp(
            clientName: clientName,
            redirectURIs: redirectURIs,
            scopes: scopes,
            website: website
        )
        let formData: [String: String] = [
            "client_name": clientName,
            "redirect_uris": redirectURIs,
            "scopes": scopes,
            "website": website ?? "",
        ].compactMapValues { $0.isEmpty ? nil : $0 }
        let request = try builder.makeRequest(for: endpoint, formData: formData)
        return try await perform(request)
    }

    func exchangeOAuthToken(
        code: String, clientID: String, clientSecret: String, redirectURI: String,
        codeVerifier: String?
    ) async throws -> OAuthTokenResponse {
        let endpoint = MastodonEndpoint.oauthToken(
            code: code,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )
        var formData: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
        ]
        if let codeVerifier {
            formData["code_verifier"] = codeVerifier
        }
        let request = try builder.makeRequest(for: endpoint, formData: formData)
        return try await perform(request)
    }

    func requestApplicationAccessToken(
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        scopes: String = "read write follow push"
    ) async throws -> OAuthTokenResponse {
        let endpoint = MastodonEndpoint.oauthTokenClientCredentials(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes
        )
        let formData: [String: String] = [
            "grant_type": "client_credentials",
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "scope": scopes,
        ]
        let request = try builder.makeRequest(for: endpoint, formData: formData)
        return try await perform(request)
    }

    func registerAccount(
        request payload: AccountRegistrationRequest,
        appAccessToken: String?
    ) async throws -> OAuthTokenResponse {
        let endpoint = MastodonEndpoint.registerAccount
        var formData: [String: String] = [
            "username": payload.username,
            "email": payload.email,
            "password": payload.password,
            "agreement": payload.agreement ? "true" : "false",
            "locale": payload.locale,
        ]

        if let reason = payload.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            !reason.isEmpty
        {
            formData["reason"] = reason
        }
        if let dateOfBirth = payload.dateOfBirth, !dateOfBirth.isEmpty {
            formData["date_of_birth"] = dateOfBirth
        }

        var request = try builder.makeRequest(for: endpoint, formData: formData)
        if let appAccessToken, !appAccessToken.isEmpty {
            request.setValue("Bearer \(appAccessToken)", forHTTPHeaderField: "Authorization")
        }
        return try await perform(request)
    }

    func verifyCredentials() async throws -> Account {
        let endpoint = MastodonEndpoint.verifyCredentials
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    // MARK: - Account

    func fetchAccount(id: String) async throws -> Account {
        let endpoint = MastodonEndpoint.account(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func lookupAccount(acct: String) async throws -> Account {
        let endpoint = MastodonEndpoint.accountLookup(acct: acct)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchAccountStatuses(
        id: String,
        maxID: String? = nil,
        sinceID: String? = nil,
        limit: Int = 40,
        excludeReplies: Bool = false,
        excludeReblogs: Bool = false,
        onlyMedia: Bool = false,
        pinned: Bool = false
    ) async throws -> [Status] {
        let endpoint = MastodonEndpoint.accountStatuses(
            id: id,
            maxID: maxID,
            sinceID: sinceID,
            limit: limit,
            excludeReplies: excludeReplies,
            excludeReblogs: excludeReblogs,
            onlyMedia: onlyMedia,
            pinned: pinned
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchAccountFollowers(
        id: String,
        maxID: String? = nil,
        limit: Int = 40
    ) async throws -> [Account] {
        let endpoint = MastodonEndpoint.accountFollowers(id: id, maxID: maxID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchAccountFollowing(
        id: String,
        maxID: String? = nil,
        limit: Int = 40
    ) async throws -> [Account] {
        let endpoint = MastodonEndpoint.accountFollowing(id: id, maxID: maxID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchRelationships(accountIDs: [String]) async throws -> [Relationship] {
        guard !accountIDs.isEmpty else { return [] }

        // Batch requests in chunks of 100 (API limit)
        let chunkSize = 100
        var allRelationships: [Relationship] = []

        for start in stride(from: 0, to: accountIDs.count, by: chunkSize) {
            let end = min(start + chunkSize, accountIDs.count)
            let chunk = Array(accountIDs[start..<end])

            let endpoint = MastodonEndpoint.relationships(accountIDs: chunk)
            let request = try authorizedRequest(for: endpoint)
            let relationships: [Relationship] = try await perform(request)
            allRelationships.append(contentsOf: relationships)
        }

        return allRelationships
    }

    func followAccount(id: String, reblogs: Bool?, notify: Bool?) async throws -> Relationship {
        let endpoint = MastodonEndpoint.followAccount(id: id)

        struct Payload: Encodable {
            let reblogs: Bool?
            let notify: Bool?

            enum CodingKeys: String, CodingKey {
                case reblogs
                case notify
            }
        }

        let payload = Payload(reblogs: reblogs, notify: notify)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func unfollowAccount(id: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.unfollowAccount(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func authorizeFollowRequest(accountID: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.authorizeFollowRequest(id: accountID)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func rejectFollowRequest(accountID: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.rejectFollowRequest(id: accountID)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func muteAccount(id: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.muteAccount(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func unmuteAccount(id: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.unmuteAccount(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func blockAccount(id: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.blockAccount(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func unblockAccount(id: String) async throws -> Relationship {
        let endpoint = MastodonEndpoint.unblockAccount(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func updateAccountCredentials(
        discoverable: Bool? = nil,
        locked: Bool? = nil,
        indexable: Bool? = nil,
        hideCollections: Bool? = nil,
        privacy: String? = nil
    ) async throws -> Account {
        var formData: [String: String] = [:]
        if let discoverable = discoverable {
            formData["discoverable"] = discoverable ? "true" : "false"
        }
        if let locked = locked {
            formData["locked"] = locked ? "true" : "false"
        }
        if let indexable = indexable {
            formData["indexable"] = indexable ? "true" : "false"
        }
        if let hideCollections = hideCollections {
            formData["hide_collections"] = hideCollections ? "true" : "false"
        }
        if let privacy = privacy {
            // Account-level default posting visibility (public/unlisted/private/direct).
            formData["source[privacy]"] = privacy
        }

        let endpoint = MastodonEndpoint.updateAccountCredentials
        let request = try authorizedRequest(
            for: endpoint, formData: formData.isEmpty ? nil : formData)
        return try await perform(request)
    }

    func updateAccountProfile(
        displayName: String? = nil,
        note: String? = nil,
        avatar: AccountProfileImageUpload? = nil,
        header: AccountProfileImageUpload? = nil,
        removeAvatar: Bool = false,
        removeHeader: Bool = false,
        fields: [AccountField]? = nil
    ) async throws -> Account {
        var multipartParts: [MultipartFormPart] = []

        if let displayName {
            multipartParts.append(MultipartFormPart(fieldName: "display_name", value: displayName))
        }
        if let note {
            multipartParts.append(MultipartFormPart(fieldName: "note", value: note))
        }
        if let avatar {
            multipartParts.append(
                MultipartFormPart(
                    fieldName: "avatar",
                    data: avatar.data,
                    fileName: avatar.fileName,
                    mimeType: avatar.mimeType
                )
            )
        }
        if let header {
            multipartParts.append(
                MultipartFormPart(
                    fieldName: "header",
                    data: header.data,
                    fileName: header.fileName,
                    mimeType: header.mimeType
                )
            )
        }
        if removeAvatar, avatar == nil {
            let removed = try await removeProfileImageIfSupported(endpoint: .deleteProfileAvatar)
            if !removed {
                // Fallback for older instances that do not support DELETE /api/v1/profile/avatar.
                multipartParts.append(MultipartFormPart(fieldName: "avatar", value: ""))
            }
        }
        if removeHeader, header == nil {
            let removed = try await removeProfileImageIfSupported(endpoint: .deleteProfileHeader)
            if !removed {
                // Fallback for older instances that do not support DELETE /api/v1/profile/header.
                multipartParts.append(MultipartFormPart(fieldName: "header", value: ""))
            }
        }

        if let fields {
            if fields.isEmpty {
                // Explicitly clear all existing profile metadata fields.
                multipartParts.append(MultipartFormPart(fieldName: "fields_attributes[]", value: ""))
            } else {
                for (index, field) in fields.enumerated() {
                    multipartParts.append(
                        MultipartFormPart(
                            fieldName: "fields_attributes[\(index)][name]",
                            value: field.name
                        )
                    )
                    multipartParts.append(
                        MultipartFormPart(
                            fieldName: "fields_attributes[\(index)][value]",
                            value: field.value
                        )
                    )
                }
            }
        }

        guard !multipartParts.isEmpty else { return try await verifyCredentials() }

        let endpoint = MastodonEndpoint.updateAccountCredentials
        let request = try authorizedRequest(
            for: endpoint,
            multipartParts: multipartParts
        )
        return try await perform(request)
    }

    private func removeProfileImageIfSupported(endpoint: MastodonEndpoint) async throws -> Bool {
        let request = try authorizedRequest(for: endpoint)
        do {
            try await performIgnoringResponse(request)
            return true
        } catch let error as APIError {
            // Mastodon <= 4.1 does not expose /api/v1/profile/avatar|header delete endpoints.
            if let status = error.httpStatusCode, [404, 405, 501].contains(status) {
                return false
            }
            throw error
        }
    }

    // MARK: - Timeline & Status

    func fetchHomeTimeline(maxID: String?, sinceID: String?, limit: Int = 40) async throws
        -> [Status]
    {
        let endpoint = MastodonEndpoint.homeTimeline(maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchPublicTimeline(
        local: Bool = true, maxID: String? = nil, sinceID: String? = nil, minID: String? = nil,
        limit: Int = 40
    ) async throws -> [Status] {
        let endpoint = MastodonEndpoint.publicTimeline(
            local: local, maxID: maxID, sinceID: sinceID, minID: minID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchHashtagTimeline(
        tag: String, maxID: String? = nil, sinceID: String? = nil, limit: Int = 40
    ) async throws -> [Status] {
        let endpoint = MastodonEndpoint.hashtagTimeline(
            tag: tag, maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func search(
        query: String,
        type: MastodonSearchType? = nil,
        resolve: Bool = true,
        limit: Int = 20,
        offset: Int? = nil
    ) async throws -> SearchResults {
        let endpoint = MastodonEndpoint.search(
            query: query,
            type: type?.rawValue,
            resolve: resolve,
            limit: limit,
            offset: offset
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchTag(name: String) async throws -> SearchTag {
        try await perform(authorizedRequest(for: .tag(name: name)))
    }

    func setTagFollowed(name: String, followed: Bool) async throws -> SearchTag {
        let endpoint: MastodonEndpoint = followed ? .followTag(name: name) : .unfollowTag(name: name)
        return try await perform(authorizedRequest(for: endpoint))
    }

    func fetchFollowedTags(maxID: String?, limit: Int = 100) async throws -> FollowedTagsPage {
        let request = try authorizedRequest(for: .followedTags(maxID: maxID, limit: limit))
        let (tags, response): ([SearchTag], HTTPURLResponse) = try await performWithResponse(request)
        return FollowedTagsPage(tags: tags, nextMaxID: FollowedTagPagination.nextMaxID(in: response))
    }

    func fetchTrendingTags(limit: Int? = 10) async throws -> [SearchTag] {
        let endpoint = MastodonEndpoint.trendsTags(limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchTrendingStatuses(limit: Int? = 10) async throws -> [Status] {
        let endpoint = MastodonEndpoint.trendsStatuses(limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchDirectoryAccounts(
        limit: Int? = 10,
        offset: Int? = nil,
        order: MastodonDirectoryOrder? = .active,
        local: Bool? = nil
    ) async throws -> [Account] {
        let endpoint = MastodonEndpoint.directory(
            limit: limit,
            offset: offset,
            order: order?.rawValue,
            local: local
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchAnnouncements() async throws -> [Announcement] {
        let endpoint = MastodonEndpoint.announcements
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func dismissAnnouncement(id: String) async throws {
        let endpoint = MastodonEndpoint.dismissAnnouncement(id: id)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func addAnnouncementReaction(id: String, name: String) async throws {
        let endpoint = MastodonEndpoint.addAnnouncementReaction(id: id, name: name)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func removeAnnouncementReaction(id: String, name: String) async throws {
        let endpoint = MastodonEndpoint.removeAnnouncementReaction(id: id, name: name)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func fetchStatusDetail(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.status(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchStatusContext(id: String) async throws -> StatusContext {
        let endpoint = MastodonEndpoint.statusContext(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchStatusHistory(id: String) async throws -> [StatusEditHistoryItem] {
        let endpoint = MastodonEndpoint.statusHistory(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchStatusSource(id: String) async throws -> StatusSource {
        let request = try authorizedRequest(for: .statusSource(id: id))
        return try await perform(request)
    }

    func translateStatus(id: String, targetLanguage: String?) async throws -> StatusTranslationPayload
    {
        let endpoint = MastodonEndpoint.statusTranslate(id: id, targetLanguage: targetLanguage)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchTranslationLanguages() async throws -> [String: [String]] {
        let endpoint = MastodonEndpoint.translationLanguages
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func postStatus(
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        language: String?,
        poll: StatusPollPayload?
    ) async throws -> Status {
        let result = try await publishStatus(
            text: text,
            visibility: visibility,
            mediaIDs: mediaIDs,
            inReplyToID: inReplyToID,
            spoilerText: spoilerText,
            sensitive: sensitive,
            quotingID: quotingID,
            language: language,
            scheduledAt: nil,
            poll: poll
        )

        switch result {
        case .posted(let status):
            return status
        case .scheduled:
            throw APIError.decoding(
                NSError(
                    domain: "MastodonClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Expected immediate status response"]
                )
            )
        }
    }

    func publishStatus(
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        quoteApprovalPolicy: MastodonQuoteApprovalPolicy? = nil,
        language: String?,
        scheduledAt: Date?,
        poll: StatusPollPayload?
    ) async throws -> StatusPublishResult {
        let payload = StatusPayload(
            status: text,
            visibility: visibility,
            mediaIDs: mediaIDs,
            inReplyToID: inReplyToID,
            spoilerText: spoilerText,
            sensitive: sensitive,
            quoteID: quotingID,
            quoteApprovalPolicy: quoteApprovalPolicy,
            language: language,
            scheduledAt: scheduledAt?.ISO8601Format(),
            poll: poll
        )
        let endpoint = MastodonEndpoint.postStatus
        let request = try authorizedRequest(for: endpoint, body: payload)
        if scheduledAt != nil {
            let scheduled: ScheduledStatus = try await perform(request)
            return .scheduled(scheduled)
        }
        let status: Status = try await perform(request)
        return .posted(status)
    }

    func editStatus(
        id: String,
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        language: String?,
        poll: StatusPollPayload?
    ) async throws -> Status {
        let payload = StatusEditPayload(
            status: text,
            mediaIDs: mediaIDs,
            spoilerText: spoilerText,
            sensitive: sensitive,
            language: language,
            poll: poll
        )
        let endpoint = MastodonEndpoint.editStatus(id: id)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func uploadMedia(data: Data, mimeType: String, description: String?) async throws
        -> Status.Attachment
    {
        let endpoint = MastodonEndpoint.uploadMedia
        let fileName = "media.\(mimeType.components(separatedBy: "/").last ?? "jpg")"
        var formData: [String: String]?
        if let description = description {
            formData = ["description": description]
        }
        let request = try authorizedRequest(
            for: endpoint,
            multipartData: (data: data, fieldName: "file", fileName: fileName, mimeType: mimeType),
            formData: formData)
        return try await perform(request)
    }

    func updateMedia(id: String, description: String?, focus: String?) async throws
        -> Status.Attachment
    {
        // Mastodon API requires form-data for PUT /api/v1/media/:id
        var formData: [String: String] = [:]
        if let description = description {
            formData["description"] = description
        }
        if let focus = focus {
            formData["focus"] = focus
        }

        let endpoint = MastodonEndpoint.updateMedia(id: id)
        let request = try authorizedRequest(
            for: endpoint, formData: formData.isEmpty ? nil : formData)
        return try await perform(request)
    }

    func fetchCustomEmojis() async throws -> [CustomEmoji] {
        let endpoint = MastodonEndpoint.customEmojis
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchNotifications(maxID: String? = nil, sinceID: String? = nil, limit: Int = 30)
        async throws -> [NotificationItem]
    {
        let endpoint = MastodonEndpoint.notifications(
            maxID: maxID,
            sinceID: sinceID,
            limit: limit,
            supportedTypes: NotificationKind.supportedRawValues
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        struct Response: Decodable {
            let count: Int
        }

        let endpoint = MastodonEndpoint.notificationUnreadCount
        let request = try authorizedRequest(for: endpoint)
        let response: Response = try await perform(request)
        return response.count
    }

    func fetchScheduledStatuses(maxID: String? = nil, sinceID: String? = nil, limit: Int = 20)
        async throws -> [ScheduledStatus]
    {
        let endpoint = MastodonEndpoint.scheduledStatuses(
            maxID: maxID,
            sinceID: sinceID,
            limit: limit
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func cancelScheduledStatus(id: String) async throws {
        let endpoint = MastodonEndpoint.cancelScheduledStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func fetchConversations(maxID: String? = nil, sinceID: String? = nil, limit: Int = 20)
        async throws -> [Conversation]
    {
        let endpoint = MastodonEndpoint.conversations(maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchBookmarkedStatuses(maxID: String? = nil, sinceID: String? = nil, limit: Int = 20)
        async throws -> [Status]
    {
        let endpoint = MastodonEndpoint.bookmarks(maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchFavouritedStatuses(maxID: String? = nil, sinceID: String? = nil, limit: Int = 20)
        async throws -> [Status]
    {
        let endpoint = MastodonEndpoint.favourites(maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchLists() async throws -> [MastodonList] {
        let endpoint = MastodonEndpoint.lists
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchAccountLists(accountID: String) async throws -> [MastodonList] {
        let endpoint = MastodonEndpoint.accountLists(id: accountID)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func createList(title: String, repliesPolicy: MastodonList.RepliesPolicy?) async throws
        -> MastodonList
    {
        struct Payload: Encodable {
            let title: String
            let repliesPolicy: String?

            enum CodingKeys: String, CodingKey {
                case title
                case repliesPolicy = "replies_policy"
            }
        }

        let payload = Payload(title: title, repliesPolicy: repliesPolicy?.rawValue)
        let endpoint = MastodonEndpoint.createList
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func updateList(id: String, title: String, repliesPolicy: MastodonList.RepliesPolicy?) async throws
        -> MastodonList
    {
        struct Payload: Encodable {
            let title: String
            let repliesPolicy: String?

            enum CodingKeys: String, CodingKey {
                case title
                case repliesPolicy = "replies_policy"
            }
        }

        let payload = Payload(title: title, repliesPolicy: repliesPolicy?.rawValue)
        let endpoint = MastodonEndpoint.updateList(id: id)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func deleteList(id: String) async throws {
        let endpoint = MastodonEndpoint.deleteList(id: id)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func fetchListAccounts(
        listID: String,
        maxID: String? = nil,
        sinceID: String? = nil,
        limit: Int = 40
    ) async throws -> [Account] {
        let endpoint = MastodonEndpoint.listAccounts(
            id: listID,
            maxID: maxID,
            sinceID: sinceID,
            limit: limit
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func addAccountsToList(listID: String, accountIDs: [String]) async throws {
        struct Payload: Encodable {
            let accountIDs: [String]

            enum CodingKeys: String, CodingKey {
                case accountIDs = "account_ids"
            }
        }

        let payload = Payload(accountIDs: accountIDs)
        let endpoint = MastodonEndpoint.addAccountsToList(id: listID)
        let request = try authorizedRequest(for: endpoint, body: payload)
        _ = try await performIgnoringResponse(request)
    }

    func removeAccountsFromList(listID: String, accountIDs: [String]) async throws {
        struct Payload: Encodable {
            let accountIDs: [String]

            enum CodingKeys: String, CodingKey {
                case accountIDs = "account_ids"
            }
        }

        let payload = Payload(accountIDs: accountIDs)
        let endpoint = MastodonEndpoint.removeAccountsFromList(id: listID)
        let request = try authorizedRequest(for: endpoint, body: payload)
        _ = try await performIgnoringResponse(request)
    }

    func fetchListTimeline(id: String, maxID: String? = nil, sinceID: String? = nil, limit: Int = 20)
        async throws -> [Status]
    {
        let endpoint = MastodonEndpoint.listTimeline(id: id, maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchPushSubscription() async throws -> PushSubscription {
        let endpoint = MastodonEndpoint.pushSubscription
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func createPushSubscription(
        endpoint: String, p256dh: String, auth: String,
        alerts: PushSubscription.Alerts, policy: String?
    ) async throws -> PushSubscription {
        struct SubscriptionKeys: Encodable {
            let p256dh: String
            let auth: String
        }
        struct Subscription: Encodable {
            let endpoint: String
            let keys: SubscriptionKeys
        }
        struct DataPayload: Encodable {
            let alerts: PushSubscription.Alerts
            let policy: String?
        }
        struct Payload: Encodable {
            let subscription: Subscription
            let data: DataPayload
        }

        let payload = Payload(
            subscription: Subscription(
                endpoint: endpoint,
                keys: SubscriptionKeys(p256dh: p256dh, auth: auth)
            ),
            data: DataPayload(alerts: alerts, policy: policy)
        )
        let request = try authorizedRequest(
            for: MastodonEndpoint.createPushSubscription, body: payload)
        return try await perform(request)
    }

    func updatePushSubscription(alerts: PushSubscription.Alerts, policy: String?) async throws
        -> PushSubscription
    {
        struct DataPayload: Encodable {
            let alerts: PushSubscription.Alerts
            let policy: String?
        }

        struct Payload: Encodable {
            let data: DataPayload
        }

        let payload = Payload(data: DataPayload(alerts: alerts, policy: policy))
        let endpoint = MastodonEndpoint.updatePushSubscription
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func deletePushSubscription() async throws {
        let endpoint = MastodonEndpoint.deletePushSubscription
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func fetchFilters() async throws -> [ServerFilter] {
        let endpoint = MastodonEndpoint.filters
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func createFilter(
        title: String,
        keyword: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async throws -> ServerFilter {
        struct CreatePayload: Encodable {
            struct KeywordAttribute: Encodable {
                let keyword: String
                let wholeWord: Bool

                enum CodingKeys: String, CodingKey {
                    case keyword
                    case wholeWord = "whole_word"
                }
            }

            let title: String
            let context: [String]
            let filterAction: String
            let keywordsAttributes: [KeywordAttribute]

            enum CodingKeys: String, CodingKey {
                case title
                case context
                case filterAction = "filter_action"
                case keywordsAttributes = "keywords_attributes"
            }
        }

        let payload = CreatePayload(
            title: title,
            context: contexts.map(\.rawValue),
            filterAction: action.rawValue,
            keywordsAttributes: [
                CreatePayload.KeywordAttribute(
                    keyword: keyword,
                    wholeWord: true
                )
            ]
        )
        let endpoint = MastodonEndpoint.createFilter
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func updateFilter(
        id: String,
        title: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async throws -> ServerFilter {
        struct UpdatePayload: Encodable {
            let title: String
            let context: [String]
            let filterAction: String

            enum CodingKeys: String, CodingKey {
                case title
                case context
                case filterAction = "filter_action"
            }
        }

        let payload = UpdatePayload(
            title: title,
            context: contexts.map(\.rawValue),
            filterAction: action.rawValue
        )
        let endpoint = MastodonEndpoint.updateFilter(id: id)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func deleteFilter(id: String) async throws {
        let endpoint = MastodonEndpoint.deleteFilter(id: id)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func addFilterKeyword(
        filterID: String,
        keyword: String,
        wholeWord: Bool
    ) async throws -> ServerFilter.Keyword {
        struct Payload: Encodable {
            let keyword: String
            let wholeWord: Bool

            enum CodingKeys: String, CodingKey {
                case keyword
                case wholeWord = "whole_word"
            }
        }

        let payload = Payload(keyword: keyword, wholeWord: wholeWord)
        let endpoint = MastodonEndpoint.createFilterKeyword(filterID: filterID)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func updateFilterKeyword(
        keywordID: String,
        keyword: String,
        wholeWord: Bool
    ) async throws -> ServerFilter.Keyword {
        struct Payload: Encodable {
            let keyword: String
            let wholeWord: Bool

            enum CodingKeys: String, CodingKey {
                case keyword
                case wholeWord = "whole_word"
            }
        }

        let payload = Payload(keyword: keyword, wholeWord: wholeWord)
        let endpoint = MastodonEndpoint.updateFilterKeyword(keywordID: keywordID)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    func deleteFilterKeyword(keywordID: String) async throws {
        let endpoint = MastodonEndpoint.deleteFilterKeyword(keywordID: keywordID)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func fetchMutedAccounts(maxID: String? = nil, sinceID: String? = nil, limit: Int? = 200)
        async throws -> [Account]
    {
        let endpoint = MastodonEndpoint.mutedAccounts(maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchBlockedAccounts(maxID: String? = nil, sinceID: String? = nil, limit: Int? = 200)
        async throws -> [Account]
    {
        let endpoint = MastodonEndpoint.blockedAccounts(
            maxID: maxID,
            sinceID: sinceID,
            limit: limit
        )
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func fetchDomainBlocks(maxID: String? = nil, sinceID: String? = nil, limit: Int? = 200)
        async throws -> [String]
    {
        let endpoint = MastodonEndpoint.domainBlocks(maxID: maxID, sinceID: sinceID, limit: limit)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func blockDomain(_ domain: String) async throws {
        let endpoint = MastodonEndpoint.blockDomain(domain: domain)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func unblockDomain(_ domain: String) async throws {
        let endpoint = MastodonEndpoint.unblockDomain(domain: domain)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func markConversationRead(id: String) async throws -> Conversation {
        let endpoint = MastodonEndpoint.readConversation(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func deleteConversation(id: String) async throws {
        let endpoint = MastodonEndpoint.deleteConversation(id: id)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    // MARK: - Interactions

    func favouriteStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.favouriteStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func unfavouriteStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.unfavouriteStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func reblogStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.reblogStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func unreblogStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.unreblogStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func bookmarkStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.bookmarkStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func unbookmarkStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.unbookmarkStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    // MARK: - Polls

    func votePoll(pollID: String, choices: [Int]) async throws -> Status.Poll {
        struct Payload: Encodable {
            let choices: [Int]
        }

        let payload = Payload(choices: choices)
        let endpoint = MastodonEndpoint.votePoll(pollID: pollID, choices: choices)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    // MARK: - Reports

    func report(accountID: String, statusIDs: [String], comment: String) async throws
        -> ReportResponse
    {
        struct Payload: Encodable {
            let accountID: String
            let statusIDs: [String]
            let comment: String

            enum CodingKeys: String, CodingKey {
                case accountID = "account_id"
                case statusIDs = "status_ids"
                case comment
            }
        }

        let payload = Payload(accountID: accountID, statusIDs: statusIDs, comment: comment)
        let endpoint = MastodonEndpoint.report(
            accountID: accountID, statusIDs: statusIDs, comment: comment)
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    // MARK: - Own Status Actions

    func deleteStatus(id: String) async throws {
        let endpoint = MastodonEndpoint.deleteStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        _ = try await performIgnoringResponse(request)
    }

    func pinStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.pinStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func unpinStatus(id: String) async throws -> Status {
        let endpoint = MastodonEndpoint.unpinStatus(id: id)
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    // MARK: - Markers (Reading Position)

    func fetchMarkers(timelines: [MarkerTimeline]) async throws -> Marker {
        let endpoint = MastodonEndpoint.markers(timelines: timelines.map { $0.queryValue })
        let request = try authorizedRequest(for: endpoint)
        return try await perform(request)
    }

    func saveMarker(home: String?, notifications: String?) async throws -> Marker {
        struct Payload: Encodable {
            struct MarkerUpdate: Encodable {
                let lastReadId: String

                enum CodingKeys: String, CodingKey {
                    case lastReadId = "last_read_id"
                }
            }

            let home: MarkerUpdate?
            let notifications: MarkerUpdate?
        }

        let payload = Payload(
            home: home.map { Payload.MarkerUpdate(lastReadId: $0) },
            notifications: notifications.map { Payload.MarkerUpdate(lastReadId: $0) }
        )
        let endpoint = MastodonEndpoint.saveMarker
        let request = try authorizedRequest(for: endpoint, body: payload)
        return try await perform(request)
    }

    // MARK: - Helpers

    private func authorizedRequest(
        for endpoint: MastodonEndpoint, body: Encodable? = nil,
        multipartData: (data: Data, fieldName: String, fileName: String, mimeType: String)? = nil,
        multipartParts: [MultipartFormPart]? = nil,
        formData: [String: String]? = nil
    ) throws -> URLRequest {
        var request = try builder.makeRequest(
            for: endpoint,
            body: body,
            formData: formData,
            multipartData: multipartData,
            multipartParts: multipartParts
        )
        if endpoint.requiresAuth {
            authInterceptor.apply(to: &request)
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (value, _): (T, HTTPURLResponse) = try await performWithResponse(request)
        return value
    }

    private func performWithResponse<T: Decodable>(_ request: URLRequest) async throws -> (T, HTTPURLResponse) {
        // Log the request
        logger.logRequest(request)
        let startTime = Date()

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidURL
            }

            // Log the response
            logger.logResponse(
                httpResponse, data: data, for: request,
                duration: Date().timeIntervalSince(startTime))

            guard 200..<300 ~= httpResponse.statusCode else {
                // Try to parse server error response
                if let serverError = try? parseServerError(
                    from: data, httpCode: httpResponse.statusCode)
                {
                    throw APIError.serverError(serverError)
                }

                // Check for specific HTTP status codes
                switch httpResponse.statusCode {
                case 401:
                    throw APIError.authenticationRequired
                case 429:
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap { TimeInterval($0) }
                    throw APIError.rateLimited(retryAfter: retryAfter)
                default:
                    #if DEBUG
                        if logger.configuration.logDiagnostics,
                            let responseString = String(data: data, encoding: .utf8)
                        {
                            AppLogger.debug(
                                "API Error Response (\(httpResponse.statusCode)): \(responseString)",
                                enabled: logger.configuration.logDiagnostics
                            )
                        }
                    #endif
                    throw APIError.http(statusCode: httpResponse.statusCode, data: data)
                }
            }

            do {
                let decodeStart = Date()
                let decoded: T
                if shouldDecodeOffMain(for: request, payloadSize: data.count) {
                    decoded = try await decodeOnBackgroundQueue(T.self, from: data)
                } else {
                    decoded = try decodeInline(T.self, from: data)
                }
                #if DEBUG
                    if logger.configuration.logDiagnostics {
                        let decodeElapsed = Date().timeIntervalSince(decodeStart) * 1000
                        if decodeElapsed > 250 {
                            AppLogger.performanceLog(
                                String(
                                    format: "⏱️ [NetworkDecode] %@ %@ decode=%.0fms",
                                    request.httpMethod ?? "GET",
                                    request.url?.absoluteString ?? "unknown",
                                    decodeElapsed
                                ),
                                enabled: logger.configuration.logDiagnostics
                            )
                        }
                    }
                #endif
                return (decoded, httpResponse)
            } catch let decodingError as DecodingError {
                // Log detailed decoding error
                #if DEBUG
                    if logger.configuration.logDiagnostics {
                        if let responseString = String(data: data, encoding: .utf8) {
                            AppLogger.debug(
                                "=== Decoding Error ===",
                                enabled: logger.configuration.logDiagnostics
                            )
                            AppLogger.debug(
                                "Response: \(responseString.prefix(500))",
                                enabled: logger.configuration.logDiagnostics
                            )  // First 500 chars
                        }
                        AppLogger.debug(
                            "Decoding Error Details: \(decodingError.detailedDescription)",
                            enabled: logger.configuration.logDiagnostics
                        )
                    }
                #endif
                throw APIError.decoding(decodingError)
            } catch let decodingError {
                #if DEBUG
                    if logger.configuration.logDiagnostics {
                        if let responseString = String(data: data, encoding: .utf8) {
                            AppLogger.debug(
                                "Decoding Error - Response: \(responseString.prefix(500))",
                                enabled: logger.configuration.logDiagnostics
                            )
                        }
                        AppLogger.debug(
                            "Decoding Error: \(decodingError)",
                            enabled: logger.configuration.logDiagnostics
                        )
                    }
                #endif
                throw APIError.decoding(decodingError)
            }
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            // Classify URLSession errors
            switch error.code {
            case .cancelled:
                throw APIError.cancelled
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.networkUnavailable
            case .timedOut:
                throw APIError.timeout
            default:
                throw APIError.underlying(error)
            }
        } catch {
            throw APIError.underlying(error)
        }
    }

    private func shouldDecodeOffMain(for request: URLRequest, payloadSize: Int) -> Bool {
        if payloadSize >= Self.heavyDecodePayloadThreshold {
            return true
        }
        guard let path = request.url?.path else { return false }
        return path.hasPrefix("/api/v1/timelines/home") || path.hasPrefix("/api/v2/search")
    }

    private func decodeInline<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.apiDateDecodingStrategy
        return try decoder.decode(type, from: data)
    }

    private func decodeOnBackgroundQueue<T: Decodable>(_ type: T.Type, from data: Data) async throws
        -> T
    {
        let decodeType = DecodeTypeBox(type: type)
        return try await withCheckedThrowingContinuation { continuation in
            Self.decodeQueue.async {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = Self.apiDateDecodingStrategy

                do {
                    continuation.resume(returning: try decoder.decode(decodeType.type, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Parse server error from response data
    private func parseServerError(from data: Data, httpCode: Int) throws -> MastodonServerError {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var serverError = try decoder.decode(MastodonServerError.self, from: data)
        serverError.httpCode = httpCode
        return serverError
    }

    /// Perform a request and ignore the response body (for delete operations)
    private func performIgnoringResponse(_ request: URLRequest) async throws {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.underlying(
                    NSError(
                        domain: "MastodonClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw APIError.http(statusCode: httpResponse.statusCode, data: data)
            }
            // Success - ignore response body
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.underlying(error)
        }
    }
}
