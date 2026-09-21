import Foundation

extension ProductUnit {
    var gramsPerUnit: Double {
        switch self {
        case .gram:
            return 1.0
        case .kilogram:
            return 1_000.0
        case .ounce:
            return 28.349_523_125
        case .pound:
            return 453.592_37
        }
    }
}

enum ProductUnitConverter {
    static func normalizeToGrams(_ value: Double, unit: ProductUnit) -> Double {
        value * unit.gramsPerUnit
    }

    static func convert(_ value: Double, from sourceUnit: ProductUnit, to targetUnit: ProductUnit) -> Double {
        guard sourceUnit != targetUnit else {
            return value
        }

        let grams = normalizeToGrams(value, unit: sourceUnit)
        return grams / targetUnit.gramsPerUnit
    }
}
