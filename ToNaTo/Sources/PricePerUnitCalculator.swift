import Foundation

struct PricePerUnitResult: Equatable, Sendable {
    let price: Double
    let quantity: Double
    let unit: ProductUnit
    let quantityInGrams: Double
    let pricePerGram: Double
    let pricePerKilogram: Double
}

enum PricePerUnitCalculator {
    static func calculate(price: Double, quantity: Double, unit: ProductUnit) -> PricePerUnitResult? {
        guard price > 0, quantity > 0 else {
            return nil
        }

        let quantityInGrams = ProductUnitConverter.normalizeToGrams(quantity, unit: unit)
        guard quantityInGrams > 0 else {
            return nil
        }

        let pricePerGram = price / quantityInGrams
        let pricePerKilogram = pricePerGram * 1_000.0

        return PricePerUnitResult(
            price: price,
            quantity: quantity,
            unit: unit,
            quantityInGrams: quantityInGrams,
            pricePerGram: pricePerGram,
            pricePerKilogram: pricePerKilogram
        )
    }

    static func calculate(for entry: ProductEntry) -> PricePerUnitResult? {
        guard entry.validation.isValid else {
            return nil
        }

        guard
            let price = parseDouble(entry.priceText),
            let quantity = parseDouble(entry.quantityText)
        else {
            return nil
        }

        return calculate(price: price, quantity: quantity, unit: entry.unit)
    }

    private static func parseDouble(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let value = Double(trimmed) {
            return value
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
