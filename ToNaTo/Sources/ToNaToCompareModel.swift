import Foundation
import Observation

enum ToNaToCurrency: String, CaseIterable, Sendable {
    case usd
    case eur
    case gbp

    var title: String {
        switch self {
        case .usd:
            return "USD"
        case .eur:
            return "EUR"
        case .gbp:
            return "GBP"
        }
    }

    var currencySymbol: String {
        switch self {
        case .usd:
            return "$"
        case .eur:
            return "€"
        case .gbp:
            return "£"
        }
    }

    var fractionalCurrencySymbol: String {
        switch self {
        case .usd:
            return "¢"
        case .eur:
            return "c"
        case .gbp:
            return "p"
        }
    }
}

/// App-owned draft and settings. Text edits are committed synchronously; only rendering is debounced.
@MainActor
@Observable
final class ToNaToCompareModel {
    static let shared = ToNaToCompareModel(defaults: .standard)

    var entries: [ProductEntry]
    var sortMode = ToNaToCompareScreenFactory.SortMode.pricePerKilogram
    var autoSortEnabled: Bool {
        didSet { defaults?.set(autoSortEnabled, forKey: "tonato.autoSortEnabled") }
    }
    var currency: ToNaToCurrency {
        didSet { defaults?.set(currency.rawValue, forKey: "tonato.defaultCurrency") }
    }
    var referenceUnit: ProductUnit {
        didSet { defaults?.set(referenceUnit.rawValue, forKey: "tonato.defaultUnit") }
    }
    @ObservationIgnored private let defaults: UserDefaults?

    init(entries: [ProductEntry] = ToNaToCompareScreenFactory.defaultEntries(), defaults: UserDefaults? = nil) {
        self.entries = entries
        self.defaults = defaults
        autoSortEnabled = defaults?.bool(forKey: "tonato.autoSortEnabled") ?? false
        currency = defaults?.string(forKey: "tonato.defaultCurrency").flatMap(ToNaToCurrency.init) ?? .usd
        referenceUnit = defaults?.string(forKey: "tonato.defaultUnit").flatMap(ProductUnit.init) ?? .gram
    }

    func updateText(_ text: String, entryID: UUID, field: ProductEntryField) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        switch field {
        case .price: entries[index].priceText = text
        case .quantity: entries[index].quantityText = text
        case .name: entries[index].name = text
        }
    }

    func updateUnit(_ unit: ProductUnit, entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        // Changing the selected unit intentionally preserves the user's numeric text.
        entries[index].unit = unit
    }

    func addProduct() {
        entries.append(ProductEntry(name: "Product \(entries.count + 1)", priceText: "", quantityText: "", unit: .gram))
    }
}
