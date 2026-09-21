import Testing
import UIKit

@testable import ToNaTo

@Suite("ToNaTo Accessibility")
struct ToNaToAccessibilityTests {
    @MainActor
    private func makeEntry(id: UUID, name: String) -> ProductEntry {
        ProductEntry(id: id, name: name, priceText: "4.99", quantityText: "500", unit: .gram)
    }

    @MainActor
    private func attachToWindow(_ viewController: UIViewController) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.loadViewIfNeeded()
        window.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        return window
    }

    @MainActor
    private func findView(in view: UIView, accessibilityIdentifier: String) -> UIView? {
        if view.accessibilityIdentifier == accessibilityIdentifier {
            return view
        }
        for subview in view.subviews {
            if let match = findView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }

    @MainActor
    @Test("compare screen exposes typed input and calculated value identifiers")
    func compareScreenExposesTypedInputAndCalculatedValueIdentifiers() async throws {
        let entryID = UUID()
        let model = ToNaToCompareModel(entries: [makeEntry(id: entryID, name: "Tomatoes")])
        let viewController = ToNaToCompareScreenFactory
            .makeCompareScreen(model: model, historyStore: ToNaToHistoryStore())
            .makeViewController()
        let window = attachToWindow(viewController)
        defer { window.isHidden = true }

        #expect(findView(in: viewController.view, accessibilityIdentifier: "compare.price.\(entryID.uuidString)") is UITextField)
        #expect(findView(in: viewController.view, accessibilityIdentifier: "compare.quantity.\(entryID.uuidString)") is UITextField)
        #expect(findView(in: viewController.view, accessibilityIdentifier: "compare.priceForWeight.\(entryID.uuidString)") is UILabel)
    }

    @MainActor
    @Test("root tabs expose native destination labels")
    func rootTabsExposeNativeDestinationLabels() async throws {
        let rootController = ToNaToRootFactory
            .makeRootTabs(model: ToNaToCompareModel(entries: []), historyStore: ToNaToHistoryStore())
            .makeViewController()
        let tabBarController = try #require(rootController as? UITabBarController)
        let window = attachToWindow(tabBarController)
        defer { window.isHidden = true }

        #expect(tabBarController.tabs.map(\.title) == [
            "Compare", "About", "Detail", "History", "Onboarding"
        ])
    }
}
