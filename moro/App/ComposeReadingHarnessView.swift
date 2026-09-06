#if DEBUG
import SwiftUI

struct ComposeReadingHarnessView: View {
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client = SearchFixtureProtocol.makeClient()
    private let draft: ComposeDraft
    private let store = ComposeDraftStore(userDefaults: UserDefaults(suiteName: "ui-compose-reading")!)

    init() {
        let model = ComposeViewModel(context: .newPost, apiClient: SearchFixtureProtocol.makeClient(), currentUserID: "fixture-author")
        model.content = "长文编辑测试。\n\n保留链接 https://example.com/long/path?first=1&second=2\n显示 <code> 原始文字。😀\n\n最后一段。"
        model.contentWarning = "内容提示"
        model.isContentWarningActive = true
        model.mediaAttachments = (1...3).map { index in
            MediaAttachment(id: "reading-\(index)", url: URL(string: "temp://reading-\(index)")!,
                previewURL: nil, type: "image", description: "图片 \(index)", focus: nil,
                originalDescription: "图片 \(index)", uploadState: .uploaded)
        }
        draft = model.makeDraft(category: .manual)
    }

    var body: some View {
        ComposeView(context: .newPost, apiClient: client, currentUserID: "fixture-author", draftStore: store, initialDraft: draft)
            .environmentObject(appState)
            .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
    }
}
#endif
