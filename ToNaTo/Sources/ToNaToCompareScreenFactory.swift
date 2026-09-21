import Foundation

enum ToNaToCompareScreenFactory {
    static let heroCellAccessibilityIdentifier = "compare.hero.cell"
    static let addProductButtonAccessibilityIdentifier = "compare.addProduct.button"
    static let compareHeaderTitle = "Compare Unit Price"
    static let cheapestFooterPrefix = "Cheapest:"
    static let priceForWeightTitle = "Price/Weight"
    static let unavailablePriceForWeightText = "—"
    static let availableUnits: [ProductUnit] = [.gram, .kilogram, .ounce, .pound]
    static let tieTolerance = 0.000_000_1
    static let computeDebounceInterval: TimeInterval = 0.15

    struct HeroSummary: Hashable, Sendable {
        let title: String
        let subtitle: String
        let badgeText: String
    }

    struct CheapestSelection: Equatable, Sendable {
        let entryID: UUID
        let referenceUnit: ProductUnit
        let pricePerReferenceUnit: Double
        let pricePerKilogram: Double
    }

    enum RowHighlightStyle: Equatable, Sendable {
        case normal
        case cheapest
    }

    enum SortMode: CaseIterable, Equatable, Sendable {
        case pricePerKilogram
        case price
        case quantity

        var title: String {
            switch self {
            case .pricePerKilogram:
                return "Price/kg"
            case .price:
                return "Price"
            case .quantity:
                return "Quantity"
            }
        }
    }
}
