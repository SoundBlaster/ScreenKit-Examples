import Testing
import UIKit

@testable import ToNaTo

@Suite("ToNaTo Root Factory")
struct ToNaToRootFactoryTests {
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
    @Test("root split uses injected compare model and history store")
    func rootSplitUsesInjectedCompareModelAndHistoryStore() async throws {
        let model = ToNaToCompareModel(entries: ToNaToCompareScreenFactory.defaultEntries())
        let historyStore = ToNaToHistoryStore()

        let rootController = ToNaToRootFactory
            .makeRootSplit(model: model, historyStore: historyStore)
            .makeViewController()
        let splitController = try #require(rootController as? UISplitViewController)
        let primaryNavigation = try #require(
            splitController.viewController(for: .primary) as? UINavigationController
        )
        let secondaryNavigation = try #require(
            splitController.viewController(for: .secondary) as? UINavigationController
        )

        #expect(primaryNavigation.title == "ToNaTo")
        #expect(secondaryNavigation.topViewController?.title == "Compare")
    }

    @MainActor
    @Test("root tabs compose the five product destinations")
    func rootTabsComposeTheFiveProductDestinations() async throws {
        let model = ToNaToCompareModel(entries: [])
        let historyStore = ToNaToHistoryStore()

        let rootController = ToNaToRootFactory
            .makeRootTabs(model: model, historyStore: historyStore)
            .makeViewController()
        let tabBarController = try #require(rootController as? UITabBarController)

        #expect(tabBarController.tabs.count == 5)
        #expect(tabBarController.tabs.map(\.title) == [
            "Compare", "About", "Detail", "History", "Onboarding"
        ])
    }

    @MainActor
    @Test("settings destination reads and writes the injected model")
    func settingsDestinationReadsAndWritesTheInjectedModel() async throws {
        let model = ToNaToCompareModel(entries: [])
        model.currency = .eur
        model.referenceUnit = .pound
        model.autoSortEnabled = true

        let viewController = ToNaToSettingsScreenFactory
            .makeSettingsScreen(model: model)
            .makeViewController()
        _ = viewController.view

        let currencyControl = try #require(
            findView(in: viewController.view, accessibilityIdentifier: "settings.currency.segmentedControl")
                as? UISegmentedControl
        )
        let unitControl = try #require(
            findView(in: viewController.view, accessibilityIdentifier: "settings.unit.segmentedControl")
                as? UISegmentedControl
        )
        let autoOrderingSwitch = try #require(
            findView(in: viewController.view, accessibilityIdentifier: "settings.autoOrdering.switch")
                as? UISwitch
        )

        let eurIndex = try #require(ToNaToCurrency.allCases.firstIndex(of: .eur))
        let poundIndex = try #require(ProductUnit.allCases.firstIndex(of: .pound))
        #expect(currencyControl.selectedSegmentIndex == eurIndex)
        #expect(unitControl.selectedSegmentIndex == poundIndex)
        #expect(autoOrderingSwitch.isOn)

        currencyControl.selectedSegmentIndex = try #require(ToNaToCurrency.allCases.firstIndex(of: .gbp))
        currencyControl.sendActions(for: .valueChanged)
        unitControl.selectedSegmentIndex = try #require(ProductUnit.allCases.firstIndex(of: .ounce))
        unitControl.sendActions(for: .valueChanged)
        autoOrderingSwitch.isOn = false
        autoOrderingSwitch.sendActions(for: .valueChanged)

        #expect(model.currency == .gbp)
        #expect(model.referenceUnit == .ounce)
        #expect(model.autoSortEnabled == false)
    }

    @MainActor
    @Test("device optimized root selects split for phone and iPad")
    func deviceOptimizedRootSelectsSplitForPhoneAndIPad() async throws {
        let model = ToNaToCompareModel(entries: [])
        let historyStore = ToNaToHistoryStore()

        let phone = ToNaToRootFactory
            .makeDeviceOptimizedRoot(idiom: .phone, model: model, historyStore: historyStore)
            .makeViewController()
        let pad = ToNaToRootFactory
            .makeDeviceOptimizedRoot(idiom: .pad, model: model, historyStore: historyStore)
            .makeViewController()

        #expect(phone is UISplitViewController)
        #expect(pad is UISplitViewController)
    }

    @MainActor
    @Test("split launch route replaces detail with injected history screen")
    func splitLaunchRouteReplacesDetailWithInjectedHistoryScreen() async throws {
        let model = ToNaToCompareModel(entries: [])
        let historyStore = ToNaToHistoryStore()

        let rootController = ToNaToRootFactory
            .makeRootSplit(model: model, historyStore: historyStore, launchRoute: "History")
            .makeViewController()
        let splitController = try #require(rootController as? UISplitViewController)
        let secondaryNavigation = try #require(
            splitController.viewController(for: .secondary) as? UINavigationController
        )

        #expect(secondaryNavigation.topViewController?.title == "History")
    }
}
