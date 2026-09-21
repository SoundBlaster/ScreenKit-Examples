import ScreenKit
import UIKit
import XCTest

@MainActor
final class ScreenContainerTests: XCTestCase {
    private final class MarkerViewController: UIViewController {}

    private final class WeakReference<Value: AnyObject> {
        weak var value: Value?
    }

    func testFactoryAndErasureCreateFreshControllersWithoutEagerConstruction() {
        var factoryCalls = 0
        let screen = ControllerScreen { () -> MarkerViewController in
            factoryCalls += 1
            return MarkerViewController()
        }
        let erased = AnyScreen(screen)
        XCTAssertEqual(factoryCalls, 0)

        let typed = screen.makeViewController()
        let first = erased.makeViewController()
        let second = erased.makeViewController()
        XCTAssertEqual(factoryCalls, 3)
        XCTAssertTrue(first is MarkerViewController)
        XCTAssertFalse(typed === first)
        XCTAssertFalse(first === second)
    }

    func testNavigationCreatesNativeContainerWithFreshTypedRoot() throws {
        let description = screen(title: "Navigation root").navigation()
        let first = description.makeViewController()
        let second = description.makeViewController()
        let firstRoot = try XCTUnwrap(first.viewControllers.first as? MarkerViewController)
        let secondRoot = try XCTUnwrap(second.viewControllers.first as? MarkerViewController)

        XCTAssertTrue(type(of: first) == UINavigationController.self)
        XCTAssertEqual(first.viewControllers.count, 1)
        XCTAssertEqual(firstRoot.title, "Navigation root")
        XCTAssertTrue(firstRoot.navigationController === first)
        XCTAssertFalse(first === second)
        XCTAssertFalse(firstRoot === secondRoot)
        XCTAssertNil(first.delegate)
    }

    func testNativeTabsKeepExplicitLabelsAndSelectByStableID() throws {
        let description = TabsScreen([
            ScreenTab(id: "home", title: "Home tab", image: UIImage(systemName: "house"), content: AnyScreen(screen(title: "Home screen"))),
            ScreenTab(id: "saved", title: "Saved tab", content: AnyScreen(screen(title: "Saved screen").navigation())),
        ], selectedID: "saved")
        let controller = description.makeViewController()

        XCTAssertTrue(type(of: controller) == UITabBarController.self)
        XCTAssertEqual(controller.tabs.map(\.identifier), ["home", "saved"])
        XCTAssertEqual(controller.tabs.map(\.title), ["Home tab", "Saved tab"])
        XCTAssertEqual(controller.selectedTab?.identifier, "saved")
        XCTAssertNil(controller.delegate)

        let home = try XCTUnwrap(controller.tabs[0].viewController as? MarkerViewController)
        let saved = try XCTUnwrap(controller.tabs[1].viewController as? UINavigationController)
        XCTAssertEqual(home.title, "Home screen")
        XCTAssertEqual(saved.viewControllers.first?.title, "Saved screen")
        home.title = "Changed screen title"
        saved.viewControllers.first?.title = "Changed nested title"
        XCTAssertEqual(controller.tabs.map(\.title), ["Home tab", "Saved tab"])

        let rebuilt = description.makeViewController()
        XCTAssertFalse(rebuilt === controller)
        XCTAssertFalse(rebuilt.tabs[0] === controller.tabs[0])
        XCTAssertFalse(rebuilt.tabs[0].viewController === home)
        XCTAssertEqual(rebuilt.selectedTab?.identifier, "saved")
    }

    func testTabsDefaultToFirstAndAllowEmptyContent() {
        let populated = TabsScreen([
            ScreenTab(id: "first", title: "First", content: AnyScreen(screen(title: "Root")))
        ]).makeViewController()
        XCTAssertEqual(populated.selectedTab?.identifier, "first")

        let empty = TabsScreen([]).makeViewController()
        XCTAssertTrue(empty.tabs.isEmpty)
        XCTAssertNil(empty.selectedTab)
    }

    func testSplitPlacesIndependentNavigationRootsInTwoColumns() throws {
        let description = SplitScreen(
            primary: screen(title: "Primary").navigation(),
            secondary: screen(title: "Secondary").navigation()
        )
        let controller = description.makeViewController()
        let primary = try XCTUnwrap(controller.viewController(for: .primary) as? UINavigationController)
        let secondary = try XCTUnwrap(controller.viewController(for: .secondary) as? UINavigationController)

        XCTAssertTrue(type(of: controller) == UISplitViewController.self)
        XCTAssertEqual(controller.style, .doubleColumn)
        XCTAssertEqual(primary.viewControllers.first?.title, "Primary")
        XCTAssertEqual(secondary.viewControllers.first?.title, "Secondary")
        XCTAssertFalse(primary === secondary)
        XCTAssertNil(controller.delegate)

        let rebuilt = description.makeViewController()
        XCTAssertFalse(rebuilt.viewController(for: .primary) === primary)
        XCTAssertFalse(rebuilt.viewController(for: .secondary) === secondary)
    }

    func testPagesRetainDataSourceAndReturnStableNeighborsAtBoundaries() throws {
        let description = PagesScreen([
            AnyScreen(screen(title: "First")),
            AnyScreen(screen(title: "Middle")),
            AnyScreen(screen(title: "Last")),
        ], initialIndex: 1)
        let controller = description.makeViewController()
        let source = try XCTUnwrap(controller.dataSource)
        let middle = try XCTUnwrap(controller.viewControllers?.first)
        let first = try XCTUnwrap(source.pageViewController(controller, viewControllerBefore: middle))
        let last = try XCTUnwrap(source.pageViewController(controller, viewControllerAfter: middle))

        XCTAssertEqual(controller.transitionStyle, .scroll)
        XCTAssertEqual(controller.navigationOrientation, .horizontal)
        XCTAssertNil(controller.delegate)
        XCTAssertEqual(middle.title, "Middle")
        XCTAssertEqual(first.title, "First")
        XCTAssertEqual(last.title, "Last")
        XCTAssertTrue(source.pageViewController(controller, viewControllerAfter: first) === middle)
        XCTAssertTrue(source.pageViewController(controller, viewControllerBefore: last) === middle)
        XCTAssertNil(source.pageViewController(controller, viewControllerBefore: first))
        XCTAssertNil(source.pageViewController(controller, viewControllerAfter: last))
        XCTAssertNil(source.pageViewController(controller, viewControllerAfter: UIViewController()))

        let rebuilt = description.makeViewController()
        XCTAssertFalse(rebuilt === controller)
        XCTAssertFalse(rebuilt.viewControllers?.first === middle)

        let empty = PagesScreen([]).makeViewController()
        XCTAssertNil(empty.viewControllers?.first)
        XCTAssertNotNil(empty.dataSource)
    }

    func testPagesReleaseRetainedDataSourceAndChildControllers() async {
        let weakContainer = WeakReference<UIPageViewController>()
        let weakOwner = WeakReference<AnyObject>()
        let weakFirst = WeakReference<UIViewController>()
        let weakSecond = WeakReference<UIViewController>()

        autoreleasepool {
            let first = ControllerScreen { () -> UIViewController in
                let controller = UIViewController()
                weakFirst.value = controller
                return controller
            }
            let second = ControllerScreen { () -> UIViewController in
                let controller = UIViewController()
                weakSecond.value = controller
                return controller
            }
            let controller = PagesScreen([AnyScreen(first), AnyScreen(second)]).makeViewController()
            weakContainer.value = controller
            weakOwner.value = controller.dataSource as AnyObject?
            XCTAssertNotNil(weakOwner.value, "The private owner must outlive makeViewController().")
            XCTAssertNotNil(weakFirst.value)
            XCTAssertNotNil(weakSecond.value)
        }

        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                weakContainer.value == nil && weakOwner.value == nil
                    && weakFirst.value == nil && weakSecond.value == nil
            }
        }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [released], timeout: 3)
        XCTAssertEqual(result, .completed, "The pages controller must not form an ownership cycle with its data source or children.")
    }

    private func screen(title: String) -> ControllerScreen<MarkerViewController> {
        ControllerScreen {
            let controller = MarkerViewController()
            controller.title = title
            return controller
        }
    }
}
