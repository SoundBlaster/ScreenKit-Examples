import Foundation

extension ToNaToCompareScreenFactory {
    static func segmentIndex(for mode: SortMode) -> Int {
        SortMode.allCases.firstIndex(of: mode) ?? 0
    }

    static func sortMode(forSegmentIndex index: Int) -> SortMode? {
        guard SortMode.allCases.indices.contains(index) else {
            return nil
        }
        return SortMode.allCases[index]
    }

    static func sortedEntries(
        entries: [ProductEntry],
        mode: SortMode,
        referenceUnit: ProductUnit
    ) -> [ProductEntry] {
        let enumerated = entries.enumerated().map { (index: $0.offset, entry: $0.element) }

        let sorted: [(index: Int, entry: ProductEntry)]
        switch mode {
        case .pricePerKilogram:
            sorted = enumerated.sorted { left, right in
                let leftValue = PricePerUnitCalculator.calculate(for: left.entry)
                    .map { pricePerReferenceUnit(from: $0, referenceUnit: referenceUnit) }
                let rightValue = PricePerUnitCalculator.calculate(for: right.entry)
                    .map { pricePerReferenceUnit(from: $0, referenceUnit: referenceUnit) }
                return compareSortableValues(
                    left: leftValue,
                    leftIndex: left.index,
                    right: rightValue,
                    rightIndex: right.index
                )
            }
        case .price:
            sorted = enumerated.sorted { left, right in
                let leftValue = parseQuantity(left.entry.priceText)
                let rightValue = parseQuantity(right.entry.priceText)
                return compareSortableValues(
                    left: leftValue,
                    leftIndex: left.index,
                    right: rightValue,
                    rightIndex: right.index
                )
            }
        case .quantity:
            sorted = enumerated.sorted { left, right in
                let leftValue = parseQuantity(left.entry.quantityText)
                let rightValue = parseQuantity(right.entry.quantityText)
                return compareSortableValues(
                    left: leftValue,
                    leftIndex: left.index,
                    right: rightValue,
                    rightIndex: right.index
                )
            }
        }

        return sorted.map(\.entry)
    }

    static func entriesPreservingDisplayOrder(
        latestEntries: [ProductEntry],
        currentDisplay: [ProductEntry]
    ) -> [ProductEntry] {
        var latestByID: [UUID: ProductEntry] = [:]
        latestByID.reserveCapacity(latestEntries.count)
        for entry in latestEntries {
            latestByID[entry.id] = entry
        }

        var merged: [ProductEntry] = []
        merged.reserveCapacity(latestEntries.count)

        var seen: Set<UUID> = []
        seen.reserveCapacity(latestEntries.count)

        for visibleEntry in currentDisplay {
            guard let latestEntry = latestByID[visibleEntry.id] else {
                continue
            }
            merged.append(latestEntry)
            seen.insert(visibleEntry.id)
        }

        for latestEntry in latestEntries where !seen.contains(latestEntry.id) {
            merged.append(latestEntry)
        }

        return merged
    }

    static func cheapestSelection(
        entries: [ProductEntry],
        referenceUnit: ProductUnit
    ) -> CheapestSelection? {
        var candidates: [
            (
                index: Int,
                entryID: UUID,
                pricePerReferenceUnit: Double,
                pricePerKilogram: Double
            )
        ] = []

        for (index, entry) in entries.enumerated() {
            guard let result = PricePerUnitCalculator.calculate(for: entry) else {
                continue
            }
            candidates.append(
                (
                    index: index,
                    entryID: entry.id,
                    pricePerReferenceUnit: pricePerReferenceUnit(
                        from: result,
                        referenceUnit: referenceUnit
                    ),
                    pricePerKilogram: result.pricePerKilogram
                )
            )
        }

        guard let winner = candidates.min(by: { left, right in
            let delta = left.pricePerReferenceUnit - right.pricePerReferenceUnit
            if abs(delta) <= tieTolerance {
                return left.index < right.index
            }
            return delta < 0
        }) else {
            return nil
        }

        return CheapestSelection(
            entryID: winner.entryID,
            referenceUnit: referenceUnit,
            pricePerReferenceUnit: winner.pricePerReferenceUnit,
            pricePerKilogram: winner.pricePerKilogram
        )
    }

    static func cheapestFooterText(
        entries: [ProductEntry],
        currency: ToNaToCurrency,
        referenceUnit: ProductUnit
    ) -> String {
        guard let selection = cheapestSelection(entries: entries, referenceUnit: referenceUnit),
              let entry = entries.first(where: { $0.id == selection.entryID }) else {
            return "Cheapest: unavailable"
        }

        let pricePerUnit = pricePerReferenceUnit(from: selection, referenceUnit: referenceUnit)
        return "Cheapest: \(entry.name) (\(formattedPricePerUnit(pricePerUnit, currency: currency, unit: referenceUnit)))"
    }

    static func priceForWeightText(
        entry: ProductEntry,
        currency: ToNaToCurrency,
        referenceUnit: ProductUnit
    ) -> String {
        guard let result = PricePerUnitCalculator.calculate(for: entry) else {
            return unavailablePriceForWeightText
        }
        let pricePerUnit = pricePerReferenceUnit(from: result, referenceUnit: referenceUnit)
        return formattedPricePerUnit(pricePerUnit, currency: currency, unit: referenceUnit)
    }

    static func heroSummary(
        entries: [ProductEntry],
        currency: ToNaToCurrency,
        referenceUnit: ProductUnit
    ) -> HeroSummary {
        let badgeText = itemCountLabel(for: comparableEntriesCount(entries: entries))

        guard let selection = cheapestSelection(entries: entries, referenceUnit: referenceUnit),
              let entry = entries.first(where: { $0.id == selection.entryID }) else {
            return HeroSummary(
                title: "Best current value",
                subtitle: "Add valid prices and quantities to see the cheapest option.",
                badgeText: badgeText
            )
        }

        let pricePerUnit = pricePerReferenceUnit(from: selection, referenceUnit: referenceUnit)
        return HeroSummary(
            title: "Best current value",
            subtitle: "\(entry.name) at \(formattedPricePerUnit(pricePerUnit, currency: currency, unit: referenceUnit))",
            badgeText: badgeText
        )
    }

    static func rowHighlightStyle(
        entryID: UUID,
        entries: [ProductEntry],
        referenceUnit: ProductUnit
    ) -> RowHighlightStyle {
        guard let selection = cheapestSelection(entries: entries, referenceUnit: referenceUnit) else {
            return .normal
        }
        return selection.entryID == entryID ? .cheapest : .normal
    }

    static func parseQuantity(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let decimal =
            Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) ??
            Decimal(string: trimmed)
        else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    static func formattedQuantity(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func formattedPricePerKilogram(_ value: Double, currency: ToNaToCurrency) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency.currencySymbol
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        if let rendered = formatter.string(from: NSNumber(value: value)) {
            return rendered
        }

        return String(
            format: "\(currency.currencySymbol)%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    static func formattedPricePerUnit(_ value: Double, currency: ToNaToCurrency, unit: ProductUnit) -> String {
        let priceString = formattedPrice(value, currency: currency)
        return "\(priceString)/\(unit.symbol)"
    }

    static func formattedPrice(_ value: Double, currency: ToNaToCurrency) -> String {
        if value > 0 && value < 0.01 {
            let fractionalValue = value * 100
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            if let rendered = formatter.string(from: NSNumber(value: fractionalValue)) {
                return "\(rendered)\(currency.fractionalCurrencySymbol)"
            }
            let rendered = String(
                format: "%.2f",
                locale: Locale(identifier: "en_US_POSIX"),
                fractionalValue
            )
            return "\(rendered)\(currency.fractionalCurrencySymbol)"
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency.currencySymbol
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        if let rendered = formatter.string(from: NSNumber(value: value)) {
            return rendered
        }

        return String(
            format: "\(currency.currencySymbol)%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func pricePerReferenceUnit(
        from result: PricePerUnitResult,
        referenceUnit: ProductUnit
    ) -> Double {
        result.pricePerGram * referenceUnit.gramsPerUnit
    }

    private static func pricePerReferenceUnit(
        from selection: CheapestSelection,
        referenceUnit: ProductUnit
    ) -> Double {
        if selection.referenceUnit == referenceUnit {
            return selection.pricePerReferenceUnit
        }

        let pricePerGram = selection.pricePerKilogram / 1_000.0
        return pricePerGram * referenceUnit.gramsPerUnit
    }

    private static func compareSortableValues(
        left: Double?,
        leftIndex: Int,
        right: Double?,
        rightIndex: Int
    ) -> Bool {
        switch (left, right) {
        case let (leftValue?, rightValue?):
            if abs(leftValue - rightValue) <= tieTolerance {
                return leftIndex < rightIndex
            }
            return leftValue < rightValue
        case (nil, nil):
            return leftIndex < rightIndex
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        }
    }

    private static func itemCountLabel(for count: Int) -> String {
        if count == 1 {
            return "1 item compared"
        }
        return "\(count) items compared"
    }

    private static func comparableEntriesCount(entries: [ProductEntry]) -> Int {
        entries.reduce(into: 0) { count, entry in
            if PricePerUnitCalculator.calculate(for: entry) != nil {
                count += 1
            }
        }
    }
}
