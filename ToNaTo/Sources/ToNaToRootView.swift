import Foundation
import NestedA11yIDs
import SwiftUI

struct ToNaToRootView: View {
    private let demoEntry = ProductEntry(
        name: "Cherry Tomatoes",
        priceText: "4.99",
        quantityText: "500",
        unit: .gram
    )

    private var demoValidationLabel: String {
        let validation = demoEntry.validation
        if validation.isValid {
            return "Sample ProductEntry: valid (\(demoEntry.unit.symbol))"
        }

        let issues = validation.issues.map(\.message).joined(separator: ", ")
        return "Sample ProductEntry: invalid (\(issues))"
    }

    private var conversionSampleLabel: String {
        let converted = ProductUnitConverter.convert(500, from: .gram, to: .kilogram)
        return String(format: "Sample conversion: 500 g -> %.3f kg", converted)
    }

    private var pricePerUnitSampleLabel: String {
        guard let result = PricePerUnitCalculator.calculate(for: demoEntry) else {
            return "Sample price per kg: unavailable"
        }

        return String(format: "Sample price per kg: %.2f", result.pricePerKilogram)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(ToNaToAppCopy.title)
                .font(ToNaToTheme.Typography.appTitle)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                .nestedAccessibilityIdentifier("title")

            Text(ToNaToAppCopy.tagline)
                .font(ToNaToTheme.Typography.bodyEmphasis)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                .nestedAccessibilityIdentifier("tagline")

            Text(ToNaToAppCopy.frameworkLinkageLabel)
                .font(ToNaToTheme.Typography.bodyRegular.weight(.semibold))
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary.opacity(0.85))
                .nestedAccessibilityIdentifier("frameworkLinkage")

            Text(demoValidationLabel)
                .font(ToNaToTheme.Typography.bodyRegular.weight(.medium))
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary.opacity(0.8))
                .nestedAccessibilityIdentifier("validation")

            Text(conversionSampleLabel)
                .font(ToNaToTheme.Typography.bodyRegular.weight(.medium))
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary.opacity(0.8))
                .nestedAccessibilityIdentifier("conversion")

            Text(pricePerUnitSampleLabel)
                .font(ToNaToTheme.Typography.bodyRegular.weight(.medium))
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary.opacity(0.8))
                .nestedAccessibilityIdentifier("pricePerUnit")
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: ToNaToTheme.Palette.surface))
        .a11yRoot("root")
    }
}

#Preview {
    ToNaToRootView()
}
