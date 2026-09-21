import Foundation
import Testing
@testable import ToNaTo

@Suite("ToNaTo Detail Screen")
struct ToNaToDetailScreenTests {
    @MainActor
    @Test("detail view model reflects synchronous compare model updates")
    func detailViewModelReflectsSynchronousCompareModelUpdates() async throws {
        let entryID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: entryID, name: "Entry", priceText: "4.99", quantityText: "500", unit: .gram)
        ])
        let viewModel = ToNaToDetailViewModel(model: model)

        let initialRow = try #require(viewModel.rows.first)
        #expect(initialRow.subtitle.contains("4.99"))

        model.updateText("7.25", entryID: entryID, field: .price)

        let updatedRow = try #require(viewModel.rows.first)
        #expect(updatedRow.subtitle.contains("7.25"))
    }

    @MainActor
    @Test("detail view model recalculates cheapest summary when entries change")
    func detailViewModelRecalculatesCheapestSummaryWhenEntriesChange() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: firstID, name: "First", priceText: "10.00", quantityText: "1", unit: .kilogram),
            ProductEntry(id: secondID, name: "Second", priceText: "8.00", quantityText: "1", unit: .kilogram),
        ])
        let viewModel = ToNaToDetailViewModel(model: model)
        #expect(viewModel.cheapestSummary.contains("Second"))

        model.updateText("5.00", entryID: firstID, field: .price)
        #expect(viewModel.cheapestSummary.contains("First"))
    }

    @MainActor
    @Test("detail screen factory builds with injected model")
    func detailScreenFactoryBuildsWithInjectedModel() async throws {
        let model = ToNaToCompareModel(entries: [])
        let viewController = ToNaToDetailScreenFactory
            .makeDetailScreen(model: model)
            .makeViewController()

        #expect(viewController.title == "Detail")
    }
}
