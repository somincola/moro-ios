//
//  ComposeDestination.swift
//  moro
//
//  Mutually exclusive presentation state for the composer.
//

import Foundation

enum ComposeDestination: Equatable, Identifiable {
    enum Presentation: Equatable {
        case sheet
        case photosPicker
        case fileImporter
        case alert
    }

    case drafts
    case photoLibrary
    case camera
    case fileImporter
    case altText(attachmentID: String)
    case language
    case schedule
    case missingAltTextConfirmation
    case discardConfirmation

    var id: String {
        switch self {
        case .drafts: return "drafts"
        case .photoLibrary: return "photoLibrary"
        case .camera: return "camera"
        case .fileImporter: return "fileImporter"
        case .altText(let attachmentID): return "altText-\(attachmentID)"
        case .language: return "language"
        case .schedule: return "schedule"
        case .missingAltTextConfirmation: return "missingAltTextConfirmation"
        case .discardConfirmation: return "discardConfirmation"
        }
    }

    var presentation: Presentation {
        switch self {
        case .drafts, .camera, .altText, .language, .schedule:
            return .sheet
        case .photoLibrary:
            return .photosPicker
        case .fileImporter:
            return .fileImporter
        case .missingAltTextConfirmation, .discardConfirmation:
            return .alert
        }
    }
}
