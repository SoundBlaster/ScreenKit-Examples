import Foundation

struct ToNaToSnapshot: Equatable, Sendable, Identifiable {
    struct Cheapest: Equatable, Sendable {
        let entryID: UUID
        let pricePerKilogram: Double
    }

    let id: UUID
    let createdAt: Date
    let entries: [ProductEntry]
    let currency: ToNaToCurrency
    let cheapest: Cheapest?
}
