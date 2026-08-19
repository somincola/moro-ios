//
//  MoroWidgetIntents.swift
//  moro
//
//  Interactive widget actions shared by the app and WidgetKit extension.
//

import AppIntents

nonisolated extension MoroWidgetDestination: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Moro Destination")
    static let caseDisplayRepresentations: [MoroWidgetDestination: DisplayRepresentation] = [
        .home: "Home",
        .compose: "Post",
        .search: "Search",
        .inbox: "Inbox",
        .profile: "Profile",
    ]
}

struct OpenMoroDestinationIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Moro"
    static let description = IntentDescription("Open Moro at the selected destination.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: MoroWidgetDestination

    init() {
        destination = .home
    }

    init(destination: MoroWidgetDestination) {
        self.destination = destination
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        MoroWidgetHandoffStore.write(destination: destination)
        return .result()
    }
}
