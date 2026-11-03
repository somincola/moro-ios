//
//  MoroBrand.swift
//  moro
//
//  Canonical product links and contact addresses for the Moro brand.
//

import Foundation

enum MoroBrand {
    static let websiteURL = URL(string: "https://getmoro.app/")!
    static let privacyPolicyURL = URL(string: "https://getmoro.app/privacy")!
    static let termsOfUseURL = URL(string: "https://getmoro.app/terms")!
    static let supportURL = URL(string: "https://getmoro.app/support")!

    /// The developer's Mastodon account, shown as "Follow the Developer" in About.
    static let authorAcct = "acacius@m.somincola.org"
    static let authorProfileURL = URL(string: "https://m.somincola.org/@acacius")!

    static let supportEmail = "support@somincola.com"
    static let privacyEmail = "privacy@somincola.com"
    static let legalEmail = "contract@somincola.com"
}
