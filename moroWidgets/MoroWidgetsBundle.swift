//
//  MoroWidgetsBundle.swift
//  moroWidgets
//


import SwiftUI
import WidgetKit

@main
struct MoroWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MoroOverviewWidget()
        MoroQuickActionsWidget()
        MoroProfileCardWidget()
        MoroComfortWidget()
    }
}
