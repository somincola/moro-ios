//
//  MediaAttachmentView.swift
//  moro
//
//  Media attachment view with alt text editing support.
//

import SwiftUI

struct MediaAttachmentView: View {
    let attachment: MediaAttachment
    let onRemove: () -> Void
    let onEditAlt: () -> Void
    
    @Environment(\.moroTheme) private var theme
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(url: attachment.previewURL ?? attachment.url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(theme.colors.surfaceSubtle)
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .padding(4)
            
            // Edit/Alt button overlay
            VStack {
                Spacer()
                HStack {
                    Button(action: onEditAlt) {
                        HStack(spacing: 4) {
                            Image(systemName: attachment.description?.isEmpty == false ? "text.bubble.fill" : "text.bubble")
                            Text(attachment.description?.isEmpty == false ? MoroL10n.ImagePreview.altBadge : MoroL10n.Media.addAlt)
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.6))
                        )
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
    }
}

// MARK: - Alt Text Editor View

struct AltTextEditorView: View {
    @Binding var altText: String
    let imageURL: URL?
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.moroTheme) private var theme
    @FocusState private var isFocused: Bool
    
    private let maxLength = 1400
    
    var body: some View {
        NavigationStack {
            VStack(spacing: theme.spacing.l) {
                // Image preview
                if let imageURL = imageURL {
                    CachedAsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } placeholder: {
                        Rectangle()
                            .fill(theme.colors.surfaceSubtle)
                            .frame(height: 200)
                    }
                    .padding(.horizontal, theme.spacing.m)
                }
                
                // Text input
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    Text(MoroL10n.Media.altLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    
                    TextEditor(text: $altText)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .background(theme.colors.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .focused($isFocused)
                        .onAppear {
                            isFocused = true
                        }
                    
                    HStack {
                        Spacer()
                        Text("\(altText.count)/\(maxLength)")
                            .font(theme.typography.caption)
                            .foregroundStyle(
                                altText.count > maxLength
                                    ? theme.colors.error
                                    : theme.colors.textSecondary
                            )
                    }
                }
                .padding(.horizontal, theme.spacing.m)
                
                Spacer()
            }
            .background(theme.colors.background)
            .navigationTitle(MoroL10n.Media.editDescNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(MoroL10n.Media.cancel) {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(MoroL10n.Media.save) {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(altText.count > maxLength)
                }
            }
        }
    }
}

