import Foundation

enum ProductUnit: String, CaseIterable, Sendable {
    case gram
    case kilogram
    case ounce
    case pound

    var symbol: String {
        switch self {
        case .gram:
            return "g"
        case .kilogram:
            return "kg"
        case .ounce:
            return "oz"
        case .pound:
            return "lb"
        }
    }
}

enum ProductEntryField: String, Sendable {
    case name
    case price
    case quantity
}

enum ProductEntryValidationIssue: String, CaseIterable, Hashable, Sendable {
    case emptyName
    case invalidPrice
    case nonPositivePrice
    case invalidQuantity
    case nonPositiveQuantity

    var field: ProductEntryField {
        switch self {
        case .emptyName:
            return .name
        case .invalidPrice, .nonPositivePrice:
            return .price
        case .invalidQuantity, .nonPositiveQuantity:
            return .quantity
        }
    }

    var message: String {
        switch self {
        case .emptyName:
            return "Name is required"
        case .invalidPrice:
            return "Price must be a valid number"
        case .nonPositivePrice:
            return "Price must be greater than zero"
        case .invalidQuantity:
            return "Quantity must be a valid number"
        case .nonPositiveQuantity:
            return "Quantity must be greater than zero"
        }
    }
}

struct ProductEntryValidation: Equatable, Sendable {
    let issues: [ProductEntryValidationIssue]

    var isValid: Bool {
        issues.isEmpty
    }
}

struct ProductEntry: Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var priceText: String
    var quantityText: String
    var unit: ProductUnit

    init(
        id: UUID = UUID(),
        name: String,
        priceText: String,
        quantityText: String,
        unit: ProductUnit
    ) {
        self.id = id
        self.name = name
        self.priceText = priceText
        self.quantityText = quantityText
        self.unit = unit
    }

    static var emptyDraft: ProductEntry {
        ProductEntry(name: "", priceText: "", quantityText: "", unit: .gram)
    }

    var validation: ProductEntryValidation {
        var issues: [ProductEntryValidationIssue] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyName)
        }

        if let price = parseDecimal(priceText) {
            if price <= 0 {
                issues.append(.nonPositivePrice)
            }
        } else {
            issues.append(.invalidPrice)
        }

        if let quantity = parseDecimal(quantityText) {
            if quantity <= 0 {
                issues.append(.nonPositiveQuantity)
            }
        } else {
            issues.append(.invalidQuantity)
        }

        return ProductEntryValidation(issues: issues)
    }

    private func parseDecimal(_ input: String) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(string: trimmed)
    }
}
