import Foundation
import Testing
@testable import ToNaTo

@MainActor
@Suite("ToNaTo isolated model")
struct ToNaToCompareModelTests {
    @Test("in-memory defaults do not depend on production preferences")
    func defaults() {
        let model = ToNaToCompareModel()
        #expect(model.currency == .usd)
        #expect(model.referenceUnit == .gram)
        #expect(!model.autoSortEnabled)
        #expect(model.entries.count == 2)
    }

    @Test("settings persist only in the injected defaults store")
    func persistedSettings() throws {
        let name = "ToNaToTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = ToNaToCompareModel(defaults: defaults)
        model.currency = .eur
        model.referenceUnit = .pound
        model.autoSortEnabled = true
        let reopened = ToNaToCompareModel(defaults: defaults)
        #expect(reopened.currency == .eur)
        #expect(reopened.referenceUnit == .pound)
        #expect(reopened.autoSortEnabled)
    }

    @Test("editing an obsolete entry ID cannot change a recycled row's product")
    func missingEntry() {
        let model = ToNaToCompareModel()
        let oldID = model.entries.removeFirst().id
        let remaining = model.entries
        model.updateText("999", entryID: oldID, field: .price)
        model.updateUnit(.pound, entryID: oldID)
        #expect(model.entries == remaining)
    }
}
