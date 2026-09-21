import Foundation
import Testing

@testable import ToNaTo

@Suite("ToNaTo Compare Rows")
struct ToNaToCompareRowsTests {
    @Test("default entries start blank for user input")
    func defaultEntriesStartBlankForUserInput() async throws {
        let entries = ToNaToCompareScreenFactory.defaultEntries()

        #expect(entries.count == 2)
        #expect(entries.map(\.name) == ["Product 1", "Product 2"])
        #expect(entries.allSatisfy { $0.priceText.isEmpty })
        #expect(entries.allSatisfy { $0.quantityText.isEmpty })
        #expect(entries.allSatisfy { $0.unit == .gram })
    }

    @Test("compare item mapping uses stable typed entry identifiers")
    func compareItemMappingUsesStableTypedEntryIdentifiers() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let entries = [
            ProductEntry(
                id: firstID,
                name: "Tomato A",
                priceText: "4.50",
                quantityText: "500",
                unit: .gram
            ),
            ProductEntry(
                id: secondID,
                name: "Tomato B",
                priceText: "5.20",
                quantityText: "1.0",
                unit: .kilogram
            ),
        ]

        let items = ToNaToCompareScreenFactory.makeCompareItems(
            entries: entries,
            currency: .usd,
            referenceUnit: .kilogram
        )

        #expect(items.map(\.id) == [.header, .hero, .entry(firstID), .entry(secondID), .addProduct, .footer])
    }

    @Test("entry item identifiers stay stable when cheapest payload changes")
    func entryItemIdentifiersStayStableWhenCheapestPayloadChanges() async throws {
        let firstID = UUID()
        let secondID = UUID()

        let firstPassEntries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "",
                quantityText: "",
                unit: .gram
            ),
        ]

        let secondPassEntries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "1.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let firstPassItems = ToNaToCompareScreenFactory.makeCompareItems(
            entries: firstPassEntries,
            currency: .usd,
            referenceUnit: .kilogram
        )
        let secondPassItems = ToNaToCompareScreenFactory.makeCompareItems(
            entries: secondPassEntries,
            currency: .usd,
            referenceUnit: .kilogram
        )

        #expect(firstPassItems.map(\.id) == secondPassItems.map(\.id))
        let firstCheapest = firstPassItems.compactMap { item -> UUID? in
            guard case let .entry(entry, _, cheapest, _) = item.content, cheapest else { return nil }
            return entry.id
        }
        let secondCheapest = secondPassItems.compactMap { item -> UUID? in
            guard case let .entry(entry, _, cheapest, _) = item.content, cheapest else { return nil }
            return entry.id
        }
        #expect(firstCheapest == [firstID])
        #expect(secondCheapest == [secondID])
    }

    @Test("compare item mapping includes typed header hero rows and footer")
    func compareItemMappingIncludesTypedHeaderHeroRowsAndFooter() async throws {
        let entries = [
            ProductEntry(
                id: UUID(),
                name: "Tomato A",
                priceText: "4.50",
                quantityText: "500",
                unit: .gram
            )
        ]

        let items = ToNaToCompareScreenFactory.makeCompareItems(
            entries: entries,
            currency: .usd,
            referenceUnit: .kilogram
        )
        #expect(items.map(\.id) == [.header, .hero, .entry(entries[0].id), .addProduct, .footer])
        guard case .hero(let summary) = items[1].content else {
            Issue.record("Expected hero content in the typed hero item")
            return
        }
        #expect(summary.title == "Best current value")
        guard case .addProduct = items[3].content else {
            Issue.record("Expected add-product content in the typed add item")
            return
        }
    }

    @Test("hero summary reports cheapest entry when available")
    func heroSummaryReportsCheapestEntryWhenAvailable() async throws {
        let entries = [
            ProductEntry(
                name: "Cherry Tomatoes",
                priceText: "4.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                name: "Roma Tomatoes",
                priceText: "6.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let summary = ToNaToCompareScreenFactory.heroSummary(
            entries: entries,
            currency: .usd,
            referenceUnit: .kilogram
        )
        #expect(summary.title == "Best current value")
        #expect(summary.subtitle.contains("Cherry Tomatoes"))
        #expect(summary.badgeText == "2 items compared")
    }

    @Test("hero summary reports guidance when cheapest is unavailable")
    func heroSummaryReportsGuidanceWhenCheapestIsUnavailable() async throws {
        let entries = [
            ProductEntry(
                name: "Invalid",
                priceText: "",
                quantityText: "",
                unit: .gram
            )
        ]

        let summary = ToNaToCompareScreenFactory.heroSummary(
            entries: entries,
            currency: .usd,
            referenceUnit: .kilogram
        )
        #expect(summary.title == "Best current value")
        #expect(summary.subtitle == "Add valid prices and quantities to see the cheapest option.")
        #expect(summary.badgeText == "0 items compared")
    }

    @Test("hero summary reports zero compared for default empty entries")
    func heroSummaryReportsZeroComparedForDefaultEmptyEntries() async throws {
        let summary = ToNaToCompareScreenFactory.heroSummary(
            entries: ToNaToCompareScreenFactory.defaultEntries(),
            currency: .usd,
            referenceUnit: .kilogram
        )

        #expect(summary.title == "Best current value")
        #expect(summary.subtitle == "Add valid prices and quantities to see the cheapest option.")
        #expect(summary.badgeText == "0 items compared")
    }

    @Test("hero summary counts only valid comparable entries")
    func heroSummaryCountsOnlyValidComparableEntries() async throws {
        let entries = [
            ProductEntry(
                name: "Valid",
                priceText: "5.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                name: "Invalid",
                priceText: "",
                quantityText: "",
                unit: .gram
            ),
        ]

        let summary = ToNaToCompareScreenFactory.heroSummary(
            entries: entries,
            currency: .usd,
            referenceUnit: .kilogram
        )
        #expect(summary.subtitle.contains("Valid"))
        #expect(summary.badgeText == "1 item compared")
    }

    @MainActor
    @Test("price for weight text shows computed value for valid entry")
    func priceForWeightTextShowsComputedValueForValidEntry() async throws {
        let entry = ProductEntry(
            name: "Tomatoes",
            priceText: "4.00",
            quantityText: "500",
            unit: .gram
        )

        let text = ToNaToCompareScreenFactory.priceForWeightText(
            entry: entry,
            currency: .usd,
            referenceUnit: .gram
        )
        let expected = ToNaToCompareScreenFactory.formattedPricePerUnit(
            0.008,
            currency: .usd,
            unit: .gram
        )
        #expect(text == expected)
    }

    @Test("price for weight text shows placeholder for invalid entry")
    func priceForWeightTextShowsPlaceholderForInvalidEntry() async throws {
        let entry = ProductEntry(
            name: "Invalid",
            priceText: "",
            quantityText: "500",
            unit: .gram
        )

        let text = ToNaToCompareScreenFactory.priceForWeightText(
            entry: entry,
            currency: .usd,
            referenceUnit: .gram
        )
        #expect(text == "—")
    }

    @MainActor
    @Test("synchronous price edits target the entry identifier")
    func synchronousPriceEditsTargetTheEntryIdentifier() async throws {
        let targetID = UUID()
        let otherID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: targetID, name: "Target", priceText: "4.50", quantityText: "500", unit: .gram),
            ProductEntry(id: otherID, name: "Other", priceText: "3.00", quantityText: "250", unit: .gram),
        ])

        model.updateText("7.25", entryID: targetID, field: .price)

        #expect(model.entries.first { $0.id == targetID }?.priceText == "7.25")
        #expect(model.entries.first { $0.id == otherID }?.priceText == "3.00")
    }

    @MainActor
    @Test("synchronous quantity edits preserve the latest typed value")
    func synchronousQuantityEditsPreserveTheLatestTypedValue() async throws {
        let targetID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: targetID, name: "Target", priceText: "4.50", quantityText: "500", unit: .gram),
        ])

        for text in ["7", "75", "750"] {
            model.updateText(text, entryID: targetID, field: .quantity)
        }

        #expect(model.entries.first?.quantityText == "750")
    }

    @MainActor
    @Test("unknown entry edits leave the model unchanged")
    func unknownEntryEditsLeaveTheModelUnchanged() async throws {
        let targetID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: targetID, name: "Target", priceText: "4.50", quantityText: "500", unit: .gram),
        ])

        model.updateText("7.25", entryID: UUID(), field: .price)

        #expect(model.entries.first?.priceText == "4.50")
    }

    @Test("unit segment mapping round-trips all product units")
    func unitSegmentMappingRoundTripsAllProductUnits() async throws {
        for unit in ProductUnit.allCases {
            let index = ToNaToCompareScreenFactory.segmentIndex(for: unit)
            let decoded = ToNaToCompareScreenFactory.unit(forSegmentIndex: index)
            #expect(decoded == unit)
        }
    }

    @Test("sort mode segment mapping round-trips all modes")
    func sortModeSegmentMappingRoundTripsAllModes() async throws {
        for mode in ToNaToCompareScreenFactory.SortMode.allCases {
            let index = ToNaToCompareScreenFactory.segmentIndex(for: mode)
            let decoded = ToNaToCompareScreenFactory.sortMode(forSegmentIndex: index)
            #expect(decoded == mode)
        }
    }

    @Test("entry updates preserve existing display order when auto sort is disabled")
    func entryUpdatesPreserveExistingDisplayOrderWhenAutoSortIsDisabled() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let fourthID = UUID()

        let currentDisplay = [
            ProductEntry(
                id: thirdID,
                name: "Third",
                priceText: "9.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "6.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "4.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let latestEntries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "7.25",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "4.10",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: thirdID,
                name: "Third",
                priceText: "8.90",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: fourthID,
                name: "Fourth",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let merged = ToNaToCompareScreenFactory.entriesPreservingDisplayOrder(
            latestEntries: latestEntries,
            currentDisplay: currentDisplay
        )

        #expect(merged.map(\.id) == [thirdID, firstID, secondID, fourthID])
        #expect(merged.first(where: { $0.id == firstID })?.priceText == "7.25")
    }

    @Test("sorting by price per kilogram orders entries ascending and keeps invalid last")
    func sortingByPricePerKilogramOrdersEntriesAscendingAndKeepsInvalidLast() async throws {
        let cheapID = UUID()
        let expensiveID = UUID()
        let invalidID = UUID()
        let entries = [
            ProductEntry(
                id: expensiveID,
                name: "Expensive",
                priceText: "6.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: invalidID,
                name: "Invalid",
                priceText: "abc",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: cheapID,
                name: "Cheap",
                priceText: "4.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let sorted = ToNaToCompareScreenFactory.sortedEntries(
            entries: entries,
            mode: .pricePerKilogram,
            referenceUnit: .kilogram
        )

        #expect(sorted.map(\.id) == [cheapID, expensiveID, invalidID])
    }

    @Test("sorting by raw price orders numerically and keeps invalid last")
    func sortingByRawPriceOrdersNumericallyAndKeepsInvalidLast() async throws {
        let lowID = UUID()
        let highID = UUID()
        let invalidID = UUID()
        let entries = [
            ProductEntry(
                id: highID,
                name: "High",
                priceText: "5.20",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: invalidID,
                name: "Invalid",
                priceText: "",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: lowID,
                name: "Low",
                priceText: "3.10",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let sorted = ToNaToCompareScreenFactory.sortedEntries(
            entries: entries,
            mode: .price,
            referenceUnit: .kilogram
        )
        #expect(sorted.map(\.id) == [lowID, highID, invalidID])
    }

    @Test("sorting by quantity orders numerically and keeps invalid last")
    func sortingByQuantityOrdersNumericallyAndKeepsInvalidLast() async throws {
        let smallID = UUID()
        let largeID = UUID()
        let invalidID = UUID()
        let entries = [
            ProductEntry(
                id: largeID,
                name: "Large",
                priceText: "1",
                quantityText: "900",
                unit: .gram
            ),
            ProductEntry(
                id: invalidID,
                name: "Invalid",
                priceText: "1",
                quantityText: "n/a",
                unit: .gram
            ),
            ProductEntry(
                id: smallID,
                name: "Small",
                priceText: "1",
                quantityText: "250",
                unit: .gram
            ),
        ]

        let sorted = ToNaToCompareScreenFactory.sortedEntries(
            entries: entries,
            mode: .quantity,
            referenceUnit: .kilogram
        )
        #expect(sorted.map(\.id) == [smallID, largeID, invalidID])
    }

    @MainActor
    @Test("unit change keeps numeric quantity text while updating unit")
    func unitChangeKeepsNumericQuantityTextWhileUpdatingUnit() async throws {
        let targetID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: targetID, name: "Target", priceText: "4.50", quantityText: "500", unit: .gram)
        ])

        model.updateUnit(.kilogram, entryID: targetID)

        #expect(model.entries.first?.unit == .kilogram)
        #expect(model.entries.first?.quantityText == "500")
    }

    @MainActor
    @Test("unit change keeps non-numeric quantity text while updating unit")
    func unitChangeKeepsNonNumericQuantityTextWhileUpdatingUnit() async throws {
        let targetID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: targetID, name: "Target", priceText: "4.50", quantityText: "abc", unit: .gram)
        ])

        model.updateUnit(.ounce, entryID: targetID)

        #expect(model.entries.first?.unit == .ounce)
        #expect(model.entries.first?.quantityText == "abc")
    }

    @MainActor
    @Test("unit change preserves numeric quantity text across multiple switches")
    func unitChangePreservesNumericQuantityTextAcrossMultipleSwitches() async throws {
        let targetID = UUID()
        let model = ToNaToCompareModel(entries: [
            ProductEntry(id: targetID, name: "Target", priceText: "4.50", quantityText: "1", unit: .kilogram)
        ])

        model.updateUnit(.pound, entryID: targetID)
        model.updateUnit(.gram, entryID: targetID)

        #expect(model.entries.first?.unit == .gram)
        #expect(model.entries.first?.quantityText == "1")
    }

    @Test("cheapest selection chooses lowest normalized price per kilogram")
    func cheapestSelectionChoosesLowestNormalizedPricePerKilogram() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        let entries = [
            ProductEntry(
                id: firstID,
                name: "Entry A",
                priceText: "5.00",
                quantityText: "500",
                unit: .gram
            ),
            ProductEntry(
                id: secondID,
                name: "Entry B",
                priceText: "3.00",
                quantityText: "1",
                unit: .pound
            ),
            ProductEntry(
                id: thirdID,
                name: "Entry C",
                priceText: "4.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let selection = try #require(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .kilogram
            )
        )
        #expect(selection.entryID == thirdID)
        #expect(selection.referenceUnit == .kilogram)
        #expect(abs(selection.pricePerReferenceUnit - 4.0) < 0.0001)
        #expect(abs(selection.pricePerKilogram - 4.0) < 0.0001)
    }

    @Test("cheapest selection ignores invalid entries")
    func cheapestSelectionIgnoresInvalidEntries() async throws {
        let validID = UUID()
        let entries = [
            ProductEntry(
                id: UUID(),
                name: "Invalid Price",
                priceText: "abc",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: UUID(),
                name: "Invalid Quantity",
                priceText: "2.00",
                quantityText: "0",
                unit: .kilogram
            ),
            ProductEntry(
                id: validID,
                name: "Valid",
                priceText: "4.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let selection = try #require(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .kilogram
            )
        )
        #expect(selection.entryID == validID)
        #expect(abs(selection.pricePerKilogram - 4.0) < 0.0001)
    }

    @Test("cheapest selection breaks ties by row order")
    func cheapestSelectionBreaksTiesByRowOrder() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let entries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let selection = try #require(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .kilogram
            )
        )
        #expect(selection.entryID == firstID)
    }

    @Test("cheapest selection returns nil when every entry is invalid")
    func cheapestSelectionReturnsNilWhenEveryEntryIsInvalid() async throws {
        let entries = [
            ProductEntry(
                id: UUID(),
                name: "Invalid Price",
                priceText: "abc",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: UUID(),
                name: "Invalid Quantity",
                priceText: "5.00",
                quantityText: "0",
                unit: .kilogram
            ),
        ]

        #expect(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .kilogram
            ) == nil
        )
    }

    @Test("cheapest selection treats near-equal values inside tie tolerance as a tie")
    func cheapestSelectionTreatsNearEqualValuesInsideTieToleranceAsATie() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let entries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "2.00000004",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let selection = try #require(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .kilogram
            )
        )
        #expect(selection.entryID == firstID)
    }

    @Test("sorting by price per kilogram keeps original order for near ties")
    func sortingByPricePerKilogramKeepsOriginalOrderForNearTies() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let entries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "3.00000006",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "3.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let sorted = ToNaToCompareScreenFactory.sortedEntries(
            entries: entries,
            mode: .pricePerKilogram,
            referenceUnit: .kilogram
        )
        #expect(sorted.map(\.id) == [firstID, secondID])
    }

    @Test("sorting by price per kilogram uses selected reference unit values")
    func sortingByPricePerKilogramUsesSelectedReferenceUnitValues() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let entries = [
            ProductEntry(
                id: firstID,
                name: "First",
                priceText: "1.0000002",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: secondID,
                name: "Second",
                priceText: "1.0",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let sortedByKilogram = ToNaToCompareScreenFactory.sortedEntries(
            entries: entries,
            mode: .pricePerKilogram,
            referenceUnit: .kilogram
        )
        let sortedByGram = ToNaToCompareScreenFactory.sortedEntries(
            entries: entries,
            mode: .pricePerKilogram,
            referenceUnit: .gram
        )

        #expect(sortedByKilogram.map(\.id) == [secondID, firstID])
        #expect(sortedByGram.map(\.id) == [firstID, secondID])
    }

    @Test("cheapest selection exposes value in selected reference unit")
    func cheapestSelectionExposesValueInSelectedReferenceUnit() async throws {
        let entries = [
            ProductEntry(
                name: "Cheapest",
                priceText: "4.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                name: "Other",
                priceText: "8.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let kilogramSelection = try #require(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .kilogram
            )
        )
        let poundSelection = try #require(
            ToNaToCompareScreenFactory.cheapestSelection(
                entries: entries,
                referenceUnit: .pound
            )
        )

        #expect(kilogramSelection.referenceUnit == .kilogram)
        #expect(abs(kilogramSelection.pricePerReferenceUnit - 4.0) < 0.0001)
        #expect(poundSelection.referenceUnit == .pound)
        #expect(abs(poundSelection.pricePerReferenceUnit - 1.81436948) < 0.0001)
        #expect(abs(poundSelection.pricePerKilogram - 4.0) < 0.0001)
    }

    @Test("cheapest footer text reports unavailable when no valid entries")
    func cheapestFooterTextReportsUnavailableWhenNoValidEntries() async throws {
        let entries = [
            ProductEntry(
                name: "Invalid",
                priceText: "",
                quantityText: "",
                unit: .gram
            )
        ]

        let text = ToNaToCompareScreenFactory.cheapestFooterText(
            entries: entries,
            currency: .usd,
            referenceUnit: .kilogram
        )
        #expect(text == "Cheapest: unavailable")
    }

    @Test("row highlight style marks cheapest entry")
    func rowHighlightStyleMarksCheapestEntry() async throws {
        let cheapestID = UUID()
        let entries = [
            ProductEntry(
                id: cheapestID,
                name: "Cheapest",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: UUID(),
                name: "Other",
                priceText: "5.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let style = ToNaToCompareScreenFactory.rowHighlightStyle(
            entryID: cheapestID,
            entries: entries,
            referenceUnit: .kilogram
        )
        #expect(style == .cheapest)
    }

    @Test("row highlight style keeps non-cheapest entries neutral")
    func rowHighlightStyleKeepsNonCheapestEntriesNeutral() async throws {
        let cheapestID = UUID()
        let nonCheapestID = UUID()
        let entries = [
            ProductEntry(
                id: cheapestID,
                name: "Cheapest",
                priceText: "2.00",
                quantityText: "1",
                unit: .kilogram
            ),
            ProductEntry(
                id: nonCheapestID,
                name: "Other",
                priceText: "5.00",
                quantityText: "1",
                unit: .kilogram
            ),
        ]

        let style = ToNaToCompareScreenFactory.rowHighlightStyle(
            entryID: nonCheapestID,
            entries: entries,
            referenceUnit: .kilogram
        )
        #expect(style == .normal)
    }

    @Test("row highlight style is neutral when no valid cheapest entry exists")
    func rowHighlightStyleIsNeutralWhenNoValidCheapestEntryExists() async throws {
        let entryID = UUID()
        let entries = [
            ProductEntry(
                id: entryID,
                name: "Invalid",
                priceText: "",
                quantityText: "",
                unit: .gram
            )
        ]

        let style = ToNaToCompareScreenFactory.rowHighlightStyle(
            entryID: entryID,
            entries: entries,
            referenceUnit: .kilogram
        )
        #expect(style == .normal)
    }
}
