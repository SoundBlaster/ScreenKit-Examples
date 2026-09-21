import Testing
@testable import ToNaTo

@Suite("ProductUnit Conversion")
struct ProductUnitConversionTests {
    @Test("identity conversion returns input value")
    func identityConversionReturnsInputValue() async throws {
        let value = ProductUnitConverter.convert(123.45, from: .gram, to: .gram)
        #expect(value == 123.45)
    }

    @Test("grams convert to kilograms")
    func gramsConvertToKilograms() async throws {
        let value = ProductUnitConverter.convert(500, from: .gram, to: .kilogram)
        #expect(abs(value - 0.5) < 0.000_000_1)
    }

    @Test("pounds convert to ounces")
    func poundsConvertToOunces() async throws {
        let value = ProductUnitConverter.convert(1, from: .pound, to: .ounce)
        #expect(abs(value - 16.0) < 0.000_001)
    }

    @Test("round-trip conversion stays within tolerance")
    func roundTripConversionStaysWithinTolerance() async throws {
        let pounds = ProductUnitConverter.convert(2.5, from: .kilogram, to: .pound)
        let kilograms = ProductUnitConverter.convert(pounds, from: .pound, to: .kilogram)
        #expect(abs(kilograms - 2.5) < 0.000_001)
    }

    @Test("canonical grams helper matches pair conversion")
    func canonicalGramsHelperMatchesPairConversion() async throws {
        let gramsFromOunce = ProductUnitConverter.normalizeToGrams(3.0, unit: .ounce)
        let direct = ProductUnitConverter.convert(3.0, from: .ounce, to: .gram)
        #expect(abs(gramsFromOunce - direct) < 0.000_001)
    }

    @Test("normalize to grams uses expected constants for each supported unit")
    func normalizeToGramsUsesExpectedConstantsForEachSupportedUnit() async throws {
        #expect(abs(ProductUnitConverter.normalizeToGrams(1.0, unit: .gram) - 1.0) < 0.000_000_1)
        #expect(abs(ProductUnitConverter.normalizeToGrams(1.0, unit: .kilogram) - 1_000.0) < 0.000_000_1)
        #expect(abs(ProductUnitConverter.normalizeToGrams(1.0, unit: .ounce) - 28.349_523_125) < 0.000_000_1)
        #expect(abs(ProductUnitConverter.normalizeToGrams(1.0, unit: .pound) - 453.592_37) < 0.000_000_1)
    }

    @Test("conversion preserves sign and zero values")
    func conversionPreservesSignAndZeroValues() async throws {
        #expect(ProductUnitConverter.convert(0, from: .gram, to: .kilogram) == 0)

        let convertedNegative = ProductUnitConverter.convert(-250, from: .gram, to: .kilogram)
        #expect(abs(convertedNegative + 0.25) < 0.000_000_1)
    }

    @Test("round-trip conversion across all unit pairs stays within tolerance")
    func roundTripConversionAcrossAllUnitPairsStaysWithinTolerance() async throws {
        let seedValue = 17.25
        for source in ProductUnit.allCases {
            for target in ProductUnit.allCases {
                let converted = ProductUnitConverter.convert(seedValue, from: source, to: target)
                let restored = ProductUnitConverter.convert(converted, from: target, to: source)
                #expect(abs(restored - seedValue) < 0.000_001)
            }
        }
    }
}
