import Foundation

/// Identity is independent of presentation, price, cheapest selection, and display order.
struct ToNaToCompareItem: Identifiable, Sendable {
    enum ID: Hashable, Sendable { case header, hero, entry(UUID), addProduct, footer }
    enum Content: Sendable {
        case header
        case hero(ToNaToCompareScreenFactory.HeroSummary)
        case entry(ProductEntry, number: Int, cheapest: Bool, priceForWeight: String)
        case addProduct
        case footer(String)
    }
    let id: ID
    let content: Content
}

extension ToNaToCompareScreenFactory {
    static func defaultEntries() -> [ProductEntry] {
        ["Product 1", "Product 2"].map { ProductEntry(name: $0, priceText: "", quantityText: "", unit: .gram) }
    }

    static func makeCompareItems(entries: [ProductEntry], currency: ToNaToCurrency, referenceUnit: ProductUnit) -> [ToNaToCompareItem] {
        let cheapest = cheapestSelection(entries: entries, referenceUnit: referenceUnit)?.entryID
        return [
            ToNaToCompareItem(id: .header, content: .header),
            ToNaToCompareItem(id: .hero, content: .hero(heroSummary(entries: entries, currency: currency, referenceUnit: referenceUnit))),
        ] + entries.enumerated().map { index, entry in
            ToNaToCompareItem(id: .entry(entry.id), content: .entry(entry, number: index + 1, cheapest: entry.id == cheapest,
                priceForWeight: priceForWeightText(entry: entry, currency: currency, referenceUnit: referenceUnit)))
        } + [
            ToNaToCompareItem(id: .addProduct, content: .addProduct),
            ToNaToCompareItem(id: .footer, content: .footer(cheapestFooterText(entries: entries, currency: currency, referenceUnit: referenceUnit))),
        ]
    }

    static func segmentIndex(for unit: ProductUnit) -> Int { availableUnits.firstIndex(of: unit) ?? 0 }
    static func unit(forSegmentIndex index: Int) -> ProductUnit? {
        availableUnits.indices.contains(index) ? availableUnits[index] : nil
    }
}
