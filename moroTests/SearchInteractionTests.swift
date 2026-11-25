import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import moro

@MainActor
struct SearchInteractionTests {
    @Test func clearingThenCancellingAlwaysReturnsToDiscovery() {
        var state = SearchInteractionState()
        state.submit("原查询", scope: .statuses)
        state.beginEntry()
        state.draftQuery = "新查询"
        #expect(state.page == .entry)
        #expect(state.submittedQuery == "原查询")
        state.draftQuery = ""
        #expect(state.page == .entry)
        state.cancelEntry()
        #expect(state.page == .discovery)
        #expect(state.draftQuery.isEmpty)
        #expect(state.submittedQuery.isEmpty)
        #expect(state.submittedScope == .accounts)
    }

    @Test func emptySubmissionAndRepeatedFocusRemainEntryUntilCancelled() {
        var state = SearchInteractionState()
        state.beginEntry()
        state.draftQuery = "  "
        state.beginEntry()
        let submitted = state.submit(state.draftQuery, scope: .all)
        #expect(!submitted)
        #expect(state.page == .entry)
        state.cancelEntry()
        #expect(state.page == .discovery)
        #expect(state.draftQuery.isEmpty)
    }

    @Test func explicitSubmissionTrimsInputAndCanReturnToDiscovery() {
        var state = SearchInteractionState()
        state.beginEntry()
        let submitted = state.submit("  中 \n", scope: .accounts)
        #expect(submitted)
        #expect(state.submittedQuery == "中")
        #expect(state.page == .results)
        state.showDiscovery()
        #expect(state.page == .discovery)
        #expect(state.submittedQuery.isEmpty)
    }

    @Test func recentSearchesAreBoundedDeduplicatedAndRestoredPerAccount() throws {
        let suite = "search-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = SearchLibraryStore(accountKey: "instance-a/user-1", defaults: defaults)
        for index in 0..<25 { a.record(query: "query-\(index)", scope: .all) }
        a.record(query: "  QUERY-15  ", scope: .statuses)
        a.record(query: " \n", scope: .all)
        #expect(a.recent.count == 20)
        #expect(a.recent.first?.query == "QUERY-15")
        #expect(a.recent.first?.scope == .statuses)
        let restored = SearchLibraryStore(accountKey: "instance-a/user-1", defaults: defaults)
        let b = SearchLibraryStore(accountKey: "instance-b/user-1", defaults: defaults)
        #expect(restored.recent == a.recent)
        #expect(b.recent.isEmpty)
        restored.clearRecent()
        a.reload()
        #expect(a.recent.isEmpty)
    }

    @Test func savedSearchesKeepQueryScopeAndNamesIndependentOfHistory() throws {
        let suite = "search-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = SearchLibraryStore(accountKey: "a", defaults: defaults)
        library.save(query: "Swift", scope: .statuses)
        library.save(query: "Swift", scope: .statuses)
        library.save(query: "Swift", scope: .accounts)
        let item = try #require(library.saved.first)
        library.rename(id: item.id, name: " 开发资料 ")
        library.record(query: "Swift", scope: .all)
        library.removeRecent(id: try #require(library.recent.first?.id))
        library.reload()
        #expect(library.saved.count == 2)
        #expect(library.saved.first?.title == "开发资料")
        #expect(library.saved.first?.query == "Swift")
        #expect(library.saved.first?.scope == .statuses)
        #expect(library.recent.isEmpty)
        library.removeSaved(id: item.id)
        #expect(!library.isSaved(query: "Swift", scope: .statuses))
        #expect(library.isSaved(query: "Swift", scope: .accounts))
    }

    @Test func corruptLocalDataDoesNotPreventSearching() throws {
        let suite = "search-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid-json".utf8), forKey: "search_library_v1.a")
        let library = SearchLibraryStore(accountKey: "a", defaults: defaults)
        #expect(library.recent.isEmpty)
        #expect(library.saved.isEmpty)
        library.record(query: "recovered", scope: .all)
        library.reload()
        #expect(library.recent.first?.query == "recovered")
    }

    #if os(iOS)
    @Test func searchLoadingStateExpandsTitleBeyondMascotWidthAfterZeroFrameLayout() throws {
        let stateView = SearchCenterStateView(
            mascotExpression: .thinking,
            imageSize: CGSize(width: 48, height: 48),
            title: "正在搜索…"
        )

        // Reproduce UITableView.backgroundView initial assignment before tableView has bounds.
        stateView.frame = .zero
        stateView.setNeedsLayout()
        stateView.layoutIfNeeded()

        stateView.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        stateView.setNeedsLayout()
        stateView.layoutIfNeeded()

        let labels = collectLabels(in: stateView)
        let titleLabel = try #require(labels.first { $0.text == "正在搜索…" })
        let singleLineSize = titleLabel.sizeThatFits(CGSize(width: 337, height: CGFloat.greatestFiniteMagnitude))

        #expect(titleLabel.bounds.width >= 300)
        #expect(titleLabel.bounds.height <= singleLineSize.height + 2)

        // Also verify empty/error state with subtitle stays wide and centered without collapsing.
        let emptyView = SearchCenterStateView(
            mascotExpression: .curious,
            imageSize: CGSize(width: 58, height: 58),
            title: "没有找到相关内容",
            subtitle: "试试更换关键词，或切换上方分类继续探索"
        )
        emptyView.frame = .zero
        emptyView.layoutIfNeeded()
        emptyView.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        emptyView.setNeedsLayout()
        emptyView.layoutIfNeeded()

        let emptyLabels = collectLabels(in: emptyView)
        let emptyTitle = try #require(emptyLabels.first { $0.text == "没有找到相关内容" })
        let emptySubtitle = try #require(emptyLabels.first { $0.text == "试试更换关键词，或切换上方分类继续探索" })
        #expect(emptyTitle.bounds.width >= 300)
        #expect(emptySubtitle.bounds.width >= 260 && emptySubtitle.bounds.width <= 281)
    }

    private func collectLabels(in view: UIView) -> [UILabel] {
        var result: [UILabel] = []
        if let label = view as? UILabel {
            result.append(label)
        }
        for subview in view.subviews {
            result.append(contentsOf: collectLabels(in: subview))
        }
        return result
    }
    #endif
}
