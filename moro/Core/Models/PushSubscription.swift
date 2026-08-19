//
//  PushSubscription.swift
//  moro
//
//  Server push subscription model.
//

import Foundation

struct PushSubscription: Codable {
    struct Alerts: Codable, Equatable {
        var mention: Bool
        var status: Bool
        var reblog: Bool
        var follow: Bool
        var followRequest: Bool
        var favourite: Bool
        var poll: Bool
        var update: Bool
        var adminSignUp: Bool
        var adminReport: Bool

        enum CodingKeys: String, CodingKey {
            case mention
            case status
            case reblog
            case follow
            case followRequest = "follow_request"
            case favourite
            case poll
            case update
            case adminSignUp = "admin.sign_up"
            case adminReport = "admin.report"
        }

        init(
            mention: Bool = false,
            status: Bool = false,
            reblog: Bool = false,
            follow: Bool = false,
            followRequest: Bool = false,
            favourite: Bool = false,
            poll: Bool = false,
            update: Bool = false,
            adminSignUp: Bool = false,
            adminReport: Bool = false
        ) {
            self.mention = mention
            self.status = status
            self.reblog = reblog
            self.follow = follow
            self.followRequest = followRequest
            self.favourite = favourite
            self.poll = poll
            self.update = update
            self.adminSignUp = adminSignUp
            self.adminReport = adminReport
        }
    }

    let id: Int?
    let endpoint: String?
    let serverKey: String?
    var alerts: Alerts
    var policy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case endpoint
        case serverKey = "server_key"
        case alerts
        case policy
    }
}
