import Foundation
import Testing
@testable import ToNaTo

@Suite("ToNaTo History Store")
struct ToNaToHistoryStoreTests {
    @MainActor
    @Test("record inserts newest snapshot first and keeps entry copies")
    func recordInsertsNewestSnapshotFirstAndKeepsEntryCopies() async throws {
        let store = ToNaToHistoryStore()
        let firstDate = Date(timeIntervalSince1970: 1)
        let secondDate = Date(timeIntervalSince1970: 2)

        var baseEntries = [
            ProductEntry(name: "First", priceText: "4.00", quantityText: "1", unit: .kilogram),
        ]

        let firstSnapshot = store.record(entries: baseEntries, createdAt: firstDate)
        baseEntries[0].priceText = "10.00"
        let secondSnapshot = store.record(entries: baseEntries, createdAt: secondDate)

        #expect(store.snapshots.count == 2)
        #expect(store.snapshots[0].id == secondSnapshot.id)
        #expect(store.snapshots[1].id == firstSnapshot.id)
        #expect(store.snapshots[1].entries[0].priceText == "4.00")
    }

    @MainActor
    @Test("record stores cheapest metadata when available")
    func recordStoresCheapestMetadataWhenAvailable() async throws {
        let store = ToNaToHistoryStore()
        let cheapID = UUID()
        let entries = [
            ProductEntry(id: cheapID, name: "Cheap", priceText: "2.00", quantityText: "1", unit: .kilogram),
            ProductEntry(name: "Expensive", priceText: "8.00", quantityText: "1", unit: .kilogram),
        ]

        let snapshot = store.record(entries: entries)
        let cheapest = try #require(snapshot.cheapest)

        #expect(cheapest.entryID == cheapID)
        #expect(abs(cheapest.pricePerKilogram - 2.0) < 0.0001)
    }

    @MainActor
    @Test("clear removes all snapshots")
    func clearRemovesAllSnapshots() async throws {
        let store = ToNaToHistoryStore()
        _ = store.record(
            entries: [ProductEntry(name: "Entry", priceText: "4.00", quantityText: "1", unit: .kilogram)]
        )
        #expect(store.snapshots.isEmpty == false)

        store.clear()
        #expect(store.snapshots.isEmpty)
    }
    @MainActor
    @Test("saved currency remains part of the snapshot")
    func savedCurrency() {
        let model = ToNaToCompareModel()
        model.currency = .eur
        let store = ToNaToHistoryStore()
        store.record(entries: model.entries, currency: model.currency)
        model.currency = .gbp
        #expect(store.snapshots.first?.currency == .eur)
    }

}
