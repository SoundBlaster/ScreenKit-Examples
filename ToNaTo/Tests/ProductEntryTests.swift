import Testing
@testable import ToNaTo

@Suite("ProductEntry Validation")
struct ProductEntryTests {
    @Test("valid entry passes validation")
    func validEntryPassesValidation() async throws {
        let entry = ProductEntry(
            name: "Tomatoes",
            priceText: "5.99",
            quantityText: "1.5",
            unit: .kilogram
        )

        let validation = entry.validation

        #expect(validation.isValid)
        #expect(validation.issues.isEmpty)
    }

    @Test("invalid entry returns field-specific issues")
    func invalidEntryReturnsFieldSpecificIssues() async throws {
        let entry = ProductEntry(
            name: "   ",
            priceText: "0",
            quantityText: "-2",
            unit: .gram
        )

        let validation = entry.validation

        #expect(!validation.isValid)
        #expect(validation.issues.contains(.emptyName))
        #expect(validation.issues.contains(.nonPositivePrice))
        #expect(validation.issues.contains(.nonPositiveQuantity))
    }

    @Test("non-numeric values produce invalid-number issues")
    func nonNumericValuesProduceInvalidNumberIssues() async throws {
        let entry = ProductEntry(
            name: "Tomatoes",
            priceText: "abc",
            quantityText: "def",
            unit: .ounce
        )

        let validation = entry.validation

        #expect(!validation.isValid)
        #expect(validation.issues.contains(.invalidPrice))
        #expect(validation.issues.contains(.invalidQuantity))
    }
}
