import Patchwork
import ScreenKit
import UIKit

private struct MacroProbeItem: Identifiable {
    let id: Int
    let title: String
}

@MainActor
enum ScreenMacroProbe {
    static func makeScreen() -> UIViewController {
        let items = [
            MacroProbeItem(id: 1, title: "Rendered by ScreenKit macro"),
            MacroProbeItem(id: 2, title: "Compiled in the consuming app target"),
        ]
        return #screen(items) { item in
            Patchwork.configuration { _, _ in
                var content = UIListContentConfiguration.cell()
                content.text = item.title
                return content
            }
        }
        .title { "External #screen" }
        .makeViewController()
    }
}
