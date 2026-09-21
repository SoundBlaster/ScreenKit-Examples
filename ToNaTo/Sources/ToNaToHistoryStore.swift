import Foundation
import Observation

@MainActor
@Observable
final class ToNaToHistoryStore {
    static let shared = ToNaToHistoryStore()

    private(set) var snapshots: [ToNaToSnapshot] = []

    init() {}

    @discardableResult
    func record(
        entries: [ProductEntry],
        currency: ToNaToCurrency = .usd,
        createdAt: Date = Date()
    ) -> ToNaToSnapshot {
        let cheapestSelection = ToNaToCompareScreenFactory.cheapestSelection(
            entries: entries,
            referenceUnit: .kilogram
        )
        let cheapest = cheapestSelection.map {
            ToNaToSnapshot.Cheapest(
                entryID: $0.entryID,
                pricePerKilogram: $0.pricePerKilogram
            )
        }
        let snapshot = ToNaToSnapshot(
            id: UUID(),
            createdAt: createdAt,
            entries: entries,
            currency: currency,
            cheapest: cheapest
        )
        snapshots.insert(snapshot, at: 0)
        return snapshot
    }

    func clear() {
        snapshots.removeAll()
    }
}
