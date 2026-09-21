import Patchwork
import ScreenKit
import SwiftUI
import UIKit

@MainActor
enum ContainerProbe {
    private struct Message: Identifiable {
        let id: Int = 0
        let title: String
        let detail: String
        let symbol: String
    }

    private final class NavigationTarget {
        weak var controller: UIViewController?
    }

    static func makeScreen() -> UITabBarController {
        TabsScreen([
            ScreenTab(id: "navigation", title: "Navigation", image: UIImage(systemName: "arrow.right.square"),
                      content: AnyScreen(ControllerScreen { makeNavigationRoot() }.navigation())),
            ScreenTab(id: "pages", title: "Pages", image: UIImage(systemName: "rectangle.on.rectangle"),
                      content: AnyScreen(PagesScreen([
                        AnyScreen(message("Page 1", detail: "Swipe left to open the next screen.", symbol: "1.circle")),
                        AnyScreen(message("Page 2", detail: "Swipe right to return. Each page is a Screen value.", symbol: "2.circle")),
                      ]))),
            ScreenTab(id: "split", title: "Split", image: UIImage(systemName: "rectangle.split.2x1"),
                      content: AnyScreen(SplitScreen(
                        primary: message("Primary", detail: "UIKit adapts these columns to the available width.", symbol: "sidebar.left").navigation(),
                        secondary: message("Secondary", detail: "An independent Screen in the detail column.", symbol: "rectangle.rightthird.inset.filled").navigation()
                      ))),
        ]).makeViewController()
    }

    private static func makeNavigationRoot() -> UIViewController {
        let target = NavigationTarget()
        let renderer: ScreenCellRenderer<Message> = Patchwork.swiftUI { row in
            VStack(alignment: .leading, spacing: 20) {
                Label(row.title, systemImage: row.symbol).font(.title2)
                Text(row.detail).foregroundStyle(.secondary)
                Button("Open detail") {
                    target.controller?.navigationController?.pushViewController(
                        message("Detail", detail: "Native push and back navigation. No client UIViewController subclass.", symbol: "checkmark.circle").makeViewController(),
                        animated: true
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("container.openDetail")
            }
            .padding(.vertical, 20)
        }
        let controller = Screen([Message(title: "Screens compose", detail: "Navigation, tabs, pages and split columns share the same screen contract.", symbol: "square.stack")]) { _ in renderer }
            .title { "Navigation" }
            .makeViewController()
        target.controller = controller
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", primaryAction: UIAction { [weak controller] _ in
            controller?.tabBarController?.dismiss(animated: true)
        })
        return controller
    }

    private static func message(_ title: String, detail: String, symbol: String) -> Screen<Int, Message> {
        let renderer: ScreenCellRenderer<Message> = Patchwork.swiftUI { row in
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: row.symbol).font(.system(size: 44)).foregroundStyle(.tint)
                Text(row.title).font(.largeTitle)
                Text(row.detail).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
            .padding(.vertical, 20)
        }
        return Screen([Message(title: title, detail: detail, symbol: symbol)]) { _ in renderer }.title { title }
    }
}
