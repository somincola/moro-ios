//
//  TimelinePager.swift
//  moro
//
//  Retained child-host container for the home timelines. Selection is controlled
//  exclusively by the header menu; there is intentionally no paging gesture.
//

import SwiftUI
import UIKit

#if os(iOS)
    struct TimelineObservedPage<Content: View>: View {
        @ObservedObject var viewModel: TimelineViewModel
        @ViewBuilder var content: () -> Content

        var body: some View {
            content()
        }
    }

    struct TimelinePagerPage: Equatable {
        let type: TimelineType
        let configurationID: String
        let view: AnyView

        init(type: TimelineType, configurationID: String = "", view: AnyView) {
            self.type = type
            self.configurationID = configurationID
            self.view = view
        }

        static func == (lhs: TimelinePagerPage, rhs: TimelinePagerPage) -> Bool {
            lhs.type == rhs.type && lhs.configurationID == rhs.configurationID
        }
    }

    final class TimelinePageHostingController: UIHostingController<AnyView> {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        let timelineType: TimelineType

        init(timelineType: TimelineType, rootView: AnyView) {
            self.timelineType = timelineType
            super.init(rootView: rootView)
            view.backgroundColor = .clear
        }

        @available(*, unavailable)
        required dynamic init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class TimelineSelectionViewController: UIViewController {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        private(set) var currentHost: TimelinePageHostingController?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        func display(_ host: TimelinePageHostingController) {
            guard currentHost !== host else { return }

            let previous = currentHost
            previous?.willMove(toParent: nil)

            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            previous?.view.removeFromSuperview()
            previous?.removeFromParent()
            host.didMove(toParent: self)
            currentHost = host
        }
    }

    struct TimelinePagerHost: UIViewControllerRepresentable {
        @Binding var selection: TimelineType
        let pages: [TimelinePagerPage]
        let onTransitionStarted: (TimelineType) -> Void
        let onPagePresented: (TimelineType) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(
                selection: $selection,
                pages: pages,
                onTransitionStarted: onTransitionStarted,
                onPagePresented: onPagePresented
            )
        }

        func makeUIViewController(context: Context) -> TimelineSelectionViewController {
            let controller = TimelineSelectionViewController()
            context.coordinator.attachInitialPage(to: controller)
            return controller
        }

        func updateUIViewController(
            _ uiViewController: TimelineSelectionViewController,
            context: Context
        ) {
            context.coordinator.onTransitionStarted = onTransitionStarted
            context.coordinator.onPagePresented = onPagePresented
            context.coordinator.updatePages(pages, in: uiViewController)
            context.coordinator.syncSelection(selection, in: uiViewController)
        }

        final class Coordinator: NSObject {
            // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
            nonisolated deinit {}

            private var selection: Binding<TimelineType>
            private var pages: [TimelinePagerPage]
            private var hosts: [TimelineType: TimelinePageHostingController] = [:]
            var onTransitionStarted: (TimelineType) -> Void
            var onPagePresented: (TimelineType) -> Void

            init(
                selection: Binding<TimelineType>,
                pages: [TimelinePagerPage],
                onTransitionStarted: @escaping (TimelineType) -> Void,
                onPagePresented: @escaping (TimelineType) -> Void
            ) {
                self.selection = selection
                self.pages = pages
                self.onTransitionStarted = onTransitionStarted
                self.onPagePresented = onPagePresented
                super.init()
                rebuildHosts()
            }

            func attachInitialPage(to controller: TimelineSelectionViewController) {
                guard let initial = hostingController(for: selection.wrappedValue)
                    ?? hostingController(for: pages.first?.type)
                else { return }
                controller.display(initial)
                onPagePresented(initial.timelineType)
            }

            func updatePages(
                _ newPages: [TimelinePagerPage],
                in controller: TimelineSelectionViewController
            ) {
                // The hosted pages observe their view models directly. Reassigning every
                // UIHostingController.rootView when only an ancestor updated invalidates all
                // timeline rows, which then schedules another representable update and forms a
                // self-sustaining layout/allocation loop behind pushed screens.
                guard pages != newPages else { return }

                pages = newPages
                rebuildHosts()

                guard let current = controller.currentHost,
                    hosts[current.timelineType] == nil
                else {
                    return
                }

                if let replacement = hostingController(for: selection.wrappedValue)
                    ?? hostingController(for: pages.first?.type)
                {
                    onTransitionStarted(current.timelineType)
                    controller.display(replacement)
                    onPagePresented(replacement.timelineType)
                }
            }

            func syncSelection(
                _ selection: TimelineType,
                in controller: TimelineSelectionViewController
            ) {
                guard let current = controller.currentHost else { return }
                guard current.timelineType != selection else { return }
                guard let target = hostingController(for: selection) else { return }

                onTransitionStarted(current.timelineType)
                controller.display(target)
                onPagePresented(target.timelineType)
            }

            private func rebuildHosts() {
                let existingTypes = Set(hosts.keys)
                let nextTypes = Set(pages.map(\.type))

                for removedType in existingTypes.subtracting(nextTypes) {
                    hosts.removeValue(forKey: removedType)
                }

                for page in pages {
                    if let existing = hosts[page.type] {
                        existing.rootView = page.view
                    } else {
                        hosts[page.type] = TimelinePageHostingController(
                            timelineType: page.type,
                            rootView: page.view
                        )
                    }
                }
            }

            private func hostingController(for type: TimelineType?) -> TimelinePageHostingController? {
                guard let type else { return nil }
                return hosts[type]
            }
        }
    }
#endif
