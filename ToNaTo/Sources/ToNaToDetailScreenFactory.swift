import Foundation
import NestedA11yIDs
import Observation
import ScreenKit
import SwiftUI
import UIKit

enum ToNaToDetailScreenFactory {
    @MainActor
    static func makeDetailScreen(
        model: ToNaToCompareModel = .shared
    ) -> ControllerScreen<UIViewController> {
        ControllerScreen<UIViewController> {
            let controller = UIHostingController(
                rootView: ToNaToDetailView(
                    viewModel: ToNaToDetailViewModel(model: model)
                )
            )
            controller.title = "Detail"
            return controller
        }
    }
}

@MainActor
@Observable
final class ToNaToDetailViewModel {
    struct BreakdownRow: Equatable, Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
    }

    @ObservationIgnored private let model: ToNaToCompareModel

    init(model: ToNaToCompareModel = .shared) {
        self.model = model
    }

    var rows: [BreakdownRow] {
        let currency = model.currency
        let referenceUnit = model.referenceUnit
        return model.entries.map { entry in
            let normalizedText: String
            if let result = PricePerUnitCalculator.calculate(for: entry) {
                let pricePerUnit = result.pricePerGram * referenceUnit.gramsPerUnit
                normalizedText = ToNaToCompareScreenFactory.formattedPricePerUnit(
                    pricePerUnit,
                    currency: currency,
                    unit: referenceUnit
                )
            } else {
                normalizedText = "unavailable"
            }

            return BreakdownRow(
                id: entry.id,
                title: entry.name,
                subtitle:
                    "Price: \(currency.currencySymbol)\(entry.priceText) | Quantity: \(entry.quantityText) \(entry.unit.symbol) | Price/\(referenceUnit.symbol): \(normalizedText)"
            )
        }
    }

    var cheapestSummary: String {
        ToNaToCompareScreenFactory.cheapestFooterText(
            entries: model.entries,
            currency: model.currency,
            referenceUnit: model.referenceUnit
        )
    }
}

private struct ToNaToDetailView: View {
    let viewModel: ToNaToDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detail Breakdown")
                .font(ToNaToTheme.Typography.sectionTitle)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                .nestedAccessibilityIdentifier("title")

            ForEach(viewModel.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(ToNaToTheme.Typography.bodyEmphasis)
                        .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                        .nestedAccessibilityIdentifier("row.\(row.id.uuidString).title")
                    Text(row.subtitle)
                        .font(ToNaToTheme.Typography.bodyRegular)
                        .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                        .nestedAccessibilityIdentifier("row.\(row.id.uuidString).subtitle")
                }
            }

            Text(viewModel.cheapestSummary)
                .font(ToNaToTheme.Typography.heroEyebrow)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                .nestedAccessibilityIdentifier("cheapest")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: ToNaToTheme.Palette.surface))
        .a11yRoot("detail")
    }
}
