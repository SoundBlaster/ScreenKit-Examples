import Testing
@testable import ToNaTo

@Suite("PricePerUnit Calculator")
struct PricePerUnitCalculatorTests {
    @Test("computes price per gram and kilogram from raw values")
    func computesPricePerUnitFromRawValues() async throws {
        let result = PricePerUnitCalculator.calculate(price: 4.99, quantity: 500, unit: .gram)

        #expect(result != nil)
        #expect(abs((result?.pricePerGram ?? 0) - 0.00998) < 0.000_001)
        #expect(abs((result?.pricePerKilogram ?? 0) - 9.98) < 0.000_001)
    }

    @Test("computes price per unit from ProductEntry")
    func computesPricePerUnitFromProductEntry() async throws {
        let entry = ProductEntry(
            name: "Tomatoes",
            priceText: "6.50",
            quantityText: "1",
            unit: .kilogram
        )

        let result = PricePerUnitCalculator.calculate(for: entry)

        #expect(result != nil)
        #expect(abs((result?.pricePerKilogram ?? 0) - 6.5) < 0.000_001)
    }

    @Test("invalid ProductEntry returns nil")
    func invalidProductEntryReturnsNil() async throws {
        let entry = ProductEntry(
            name: "",
            priceText: "0",
            quantityText: "0",
            unit: .gram
        )

        let result = PricePerUnitCalculator.calculate(for: entry)

        #expect(result == nil)
    }
}
