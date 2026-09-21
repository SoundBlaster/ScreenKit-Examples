import NestedA11yIDs
import Observation
import ScreenKit
import SwiftUI
import UIKit

enum ToNaToRootFactory {
    private static let menuItems: [ToNaToMenuItem] = [
        ToNaToMenuItem(title: "Compare", systemImage: "list.bullet.rectangle"),
        ToNaToMenuItem(title: "Settings", systemImage: "gearshape"),
        ToNaToMenuItem(title: "About", systemImage: "info.circle"),
        ToNaToMenuItem(title: "Detail", systemImage: "doc.text.magnifyingglass"),
        ToNaToMenuItem(title: "History", systemImage: "clock.arrow.circlepath"),
        ToNaToMenuItem(title: "Onboarding", systemImage: "hand.wave"),
    ]

    @MainActor
    static func makeDeviceOptimizedRoot(
        idiom: UIUserInterfaceIdiom? = nil,
        model: ToNaToCompareModel = .shared,
        historyStore: ToNaToHistoryStore = .shared,
        launchRoute: String? = nil
    ) -> AnyScreen {
        _ = idiom ?? UIDevice.current.userInterfaceIdiom
        if launchRoute == "Compare" {
            return makeScreenForMenuItem(
                "Compare",
                model: model,
                historyStore: historyStore
            )
        }
        return makeRootSplit(
            model: model,
            historyStore: historyStore,
            launchRoute: launchRoute
        )
    }

    @MainActor
    static func makeRootSplit(
        model: ToNaToCompareModel = .shared,
        historyStore: ToNaToHistoryStore = .shared,
        launchRoute: String? = nil
    ) -> AnyScreen {
        return AnyScreen(
            ControllerScreen<UISplitViewController> {
                let coordinator = ToNaToRootCoordinator(
                    model: model,
                    historyStore: historyStore
                )
                let menu = ControllerScreen<UIViewController> {
                    let host = UIHostingController(
                        rootView: ToNaToMenuView(
                            items: menuItems,
                            onSelect: { @MainActor title in
                                coordinator.select(title)
                            }
                        )
                    )
                    host.title = "ToNaTo"
                    return host
                }
                let primary = NavigationScreen(menu)
                let secondary = makeScreenForMenuItem(
                    "Compare",
                    model: model,
                    historyStore: historyStore
                )
                let split = SplitScreen(primary: primary, secondary: secondary)
                let controller = split.makeViewController()
                if UIDevice.current.userInterfaceIdiom == .pad {
                    controller.preferredDisplayMode = .oneBesideSecondary
                    controller.preferredSplitBehavior = .tile
                }
                coordinator.attach(controller)
                if let launchRoute {
                    coordinator.select(launchRoute)
                }
                return controller
            }
        )
    }

    @MainActor
    static func makeRootTabs(
        model: ToNaToCompareModel = .shared,
        historyStore: ToNaToHistoryStore = .shared,
        launchRoute: String? = nil
    ) -> AnyScreen {
        let tabs = [
            ScreenTab(
                id: "compare",
                title: "Compare",
                image: UIImage(systemName: "list.bullet.rectangle"),
                content: makeScreenForMenuItem(
                    "Compare",
                    model: model,
                    historyStore: historyStore
                )
            ),
            ScreenTab(
                id: "about",
                title: "About",
                image: UIImage(systemName: "info.circle"),
                content: makeScreenForMenuItem(
                    "About",
                    model: model,
                    historyStore: historyStore
                )
            ),
            ScreenTab(
                id: "detail",
                title: "Detail",
                image: UIImage(systemName: "doc.text.magnifyingglass"),
                content: makeScreenForMenuItem(
                    "Detail",
                    model: model,
                    historyStore: historyStore
                )
            ),
            ScreenTab(
                id: "history",
                title: "History",
                image: UIImage(systemName: "clock.arrow.circlepath"),
                content: makeScreenForMenuItem(
                    "History",
                    model: model,
                    historyStore: historyStore
                )
            ),
            ScreenTab(
                id: "onboarding",
                title: "Onboarding",
                image: UIImage(systemName: "hand.wave"),
                content: makeScreenForMenuItem(
                    "Onboarding",
                    model: model,
                    historyStore: historyStore
                )
            ),
        ]

        let selectedID: String?
        switch launchRoute {
        case "About": selectedID = "about"
        case "Detail": selectedID = "detail"
        case "History": selectedID = "history"
        case "Onboarding": selectedID = "onboarding"
        default: selectedID = "compare"
        }

        return AnyScreen(TabsScreen(tabs, selectedID: selectedID))
    }

    @MainActor
    fileprivate static func makeScreenForMenuItem(
        _ title: String,
        model: ToNaToCompareModel,
        historyStore: ToNaToHistoryStore
    ) -> AnyScreen {
        switch title {
        case "Compare":
            return makeNavigationRoute(title: title) {
                ToNaToCompareScreenFactory
                    .makeCompareScreen(model: model, historyStore: historyStore)
                    .makeViewController()
            }

        case "Settings":
            return makeNavigationRoute(title: title) {
                ToNaToSettingsScreenFactory
                    .makeSettingsScreen(model: model)
                    .makeViewController()
            }

        case "About":
            return makeNavigationRoute(title: title) {
                UIHostingController(rootView: ToNaToAboutView())
            }

        case "Detail":
            return makeNavigationRoute(title: title) {
                ToNaToDetailScreenFactory
                    .makeDetailScreen(model: model)
                    .makeViewController()
            }

        case "History":
            return makeNavigationRoute(title: title) {
                ToNaToHistoryScreenFactory
                    .makeHistoryScreen(historyStore: historyStore)
                    .makeViewController()
            }

        case "Onboarding":
            return makeNavigationRoute(title: title) {
                ToNaToOnboardingFactory.makeOnboardingScreen().makeViewController()
            }

        default:
            return makeNavigationRoute(title: title) {
                UIHostingController(rootView: Text("Unknown: \(title)"))
            }
        }
    }

    @MainActor
    private static func makeNavigationRoute(
        title: String,
        content: @escaping @MainActor () -> UIViewController
    ) -> AnyScreen {
        let root = ControllerScreen<UIViewController> {
            let controller = content()
            controller.title = title
            return controller
        }
        return AnyScreen(NavigationScreen(root))
    }
}

private struct ToNaToMenuItem: Identifiable, Hashable, Sendable {
    let title: String
    let systemImage: String

    var id: String { title }
}

private struct ToNaToMenuView: View {
    let items: [ToNaToMenuItem]
    let onSelect: @MainActor (String) -> Void

    var body: some View {
        List(items) { item in
            Button {
                onSelect(item.title)
            } label: {
                Label(item.title, systemImage: item.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("menu.\(item.id)")
        }
        .listStyle(.insetGrouped)
        .a11yRoot("menu")
    }
}

@MainActor
private final class ToNaToRootCoordinator {
    private let model: ToNaToCompareModel
    private let historyStore: ToNaToHistoryStore
    private weak var splitController: UISplitViewController?

    init(model: ToNaToCompareModel, historyStore: ToNaToHistoryStore) {
        self.model = model
        self.historyStore = historyStore
    }

    func attach(_ splitController: UISplitViewController) {
        self.splitController = splitController
    }

    func select(_ title: String) {
        guard let splitController else { return }
        let screen = ToNaToRootFactory.makeScreenForMenuItem(
            title,
            model: model,
            historyStore: historyStore
        )
        splitController.showDetailViewController(screen.makeViewController(), sender: self)
    }
}

enum ToNaToSettingsScreenFactory {
    fileprivate static let availableCurrencies = ToNaToCurrency.allCases
    fileprivate static let availableUnits = ProductUnit.allCases

    @MainActor
    static func makeSettingsScreen(
        model: ToNaToCompareModel = .shared
    ) -> ControllerScreen<UIViewController> {
        ControllerScreen<UIViewController> {
            let controller = UIViewController()
            controller.view = ToNaToSettingsView(model: model)
            controller.title = "Settings"
            return controller
        }
    }
}

@MainActor
private final class ToNaToSettingsView: UIScrollView {
    private let model: ToNaToCompareModel
    private let currencyControl: UISegmentedControl
    private let unitControl: UISegmentedControl
    private let autoOrderingSwitch: UISwitch

    init(model: ToNaToCompareModel) {
        self.model = model
        currencyControl = UISegmentedControl(items: ToNaToSettingsScreenFactory.availableCurrencies.map(\.title))
        unitControl = UISegmentedControl(items: ToNaToSettingsScreenFactory.availableUnits.map(\.symbol))
        autoOrderingSwitch = UISwitch()
        super.init(frame: .zero)
        buildView()
        syncControls()
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use ToNaToSettingsView(model:)")
    }

    private func buildView() {
        backgroundColor = ToNaToTheme.Palette.groupedBackground
        alwaysBounceVertical = true

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        currencyControl.accessibilityIdentifier = "settings.currency.segmentedControl"
        currencyControl.addAction(
            UIAction { [weak self] _ in
                guard let self,
                    let value = Self.currency(for: self.currencyControl.selectedSegmentIndex)
                else { return }
                self.model.currency = value
            },
            for: .valueChanged
        )

        unitControl.accessibilityIdentifier = "settings.unit.segmentedControl"
        unitControl.addAction(
            UIAction { [weak self] _ in
                guard let self,
                    let value = Self.unit(for: self.unitControl.selectedSegmentIndex)
                else { return }
                self.model.referenceUnit = value
            },
            for: .valueChanged
        )

        autoOrderingSwitch.accessibilityIdentifier = "settings.autoOrdering.switch"
        autoOrderingSwitch.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.model.autoSortEnabled = self.autoOrderingSwitch.isOn
            },
            for: .valueChanged
        )

        stack.addArrangedSubview(
            Self.makeSettingCard(
                labelText: "Default Currency",
                labelIdentifier: "settings.currency.label",
                control: currencyControl
            )
        )
        stack.addArrangedSubview(
            Self.makeSettingCard(
                labelText: "Default Unit",
                labelIdentifier: "settings.unit.label",
                control: unitControl
            )
        )
        stack.addArrangedSubview(
            Self.makeSwitchCard(
                labelText: "Auto ordering",
                labelIdentifier: "settings.autoOrdering.label",
                toggle: autoOrderingSwitch
            )
        )

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),

            stack.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    private func syncControls() {
        currencyControl.selectedSegmentIndex = Self.index(for: model.currency)
        unitControl.selectedSegmentIndex = Self.index(for: model.referenceUnit)
        autoOrderingSwitch.isOn = model.autoSortEnabled
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.currency
            _ = model.referenceUnit
            _ = model.autoSortEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                syncControls()
                observeModel()
            }
        }
    }

    private static func makeSettingCard(
        labelText: String,
        labelIdentifier: String,
        control: UIView
    ) -> UIView {
        let label = UILabel()
        label.text = labelText
        label.font = .preferredFont(forTextStyle: .headline)
        label.accessibilityIdentifier = labelIdentifier

        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.backgroundColor = ToNaToTheme.Palette.groupedCardBackground
        stack.layer.cornerRadius = 12
        stack.layer.masksToBounds = true
        return stack
    }

    private static func makeSwitchCard(
        labelText: String,
        labelIdentifier: String,
        toggle: UISwitch
    ) -> UIView {
        let label = UILabel()
        label.text = labelText
        label.font = .preferredFont(forTextStyle: .headline)
        label.accessibilityIdentifier = labelIdentifier

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [row])
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.backgroundColor = ToNaToTheme.Palette.groupedCardBackground
        stack.layer.cornerRadius = 12
        stack.layer.masksToBounds = true
        return stack
    }

    private static func index(for currency: ToNaToCurrency) -> Int {
        ToNaToSettingsScreenFactory.availableCurrencies.firstIndex(of: currency) ?? 0
    }

    private static func currency(for index: Int) -> ToNaToCurrency? {
        guard ToNaToSettingsScreenFactory.availableCurrencies.indices.contains(index) else {
            return nil
        }
        return ToNaToSettingsScreenFactory.availableCurrencies[index]
    }

    private static func index(for unit: ProductUnit) -> Int {
        ToNaToSettingsScreenFactory.availableUnits.firstIndex(of: unit) ?? 0
    }

    private static func unit(for index: Int) -> ProductUnit? {
        guard ToNaToSettingsScreenFactory.availableUnits.indices.contains(index) else { return nil }
        return ToNaToSettingsScreenFactory.availableUnits[index]
    }
}

private struct ToNaToAboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(ToNaToAppCopy.title)
                .font(ToNaToTheme.Typography.appTitle)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                .nestedAccessibilityIdentifier("title")
            Text("Quick grocery unit-price checks.")
                .font(ToNaToTheme.Typography.bodyEmphasis)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                .nestedAccessibilityIdentifier("tagline")
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: ToNaToTheme.Palette.surface))
        .a11yRoot("about")
    }
}
