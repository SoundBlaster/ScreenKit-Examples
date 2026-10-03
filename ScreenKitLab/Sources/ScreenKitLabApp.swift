import UIKit

@main
final class ScreenKitLabApp: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "ScreenKit Lab", sessionRole: session.role)
        configuration.delegateClass = ScreenKitLabScene.self
        return configuration
    }
}

final class ScreenKitLabScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
#if SCREENKIT_TELEMETRY
    private var telemetrySession: LabTelemetrySession?
#endif

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let navigation = UINavigationController()
#if SCREENKIT_TELEMETRY
        let telemetrySession = LabTelemetrySession(navigation: navigation)
        self.telemetrySession = telemetrySession
        telemetrySession.showLiveScreen()
#else
        let arguments = ProcessInfo.processInfo.arguments
        let initial: UIViewController
        if arguments.contains("--sections") { initial = SectionedContentProbe.makeScreen() }
        else if arguments.contains("--legacy") { initial = LegacyContentProbe() }
        else if arguments.contains("--macro") { initial = ScreenMacroProbe.makeScreen() }
        else { initial = MixedContentProbe.makeScreen() }
        Self.show(initial, in: navigation)
#endif
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window
#if SCREENKIT_TELEMETRY
        if ProcessInfo.processInfo.arguments.contains("--telemetry-benchmark") {
            telemetrySession.startComparison()
        }
#endif
    }

    private static func show(_ controller: UIViewController, in navigation: UINavigationController) {
        let examples: [(String, () -> UIViewController)] = [
            ("Mixed", { MixedContentProbe.makeScreen() }),
            ("Sections", { SectionedContentProbe.makeScreen() }),
            ("Legacy", { LegacyContentProbe() }),
            ("Macro", { ScreenMacroProbe.makeScreen() }),
        ]
        var actions = examples.map { title, factory in
            UIAction(title: title) { [weak navigation] _ in
                guard let navigation else { return }
                Self.show(factory(), in: navigation)
            }
        }
        actions.append(UIAction(title: "Containers") { [weak navigation] _ in
            let containers = ContainerProbe.makeScreen()
            containers.modalPresentationStyle = .fullScreen
            navigation?.present(containers, animated: true)
        })
        let menu = UIMenu(children: actions)
        let picker = UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"), menu: menu)
        picker.accessibilityLabel = "Examples"
        controller.navigationItem.leftBarButtonItem = picker
        navigation.setViewControllers([controller], animated: false)
        navigation.isToolbarHidden = controller.toolbarItems == nil
    }
}
