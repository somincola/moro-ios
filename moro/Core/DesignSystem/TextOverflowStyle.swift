//
//  TextOverflowStyle.swift
//  moro
//
//  Shared text overflow styles for identity and metadata labels.
//

import SwiftUI

extension Text {
    func moroIdentityPrimaryLine() -> some View {
        lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
    }

    func moroIdentityHandleLine() -> some View {
        lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.84)
            .allowsTightening(true)
    }
}
