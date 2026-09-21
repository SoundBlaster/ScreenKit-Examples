import Foundation
import Testing
@testable import ToNaTo

@Suite("ToNaTo History Screen")
struct ToNaToHistoryScreenTests {
    @MainActor
    @Test("history screen factory builds an isolated controller")
    func historyScreenFactoryBuildsAnIsolatedController() async throws {
        let store = ToNaToHistoryStore()

        let viewController = ToNaToHistoryScreenFactory
            .makeHistoryScreen(historyStore: store)
            .makeViewController()

        #expect(viewController.title == "History")
        viewController.loadViewIfNeeded()
        #expect(viewController.viewIfLoaded != nil)
    }

    @MainActor
    @Test("history screen factory accepts recorded snapshots without shared state")
    func historyScreenFactoryAcceptsRecordedSnapshotsWithoutSharedState() async throws {
        let store = ToNaToHistoryStore()
        let entry = ProductEntry(
            name: "Roma",
            priceText: "4.99",
            quantityText: "500",
            unit: .gram
        )
        let snapshot = store.record(entries: [entry], createdAt: Date(timeIntervalSince1970: 1))

        let viewController = ToNaToHistoryScreenFactory
            .makeHistoryScreen(historyStore: store)
            .makeViewController()

        #expect(viewController.title == "History")
        #expect(store.snapshots.map(\.id) == [snapshot.id])
        #expect(store.snapshots.first?.entries == [entry])
    }
}
