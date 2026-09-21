import ScreenKit
import SwiftUI
import UIKit

@main
@MainActor
struct ToNaToApp: App {
    private let model: ToNaToCompareModel
    private let historyStore: ToNaToHistoryStore
    private let launchRoute: String?

    init() {
        let arguments = CommandLine.arguments
        let isUITesting = arguments.contains("--uitesting")

        if isUITesting {
            // Keep UI tests deterministic and prevent them from writing user settings.
            model = ToNaToCompareModel(
                entries: ToNaToCompareScreenFactory.defaultEntries(),
                defaults: nil
            )
            historyStore = ToNaToHistoryStore()
        } else {
            model = .shared
            historyStore = .shared
        }

        launchRoute = arguments.contains("--compare") ? "Compare" : nil
    }

    var body: some Scene {
        WindowGroup {
            ToNaToRootViewControllerHost(
                model: model,
                historyStore: historyStore,
                launchRoute: launchRoute
            )
            .ignoresSafeArea()
        }
    }
}

private struct ToNaToRootViewControllerHost: UIViewControllerRepresentable {
    let model: ToNaToCompareModel
    let historyStore: ToNaToHistoryStore
    let launchRoute: String?

    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        ToNaToRootFactory.makeDeviceOptimizedRoot(
            model: model,
            historyStore: historyStore,
            launchRoute: launchRoute
        )
        .makeViewController()
    }

    @MainActor
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
