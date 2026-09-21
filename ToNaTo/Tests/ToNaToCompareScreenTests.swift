import ScreenKit
import Testing
import UIKit
@testable import ToNaTo

@MainActor
@Suite("ToNaTo modular Compare", .serialized)
struct ToNaToCompareScreenTests {
    private func show(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        return window
    }

    private func entry(_ name: String, price: String = "4", quantity: String = "500") -> ProductEntry {
        ProductEntry(name: name, priceText: price, quantityText: quantity, unit: .gram)
    }

    private func descendants<T: UIView>(_ view: UIView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(350)) }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(predicate())
    }


    @Test("updates and sorting preserve the same text field, selection, and first responder")
    func focusSurvivesReconfigurationAndMove() async throws {
        let model = ToNaToCompareModel(entries: [entry("First", price: "12.34"), entry("Second", price: "2")])
        let controller = ToNaToCompareScreenFactory.makeCompareScreen(model: model).makeViewController()
        let window = show(UINavigationController(rootViewController: controller))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle()
        let field = try #require(descendants(controller.view, of: UITextField.self).first { $0.accessibilityLabel == "Price for First" })
        #expect(field.becomeFirstResponder())
        let position = try #require(field.position(from: field.beginningOfDocument, offset: 2))
        field.selectedTextRange = field.textRange(from: position, to: position)
        model.currency = .eur
        model.sortMode = .price
        try await waitUntil { controller.itemIDs[2] == .entry(model.entries[1].id) }
        let current = try #require(descendants(controller.view, of: UITextField.self).first { $0.accessibilityLabel == "Price for First" })
        #expect(current === field)
        #expect(field.isFirstResponder)
        #expect(field.text == "12.34")
        #expect(field.offset(from: field.beginningOfDocument, to: try #require(field.selectedTextRange).start) == 2)
        #expect(controller.itemIDs.filter { if case .entry = $0 { return true }; return false } == [.entry(model.entries[1].id), .entry(model.entries[0].id)])
    }

    @Test("editing commits synchronously and updates the inline calculation")
    func synchronousEditing() async throws {
        let model = ToNaToCompareModel(entries: [entry("First")])
        let view = ToNaToEntryView(model: model)
        view.update(try #require(ToNaToCompareScreenFactory.makeCompareItems(entries: model.entries, currency: .usd, referenceUnit: .gram).first { $0.id == .entry(model.entries[0].id) }))
        view.priceField.text = "7.25"
        view.priceField.sendActions(for: .editingChanged)
        let saved = ToNaToHistoryStore().record(entries: model.entries)
        #expect(saved.entries[0].priceText == "7.25")
        #expect(saved.cheapest?.pricePerKilogram == 14.5)
        let value = descendants(view, of: UILabel.self).first { $0.accessibilityLabel == "Price/Weight for First" }
        #expect(value?.accessibilityValue == ToNaToCompareScreenFactory.priceForWeightText(entry: model.entries[0], currency: .usd, referenceUnit: .gram))
    }

    @Test("manual ordering stays stable and auto ordering reacts to later edits")
    func orderingPolicy() async throws {
        let model = ToNaToCompareModel(entries: [entry("First", price: "8"), entry("Second", price: "2")])
        let controller = ToNaToCompareScreenFactory.makeCompareScreen(model: model).makeViewController()
        controller.loadViewIfNeeded()
        let original = controller.itemIDs
        model.entries[0].priceText = "10"
        try await settle()
        #expect(controller.itemIDs == original)
        model.autoSortEnabled = true
        try await waitUntil { controller.itemIDs[2] == .entry(model.entries[1].id) }
        #expect(controller.itemIDs[2] == .entry(model.entries[1].id))
        model.entries[0].priceText = "1"
        try await waitUntil { controller.itemIDs[2] == .entry(model.entries[0].id) }
        #expect(controller.itemIDs[2] == .entry(model.entries[0].id))
    }

    @Test("settings reformat existing controls without replacing them")
    func liveSettings() async throws {
        let model = ToNaToCompareModel(entries: [entry("First")])
        let controller = ToNaToCompareScreenFactory.makeCompareScreen(model: model).makeViewController()
        let window = show(controller)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle()
        let value = try #require(descendants(controller.view, of: UILabel.self).first { $0.accessibilityLabel == "Price/Weight for First" })
        model.currency = .eur
        model.referenceUnit = .pound
        try await settle()
        #expect(value.accessibilityValue == ToNaToCompareScreenFactory.priceForWeightText(entry: model.entries[0], currency: .eur, referenceUnit: .pound))
    }

    @Test("add product updates the snapshot with a fresh blank draft")
    func addProduct() async throws {
        let model = ToNaToCompareModel(entries: [entry("First")])
        let controller = ToNaToCompareScreenFactory.makeCompareScreen(model: model).makeViewController()
        let window = show(controller)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle()
        let button = try #require(descendants(controller.view, of: UIButton.self).first { $0.accessibilityIdentifier == "compare.addProduct.button" })
        button.sendActions(for: .touchUpInside)
        try await settle()
        #expect(model.entries.count == 2)
        #expect(model.entries[1].priceText.isEmpty)
        #expect(controller.itemIDs.contains(.entry(model.entries[1].id)))
    }

    @Test("pending render does not keep its session or controller alive")
    func releasePendingSession() async throws {
        let model = ToNaToCompareModel()
        var session: ToNaToCompareSession? = ToNaToCompareSession(model: model)
        var controller: ScreenViewController<Int, ToNaToCompareItem>? = {
            let retained = session!
            return Screen(retained.items()) { retained.renderer(for: $0) }.makeViewController()
        }()
        session?.attach(to: controller!)
        controller?.loadViewIfNeeded()
        try await settle()
        weak var weakSession = session
        weak var weakController = controller
        model.entries[0].priceText = "9"
        await Task.yield()
        session = nil
        controller = nil
        try await Task.sleep(for: .milliseconds(30))
        #expect(weakSession == nil)
        #expect(weakController == nil)
        model.entries[0].quantityText = "300"
        try await settle()
        #expect(model.entries[0].priceText == "9")
    }

    @Test("screen factories create independent controllers over a shared draft")
    func freshControllers() {
        let model = ToNaToCompareModel()
        let screen = ToNaToCompareScreenFactory.makeCompareScreen(model: model)
        let first = screen.makeViewController()
        let second = screen.makeViewController()
        #expect(first !== second)
        #expect(first.itemIDs == second.itemIDs)
        #expect(first.navigationItem.leftBarButtonItem == nil)
        #expect(first.navigationItem.rightBarButtonItems?.map(\.title) == ["Save", "History"])
    }
}
