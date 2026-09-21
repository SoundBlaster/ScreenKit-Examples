import Patchwork
import SwiftUI
import UIKit
import XCTest
@testable import ScreenKit

@MainActor
final class ScreenKitLabTests: XCTestCase {
    private enum Family {
        case legacy
        case configuration
        case swiftUI
    }

    private enum TestSectionID: String, Hashable, Sendable {
        case first
        case second
        case third
    }

    private final class SectionHeader: UICollectionReusableView {
        let label = UILabel()
        var representedSection: TestSectionID?

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Use init(frame:)")
        }
    }

    private struct Row: Identifiable {
        let id: Int
        var title: String
        var family: Family = .legacy
    }

    private final class TitleModel {
        var title = "Before refresh"
    }

    private final class LayoutModel {
        var columns = 1
    }

    private final class SupplementaryModel {
        var revision = 0
        var dequeueCounts: [String: Int] = [:]
        var updatedSections: [TestSectionID] = []
    }

    private final class WeakReference<Value: AnyObject> {
        weak var value: Value?

        init(_ value: Value?) {
            self.value = value
        }
    }

    private final class LifecycleHost: UIViewController {
        let appeared = XCTestExpectation(description: "Test host completed viewDidAppear")
        let disappeared = XCTestExpectation(description: "Test host completed viewDidDisappear")
        private let content: UIViewController
        private var didAppear = false
        private var didDisappear = false

        init(content: UIViewController) {
            self.content = content
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Use init(content:)")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(content)
            content.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(content.view)
            NSLayoutConstraint.activate([
                content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                content.view.topAnchor.constraint(equalTo: view.topAnchor),
                content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            content.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if !didAppear {
                didAppear = true
                appeared.fulfill()
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if !didDisappear {
                didDisappear = true
                disappeared.fulfill()
            }
        }
    }

    private final class LegacyCell: UICollectionViewCell {
        let label = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Use init(frame:)")
        }
    }

    private final class StatefulLegacyCell: UICollectionViewCell {
        var renderedTitle = ""
        var originalHandlerCalls = 0
        var lastSelection = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            configurationUpdateHandler = { cell, state in
                guard let cell = cell as? StatefulLegacyCell else { return }
                cell.originalHandlerCalls += 1
                cell.lastSelection = state.isSelected
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Use init(frame:)")
        }
    }

    func testThreeCellFamiliesRenderTogetherInOneCollection() async throws {
        let renderers = makeRenderers()
        let rows = [
            Row(id: 1, title: "Legacy row", family: .legacy),
            Row(id: 2, title: "Configured row", family: .configuration),
            Row(id: 3, title: "SwiftUI row", family: .swiftUI),
        ]
        let controller = Screen(rows, renderer: renderers).makeViewController()

        try await withWindow(controller) {
            XCTAssertEqual(controller.itemIDs, [1, 2, 3])
            XCTAssertEqual(controller.collectionView.visibleCells.count, 3)

            let legacy = try XCTUnwrap(cell(at: 0, in: controller) as? LegacyCell)
            XCTAssertEqual(legacy.label.text, "Legacy row")

            let configured = try XCTUnwrap(cell(at: 1, in: controller) as? UICollectionViewListCell)
            let configuration = try XCTUnwrap(configured.contentConfiguration as? UIListContentConfiguration)
            XCTAssertEqual(configuration.text, "Configured row")

            let hosted = try XCTUnwrap(cell(at: 2, in: controller) as? UICollectionViewListCell)
            let hostingConfiguration = try XCTUnwrap(hosted.contentConfiguration)
            XCTAssertTrue(
                String(reflecting: type(of: hostingConfiguration)).contains("UIHostingConfiguration"),
                "The SwiftUI family must install an actual UIHostingConfiguration."
            )
            await assertEventually("SwiftUI content is attached and laid out") {
                hosted.contentView.window != nil
                    && hosted.contentView.bounds.width > 0
                    && hosted.contentView.bounds.height > 0
            }
        }
    }

    func testChangingRendererFamilyUnderSameIDReplacesLegacyCell() async throws {
        let controller = Screen(
            [Row(id: 1, title: "Legacy", family: .legacy)],
            renderer: makeRenderers()
        ).makeViewController()

        try await withWindow(controller) {
            let original = try XCTUnwrap(cell(at: 0, in: controller) as? LegacyCell)

            await performUpdate { done in
                controller.setItems([Row(id: 1, title: "Configured", family: .configuration)], animated: false, completion: done)
            }
            layout(controller)

            let replacement = try XCTUnwrap(cell(at: 0, in: controller) as? UICollectionViewListCell)
            XCTAssertFalse(replacement === original)
            XCTAssertEqual(controller.itemIDs, [1])
            XCTAssertEqual((replacement.contentConfiguration as? UIListContentConfiguration)?.text, "Configured")
            XCTAssertFalse(replacement.contentView.subviews.contains { $0 === original.label })

            await performUpdate { done in
                controller.setItems([Row(id: 1, title: "Legacy again", family: .legacy)], animated: false, completion: done)
            }
            layout(controller)
            XCTAssertEqual((cell(at: 0, in: controller) as? LegacyCell)?.label.text, "Legacy again")
        }
    }

    func testStableIDsSurviveReorderPayloadUpdateRemovalAndInsertion() async {
        let controller = Screen(
            [Row(id: 1, title: "First"), Row(id: 2, title: "Second")],
            renderer: makeRenderers()
        ).makeViewController()

        await withWindow(controller) {
            await performUpdate { done in
                controller.setItems(
                    [Row(id: 2, title: "Second updated"), Row(id: 1, title: "First updated")],
                    animated: false,
                    completion: done
                )
            }
            layout(controller)

            XCTAssertEqual(controller.itemIDs, [2, 1])
            XCTAssertEqual((cell(at: 0, in: controller) as? LegacyCell)?.label.text, "Second updated")
            XCTAssertEqual((cell(at: 1, in: controller) as? LegacyCell)?.label.text, "First updated")

            await performUpdate { done in
                controller.setItems([Row(id: 2, title: "Retained"), Row(id: 3, title: "Inserted")], animated: false, completion: done)
            }
            layout(controller)

            XCTAssertEqual(controller.itemIDs, [2, 3])
            XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 0), 2)
            XCTAssertEqual((cell(at: 0, in: controller) as? LegacyCell)?.label.text, "Retained")
            XCTAssertEqual((cell(at: 1, in: controller) as? LegacyCell)?.label.text, "Inserted")
        }
    }

    func testExplicitRefreshUpdatesPlainModelWithoutChangingIdentity() async throws {
        let model = TitleModel()
        let renderer: ScreenCellRenderer<Row> = Patchwork.legacyCell(LegacyCell.self) { cell, _ in
            cell.label.text = model.title
        }
        let controller = Screen([Row(id: 1, title: "Stable row")]) { _ in renderer }.makeViewController()

        try await withWindow(controller) {
            let original = try XCTUnwrap(cell(at: 0, in: controller) as? LegacyCell)
            XCTAssertEqual(original.label.text, "Before refresh")

            for title in ["After first refresh", "After second refresh"] {
                model.title = title
                await performUpdate { done in
                    controller.refreshContent(completion: done)
                }
                layout(controller)
                let refreshed = try XCTUnwrap(cell(at: 0, in: controller) as? LegacyCell)
                XCTAssertTrue(refreshed === original, "A retained renderer must reconfigure its existing cell.")
                XCTAssertEqual(refreshed.label.text, title)
                XCTAssertEqual(controller.itemIDs, [1])
            }
        }
    }

    func testExplicitLayoutInvalidationChangesListToGridAndKeepsItems() async throws {
        let model = LayoutModel()
        let controller = Screen(
            [Row(id: 1, title: "First"), Row(id: 2, title: "Second")],
            renderer: makeRenderers()
        )
        .layout { _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1.0 / CGFloat(model.columns)),
                heightDimension: .fractionalHeight(1)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(72)),
                subitems: Array(repeating: item, count: model.columns)
            )
            return NSCollectionLayoutSection(group: group)
        }
        .makeViewController()

        try await withWindow(controller) {
            let collection = try XCTUnwrap(controller.collectionView)
            let firstListFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
            let secondListFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame
            XCTAssertGreaterThanOrEqual(secondListFrame.minY, firstListFrame.maxY)

            model.columns = 2
            controller.invalidateLayout()
            layout(controller)

            let firstGridFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
            let secondGridFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame
            XCTAssertEqual(firstGridFrame.minY, secondGridFrame.minY, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(secondGridFrame.minX, firstGridFrame.maxX - 0.5)
            XCTAssertLessThan(firstGridFrame.width, firstListFrame.width)
            XCTAssertEqual(controller.itemIDs, [1, 2])
        }
    }

    func testControllerIsReleasedAfterRemovingWindowRoot() async {
        var controller: ScreenViewController<Int, Row>? = Screen(
            [Row(id: 1, title: "Legacy"), Row(id: 2, title: "SwiftUI", family: .swiftUI)],
            renderer: makeRenderers()
        ).makeViewController()
        let releasedController = WeakReference(controller)

        await withWindow(controller!) {
            XCTAssertNotNil(controller?.collectionView.dataSource)
        }
        controller = nil

        await assertEventually("Removing the window root releases its screen controller") {
            releasedController.value == nil
        }
    }

    func testUIViewAdapterReusesHostedViewAndUpdatesLatestPayload() async throws {
        var factoryCalls = 0
        let renderer: ScreenCellRenderer<Row> = Patchwork.uiView(make: { () -> UILabel in
            factoryCalls += 1
            return UILabel()
        }) { label, row in
            label.text = row.title
        }
        let controller = Screen([Row(id: 1, title: "Original")]) { _ in renderer }.makeViewController()

        try await withWindow(controller) {
            let originalCell = try XCTUnwrap(cell(at: 0, in: controller))
            let originalHost = originalCell.contentView
            let originalLabel = try XCTUnwrap(originalHost.subviews.compactMap { $0 as? UILabel }.first)
            let initialFactoryCalls = factoryCalls
            XCTAssertGreaterThan(initialFactoryCalls, 0)
            XCTAssertEqual(originalLabel.text, "Original")

            for title in ["Updated once", "Updated twice"] {
                await performUpdate { done in
                    controller.setItems([Row(id: 1, title: title)], animated: false, completion: done)
                }
                layout(controller)
                let currentCell = try XCTUnwrap(cell(at: 0, in: controller))
                XCTAssertTrue(currentCell === originalCell)
                XCTAssertTrue(currentCell.contentView === originalHost)
                XCTAssertEqual(originalLabel.text, title)
                XCTAssertEqual(factoryCalls, initialFactoryCalls, "Payload changes must update the existing UIView.")
            }
        }
    }

    func testLegacyAdapterPreservesOriginalHandlerWithoutStackingOnReconfigure() async throws {
        let renderer: ScreenCellRenderer<Row> = Patchwork.legacyCell(StatefulLegacyCell.self) { cell, row in
            cell.renderedTitle = row.title
        }
        let controller = Screen([Row(id: 1, title: "Original")]) { _ in renderer }.makeViewController()

        try await withWindow(controller) {
            for revision in 1...3 {
                let title = "Revision \(revision)"
                await performUpdate { done in
                    controller.setItems([Row(id: 1, title: title)], animated: false, completion: done)
                }
                layout(controller)
                let cell = try XCTUnwrap(cell(at: 0, in: controller) as? StatefulLegacyCell)
                XCTAssertEqual(cell.renderedTitle, title)

                let callsBeforeUpdate = cell.originalHandlerCalls
                var state = cell.configurationState
                state.isSelected = revision.isMultiple(of: 2)
                let handler = try XCTUnwrap(cell.configurationUpdateHandler)
                handler(cell, state)

                XCTAssertEqual(cell.originalHandlerCalls, callsBeforeUpdate + 1,
                               "Each configuration update must call the pre-existing handler exactly once.")
                XCTAssertEqual(cell.lastSelection, state.isSelected)
                XCTAssertEqual(cell.renderedTitle, title, "The wrapper must configure the latest payload.")
            }
        }
    }

    func testSectionReorderMovesStableItemAndUpdatesPayloads() async {
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "One"), Row(id: 2, title: "Two")]),
            ScreenSection(id: .second, items: [Row(id: 3, title: "Three")]),
        ]
        let controller = Screen(initial, renderer: makeRenderers()).makeViewController()

        await withWindow(controller) {
            await performUpdate { done in
                controller.setSections([
                    ScreenSection(id: .second, items: [Row(id: 3, title: "Three updated"), Row(id: 1, title: "One moved")]),
                    ScreenSection(id: .first, items: [Row(id: 2, title: "Two updated")]),
                ], animated: false, completion: done)
            }
            layout(controller)

            XCTAssertEqual(controller.sectionIDs, [.second, .first])
            XCTAssertEqual(controller.itemIDs, [3, 1, 2])
            XCTAssertEqual(controller.itemIDs(in: .second), [3, 1])
            XCTAssertEqual(controller.itemIDs(in: .first), [2])
            XCTAssertEqual(controller.collectionView.numberOfSections, 2)
            XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 0), 2)
            XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 1), 1)
            XCTAssertEqual((cell(at: 0, section: 0, in: controller) as? LegacyCell)?.label.text, "Three updated")
            XCTAssertEqual((cell(at: 1, section: 0, in: controller) as? LegacyCell)?.label.text, "One moved")
            XCTAssertEqual((cell(at: 0, section: 1, in: controller) as? LegacyCell)?.label.text, "Two updated")
        }
    }

    func testSectionsCanBeRemovedEmptiedAndRestored() async {
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "One")]),
            ScreenSection(id: .second, items: [Row(id: 2, title: "Two")]),
        ]
        let controller = Screen(initial, renderer: makeRenderers()).makeViewController()

        await withWindow(controller) {
            await performUpdate { done in
                controller.setSections([ScreenSection(id: .first, items: [])], animated: false, completion: done)
            }
            layout(controller)
            XCTAssertEqual(controller.sectionIDs, [.first])
            XCTAssertTrue(controller.itemIDs.isEmpty)
            XCTAssertTrue(controller.itemIDs(in: .second).isEmpty, "A removed section has no items.")
            XCTAssertEqual(controller.collectionView.numberOfSections, 1)
            XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 0), 0)

            await performUpdate { done in
                controller.setSections([], animated: false, completion: done)
            }
            layout(controller)
            XCTAssertTrue(controller.sectionIDs.isEmpty)
            XCTAssertEqual(controller.collectionView.numberOfSections, 0)

            await performUpdate { done in
                controller.setSections([
                    ScreenSection(id: .second, items: [Row(id: 2, title: "Two restored")]),
                    ScreenSection(id: .first, items: []),
                    ScreenSection(id: .third, items: [Row(id: 4, title: "Four inserted")]),
                ], animated: false, completion: done)
            }
            layout(controller)
            XCTAssertEqual(controller.sectionIDs, [.second, .first, .third])
            XCTAssertEqual(controller.itemIDs, [2, 4])
            XCTAssertEqual(controller.collectionView.numberOfSections, 3)
            XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 1), 0)
            XCTAssertEqual(controller.itemIDs(in: .second), [2])
            XCTAssertTrue(controller.itemIDs(in: .first).isEmpty)
            XCTAssertEqual(controller.itemIDs(in: .third), [4])
            XCTAssertEqual((cell(at: 0, section: 0, in: controller) as? LegacyCell)?.label.text, "Two restored")
            XCTAssertEqual((cell(at: 0, section: 2, in: controller) as? LegacyCell)?.label.text, "Four inserted")
        }
    }

    func testLayoutsAndHeadersResolveSectionIdentityAfterReorder() async throws {
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "Short section")]),
            ScreenSection(id: .second, items: [Row(id: 2, title: "Tall section")]),
        ]
        let headerKind = UICollectionView.elementKindSectionHeader
        let registration = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: headerKind) {
            _, _, _ in
        }
        let controller = Screen(initial, renderer: makeRenderers())
            .layout { sectionID, _ in
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)
                ))
                let height: CGFloat = sectionID == .first ? 48 : 96
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                    subitems: [item]
                )
                let section = NSCollectionLayoutSection(group: group)
                section.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(28)),
                        elementKind: headerKind,
                        alignment: .top
                    )
                ]
                return section
            }
            .supplementary([
                ScreenSupplementaryRenderer<TestSectionID>(elementKind: headerKind, make: { (collection, indexPath) -> SectionHeader in
                    collection.dequeueConfiguredReusableSupplementary(using: registration, for: indexPath)
                }, update: { header, sectionID in
                    header.representedSection = sectionID
                    header.label.text = sectionID.rawValue
                })
            ])
            .makeViewController()

        try await withWindow(controller) {
            let collection = try XCTUnwrap(controller.collectionView)
            let firstPath = IndexPath(item: 0, section: 0)
            let secondPath = IndexPath(item: 0, section: 1)
            XCTAssertEqual(try XCTUnwrap(collection.layoutAttributesForItem(at: firstPath)).frame.height, 48, accuracy: 0.5)
            XCTAssertEqual(try XCTUnwrap(collection.layoutAttributesForItem(at: secondPath)).frame.height, 96, accuracy: 0.5)
            XCTAssertEqual((collection.supplementaryView(forElementKind: headerKind, at: firstPath) as? SectionHeader)?.representedSection, .first)
            XCTAssertEqual((collection.supplementaryView(forElementKind: headerKind, at: secondPath) as? SectionHeader)?.representedSection, .second)

            await performUpdate { done in
                controller.setSections([initial[1], initial[0]], animated: false, completion: done)
            }
            layout(controller)

            await assertEventually("Layout and headers follow stable section IDs after index changes") {
                let firstHeader = collection.supplementaryView(forElementKind: headerKind, at: firstPath) as? SectionHeader
                let secondHeader = collection.supplementaryView(forElementKind: headerKind, at: secondPath) as? SectionHeader
                return collection.layoutAttributesForItem(at: firstPath)?.frame.height == 96
                    && collection.layoutAttributesForItem(at: secondPath)?.frame.height == 48
                    && firstHeader?.representedSection == .second
                    && secondHeader?.representedSection == .first
            }
            XCTAssertEqual(controller.sectionIDs, [.second, .first])
            XCTAssertEqual((collection.supplementaryView(forElementKind: headerKind, at: firstPath) as? SectionHeader)?.label.text, "second")
            XCTAssertEqual((collection.supplementaryView(forElementKind: headerKind, at: secondPath) as? SectionHeader)?.label.text, "first")
        }
    }

    func testAnimatedSnapshotsCompleteFIFOWithMovesAndRendererReplacement() async throws {
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "One"), Row(id: 2, title: "Two")]),
            ScreenSection(id: .second, items: [Row(id: 3, title: "Three")]),
        ]
        let controller = Screen(initial, renderer: makeRenderers()).makeViewController()

        try await withWindow(controller) {
            let completed = XCTestExpectation(description: "Three animated snapshots complete in order")
            completed.expectedFulfillmentCount = 3
            var order: [String] = []

            controller.setSections([
                ScreenSection(id: .second, items: [Row(id: 3, title: "Three moved"), Row(id: 1, title: "One moved")]),
                ScreenSection(id: .first, items: [Row(id: 2, title: "Two retained")]),
            ], animated: true) {
                order.append("move")
                XCTAssertEqual(controller.sectionIDs, [.second, .first])
                XCTAssertEqual(controller.itemIDs, [3, 1, 2])
                completed.fulfill()
            }
            controller.setSections([
                ScreenSection(id: .second, items: [Row(id: 3, title: "Three again"), Row(id: 1, title: "One configured", family: .configuration)]),
                ScreenSection(id: .first, items: [Row(id: 2, title: "Two again")]),
            ], animated: true) {
                order.append("replace")
                self.layout(controller)
                XCTAssertEqual(controller.itemIDs(in: .second), [3, 1])
                let replacement = self.cell(at: 1, section: 0, in: controller) as? UICollectionViewListCell
                XCTAssertEqual((replacement?.contentConfiguration as? UIListContentConfiguration)?.text, "One configured")
                completed.fulfill()
            }
            controller.setSections([
                ScreenSection(id: .first, items: [Row(id: 2, title: "Two final"), Row(id: 1, title: "One final", family: .configuration)]),
                ScreenSection(id: .second, items: [Row(id: 3, title: "Three final")]),
            ], animated: true) {
                order.append("final")
                XCTAssertEqual(controller.sectionIDs, [.first, .second])
                XCTAssertEqual(controller.itemIDs, [2, 1, 3])
                completed.fulfill()
            }

            await waitForLifecycle(completed)
            self.layout(controller)
            XCTAssertEqual(order, ["move", "replace", "final"])
            let finalConfiguredCell = try XCTUnwrap(self.cell(at: 1, section: 0, in: controller) as? UICollectionViewListCell)
            XCTAssertEqual((finalConfiguredCell.contentConfiguration as? UIListContentConfiguration)?.text, "One final")
            XCTAssertEqual((self.cell(at: 0, section: 1, in: controller) as? LegacyCell)?.label.text, "Three final")
        }
    }

    func testReentrantCompletionEnqueuesBehindPendingRefreshAndSnapshot() async {
        let model = TitleModel()
        let renderer: ScreenCellRenderer<Row> = Patchwork.legacyCell(LegacyCell.self) { cell, row in
            cell.label.text = row.title + " / " + model.title
        }
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "One")]),
            ScreenSection(id: .second, items: [Row(id: 2, title: "Two")]),
        ]
        let controller = Screen(initial) { _ in renderer }.title { model.title }.makeViewController()

        await withWindow(controller) {
            let completed = XCTestExpectation(description: "Reentrant work follows operations already queued")
            completed.expectedFulfillmentCount = 4
            var order: [String] = []

            controller.setSections([initial[1], initial[0]], animated: true) {
                order.append("animated")
                XCTAssertEqual(controller.sectionIDs, [.second, .first])
                controller.setSections([
                    ScreenSection(id: .third, items: [Row(id: 3, title: "Reentrant")])
                ], animated: false) {
                    order.append("reentrant")
                    XCTAssertEqual(controller.sectionIDs, [.third])
                    XCTAssertEqual(controller.itemIDs, [3])
                    completed.fulfill()
                }
                completed.fulfill()
            }
            model.title = "Queued refresh"
            controller.refreshContent {
                order.append("refresh")
                self.layout(controller)
                XCTAssertEqual(controller.sectionIDs, [.second, .first])
                XCTAssertEqual(controller.title, "Queued refresh")
                XCTAssertEqual((self.cell(at: 0, section: 0, in: controller) as? LegacyCell)?.label.text, "Two / Queued refresh")
                completed.fulfill()
            }
            controller.setSections([
                ScreenSection(id: .first, items: [Row(id: 1, title: "Pending snapshot")])
            ], animated: false) {
                order.append("pending")
                XCTAssertEqual(controller.sectionIDs, [.first])
                XCTAssertEqual(controller.itemIDs, [1])
                completed.fulfill()
            }

            await waitForLifecycle(completed)
            self.layout(controller)
            XCTAssertEqual(order, ["animated", "refresh", "pending", "reentrant"])
            XCTAssertEqual((self.cell(at: 0, in: controller) as? LegacyCell)?.label.text, "Reentrant / Queued refresh")
        }
    }

    func testPlainModelRefreshUpdatesHeaderAndFooterWithoutDequeue() async throws {
        let model = SupplementaryModel()
        let controller = makeSupplementaryController([
            ScreenSection(id: .first, items: [Row(id: 1, title: "Cell")])
        ], model: model)

        try await withWindow(controller) {
            let collection = try XCTUnwrap(controller.collectionView)
            let path = IndexPath(item: 0, section: 0)
            let headerKind = UICollectionView.elementKindSectionHeader
            let footerKind = UICollectionView.elementKindSectionFooter
            let header = try XCTUnwrap(collection.supplementaryView(forElementKind: headerKind, at: path) as? SectionHeader)
            let footer = try XCTUnwrap(collection.supplementaryView(forElementKind: footerKind, at: path) as? SectionHeader)
            let initialCell = try XCTUnwrap(self.cell(at: 0, in: controller) as? LegacyCell)
            let initialDequeues = model.dequeueCounts
            XCTAssertEqual(header.label.text, "Header first · 0")
            XCTAssertEqual(footer.label.text, "Footer first · 0")
            XCTAssertEqual(initialCell.label.text, "Cell · 0")

            model.revision = 1
            let supplementaryCompleted = XCTestExpectation(description: "Explicit supplementary refresh completes")
            controller.refreshSupplementaryContent { supplementaryCompleted.fulfill() }
            await waitForLifecycle(supplementaryCompleted)
            XCTAssertEqual(header.label.text, "Header first · 1")
            XCTAssertEqual(footer.label.text, "Footer first · 1")
            XCTAssertEqual(initialCell.label.text, "Cell · 0", "Supplementary-only refresh does not reconfigure cells.")
            XCTAssertEqual(model.dequeueCounts, initialDequeues)
            XCTAssertTrue(collection.supplementaryView(forElementKind: headerKind, at: path) === header)
            XCTAssertTrue(collection.supplementaryView(forElementKind: footerKind, at: path) === footer)

            model.revision = 2
            let contentCompleted = XCTestExpectation(description: "Content refresh also refreshes visible supplementaries")
            controller.refreshContent { contentCompleted.fulfill() }
            await waitForLifecycle(contentCompleted)
            XCTAssertEqual(header.label.text, "Header first · 2")
            XCTAssertEqual(footer.label.text, "Footer first · 2")
            XCTAssertEqual(initialCell.label.text, "Cell · 2")
            XCTAssertEqual(controller.title, "Revision 2")
            XCTAssertEqual(model.dequeueCounts, initialDequeues)
            XCTAssertTrue(collection.supplementaryView(forElementKind: headerKind, at: path) === header)
            XCTAssertTrue(collection.supplementaryView(forElementKind: footerKind, at: path) === footer)
            XCTAssertTrue(self.cell(at: 0, in: controller) === initialCell)
        }
    }

    func testQueuedRemovalReorderAndSupplementaryRefreshUseFinalSectionIDs() async throws {
        let model = SupplementaryModel()
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "One")]),
            ScreenSection(id: .second, items: [Row(id: 2, title: "Two")]),
            ScreenSection(id: .third, items: [Row(id: 3, title: "Three")]),
        ]
        let controller = makeSupplementaryController(initial, model: model)

        try await withWindow(controller) {
            let completed = XCTestExpectation(description: "Removed sections never receive the queued final refresh")
            completed.expectedFulfillmentCount = 3
            var order: [String] = []
            var dequeuesBeforeRefresh: [String: Int] = [:]

            controller.setSections([initial[1], initial[2]], animated: true) {
                order.append("remove")
                XCTAssertEqual(controller.sectionIDs, [.second, .third])
                completed.fulfill()
            }
            controller.setSections([initial[2], initial[1]], animated: true) {
                order.append("reorder")
                self.layout(controller)
                model.updatedSections.removeAll()
                dequeuesBeforeRefresh = model.dequeueCounts
                completed.fulfill()
            }
            model.revision = 1
            controller.refreshSupplementaryContent {
                order.append("refresh")
                XCTAssertEqual(controller.sectionIDs, [.third, .second])
                XCTAssertEqual(Set(model.updatedSections), Set([TestSectionID.third, .second]))
                XCTAssertEqual(model.dequeueCounts, dequeuesBeforeRefresh)
                completed.fulfill()
            }

            await waitForLifecycle(completed)
            self.layout(controller)
            XCTAssertEqual(order, ["remove", "reorder", "refresh"])
            let collection = try XCTUnwrap(controller.collectionView)
            for (sectionIndex, sectionID) in [TestSectionID.third, .second].enumerated() {
                let path = IndexPath(item: 0, section: sectionIndex)
                for (kind, name) in [
                    (UICollectionView.elementKindSectionHeader, "Header"),
                    (UICollectionView.elementKindSectionFooter, "Footer"),
                ] {
                    let view = try XCTUnwrap(collection.supplementaryView(forElementKind: kind, at: path) as? SectionHeader)
                    XCTAssertEqual(view.representedSection, sectionID)
                    XCTAssertEqual(view.label.text, "\(name) \(sectionID.rawValue) · 1")
                }
            }
        }
    }

    func testLongReentrantSupplementaryChainCompletesEveryRequestInOrder() async throws {
        let model = SupplementaryModel()
        let controller = makeSupplementaryController([
            ScreenSection(id: .first, items: [Row(id: 1, title: "Cell")])
        ], model: model)

        try await withWindow(controller) {
            let header = try XCTUnwrap(controller.collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? SectionHeader)
            let initialDequeues = model.dequeueCounts
            let requestCount = 1_000
            var completedIndices: [Int] = []
            let completed = XCTestExpectation(description: "Every finite reentrant refresh completes")

            @MainActor
            func schedule(_ index: Int) {
                model.revision = index
                controller.refreshSupplementaryContent {
                    completedIndices.append(index)
                    XCTAssertEqual(header.label.text, "Header first · \(index)")
                    if index + 1 < requestCount {
                        schedule(index + 1)
                    } else {
                        completed.fulfill()
                    }
                }
            }

            schedule(0)
            await waitForLifecycle(completed)
            XCTAssertEqual(completedIndices, Array(0..<requestCount))
            XCTAssertEqual(header.label.text, "Header first · 999")
            XCTAssertEqual(model.dequeueCounts, initialDequeues)
        }
    }

    func testRemovingControllerDuringAnimationReleasesPendingCompletionCaptures() async {
        let initial: [ScreenSection<TestSectionID, Row>] = [
            ScreenSection(id: .first, items: [Row(id: 1, title: "One")]),
            ScreenSection(id: .second, items: [Row(id: 2, title: "Two"), Row(id: 3, title: "Three")]),
        ]
        var controller: ScreenViewController<TestSectionID, Row>? = Screen(initial, renderer: makeRenderers()).makeViewController()
        var pendingToken: TitleModel? = TitleModel()
        let weakController = WeakReference(controller)
        let weakToken = WeakReference(pendingToken)
        var completedOperations: [String] = []

        await withWindow(controller!) {
            controller?.setSections([
                ScreenSection(id: .second, items: [Row(id: 3, title: "Three moved"), Row(id: 1, title: "One configured", family: .configuration)]),
                ScreenSection(id: .first, items: [Row(id: 2, title: "Two moved")]),
            ], animated: true) {
                completedOperations.append("snapshot")
            }
            controller?.refreshSupplementaryContent { [token = pendingToken!] in
                XCTAssertEqual(token.title, "Before refresh")
                completedOperations.append("refresh")
            }
            XCTAssertTrue(completedOperations.isEmpty, "The window must be removed while the animated request is still active.")
            // Return without awaiting the animation: the shared harness removes the
            // root and waits for the real disappearance lifecycle while work is pending.
        }
        pendingToken = nil
        controller = nil

        await assertEventually("In-flight updates and queued callbacks do not retain a removed controller") {
            weakController.value == nil && weakToken.value == nil
        }
        XCTAssertEqual(
            completedOperations,
            Array(["snapshot", "refresh"].prefix(completedOperations.count)),
            "Callbacks that finish before disposal must keep FIFO order; disposal need not complete pending work."
        )
    }

    private func makeSupplementaryController(
        _ sections: [ScreenSection<TestSectionID, Row>],
        model: SupplementaryModel
    ) -> ScreenViewController<TestSectionID, Row> {
        let kinds = [
            (UICollectionView.elementKindSectionHeader, "Header", NSRectAlignment.top),
            (UICollectionView.elementKindSectionFooter, "Footer", NSRectAlignment.bottom),
        ]
        let supplementaries = kinds.map { kind, name, _ in
            let registration = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: kind) { _, _, _ in }
            return ScreenSupplementaryRenderer<TestSectionID>(elementKind: kind, make: { (collection, indexPath) -> SectionHeader in
                model.dequeueCounts[kind, default: 0] += 1
                return collection.dequeueConfiguredReusableSupplementary(using: registration, for: indexPath)
            }, update: { header, sectionID in
                model.updatedSections.append(sectionID)
                header.representedSection = sectionID
                header.label.text = "\(name) \(sectionID.rawValue) · \(model.revision)"
            })
        }
        let renderer: ScreenCellRenderer<Row> = Patchwork.legacyCell(LegacyCell.self) { cell, row in
            cell.label.text = "\(row.title) · \(model.revision)"
        }
        return Screen(sections) { _ in renderer }
            .title { "Revision \(model.revision)" }
            .layout { _, _ in
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)
                ))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(72)),
                    subitems: [item]
                )
                let section = NSCollectionLayoutSection(group: group)
                section.boundarySupplementaryItems = kinds.map { kind, _, alignment in
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(28)),
                        elementKind: kind,
                        alignment: alignment
                    )
                }
                return section
            }
            .supplementary(supplementaries)
            .makeViewController()
    }

    private func makeRenderers() -> (Row) -> ScreenCellRenderer<Row> {
        let legacy: ScreenCellRenderer<Row> = Patchwork.legacyCell(LegacyCell.self) { cell, row in
            cell.label.text = row.title
        }
        let configuration: ScreenCellRenderer<Row> = Patchwork.configuration { row, _ in
            var content = UIListContentConfiguration.cell()
            content.text = row.title
            return content
        }
        let swiftUI: ScreenCellRenderer<Row> = Patchwork.swiftUI { row in
            Text(row.title)
        }
        return { row in
            switch row.family {
            case .legacy: legacy
            case .configuration: configuration
            case .swiftUI: swiftUI
            }
        }
    }

    private func cell<SectionID: Hashable & Sendable>(
        at index: Int,
        section: Int = 0,
        in controller: ScreenViewController<SectionID, Row>
    ) -> UICollectionViewCell? {
        controller.collectionView.cellForItem(at: IndexPath(item: index, section: section))
    }

    private func layout<SectionID: Hashable & Sendable>(_ controller: ScreenViewController<SectionID, Row>) {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.collectionView.layoutIfNeeded()
    }

    private func withWindow<SectionID: Hashable & Sendable>(
        _ controller: ScreenViewController<SectionID, Row>,
        perform assertions: () async throws -> Void
    ) async rethrows {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previousKeyWindow = scene?.windows.first(where: \.isKeyWindow)
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = LifecycleHost(content: controller)

        // A committed layer transaction does not guarantee that UIKit has ended
        // its appearance transition. Wait for the actual controller callback.
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await waitForLifecycle(host.appeared)
        layout(controller)

        do {
            try await assertions()
        } catch {
            await detach(window, host: host, restoring: previousKeyWindow)
            throw error
        }
        await detach(window, host: host, restoring: previousKeyWindow)
    }

    private func detach(_ window: UIWindow, host: LifecycleHost, restoring previousKeyWindow: UIWindow?) async {
        // Removing the root starts disappearance; keep the window and its host
        // alive until UIKit reports that disappearance has completed.
        window.rootViewController = nil
        await waitForLifecycle(host.disappeared)
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }

    private func performUpdate(_ update: (@escaping @MainActor () -> Void) -> Void) async {
        let completed = XCTestExpectation(description: "Queued update completes")
        update { completed.fulfill() }
        await waitForLifecycle(completed)
    }

    private func waitForLifecycle(_ expectation: XCTestExpectation) async {
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed, expectation.expectationDescription)
    }

    private func assertEventually(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } },
            object: nil
        )
        expectation.expectationDescription = description
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed, description, file: file, line: line)
    }
}
