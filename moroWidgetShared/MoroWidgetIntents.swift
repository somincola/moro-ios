//
//  MoroWidgetIntents.swift
//  moro
//
//  Interactive widget actions shared by the app and WidgetKit extension.
//

import AppIntents

nonisolated extension MoroWidgetDestination: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Moro Destination", table: "AppIntents"))
    static let caseDisplayRepresentations: [MoroWidgetDestination: DisplayRepresentation] = [
        .home: DisplayRepresentation(title: LocalizedStringResource("Home", table: "AppIntents")),
        .compose: DisplayRepresentation(title: LocalizedStringResource("Post", table: "AppIntents")),
        .search: DisplayRepresentation(title: LocalizedStringResource("Search", table: "AppIntents")),
        .inbox: DisplayRepresentation(title: LocalizedStringResource("Inbox", table: "AppIntents")),
        .profile: DisplayRepresentation(title: LocalizedStringResource("Profile", table: "AppIntents")),
    ]
}

struct OpenMoroDestinationIntent: AppIntent {
    static let title = LocalizedStringResource("Open Moro", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("Open Moro at the selected destination.", table: "AppIntents"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Destination", table: "AppIntents"))
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
