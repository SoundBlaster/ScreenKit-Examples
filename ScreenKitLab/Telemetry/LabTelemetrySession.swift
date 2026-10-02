import ScreenKit
import ScreenKitTelemetryMonitor
import UIKit

/// Scene-owned SDK lifetime. The normal release-pinned Lab does not compile this file.
@MainActor
final class LabTelemetrySession {
    private weak var navigation: UINavigationController?
    private var monitor: ScreenTelemetryMonitor?
    private var comparing = false
    private var enabled = !ProcessInfo.processInfo.arguments.contains("--telemetry-off")
    private let endpoint: URL
    private let endpointIsValid: Bool

    init(navigation: UINavigationController) {
        self.navigation = navigation
        let value = ProcessInfo.processInfo.environment["SCREENKIT_OTLP_ENDPOINT"] ?? "http://127.0.0.1:4318"
        let candidate = URL(string: value)
        endpointIsValid = candidate?.host != nil && ["http", "https"].contains(candidate?.scheme ?? "")
            && candidate?.user == nil && candidate?.password == nil
            && candidate?.query == nil && candidate?.fragment == nil
        endpoint = candidate ?? URL(string: "http://127.0.0.1:4318")!
    }

    func showLiveScreen() {
        guard let navigation else { return }
        guard endpointIsValid else {
            showMessage("Invalid endpoint", detail: "Set SCREENKIT_OTLP_ENDPOINT to an HTTP(S) Collector base URL without credentials, a query, or a fragment.")
            return
        }
        if enabled {
            monitor = ScreenTelemetryMonitor(endpoint: endpoint, serviceName: "screenkit-lab", source: "app")
        }
        let controller = MixedContentProbe.makeScreen(forceExplicitUpdates: true) { [monitor] screen in
            guard let monitor else { return screen }
            return screen.telemetry(monitor.adapter, name: "Lab.Mixed")
        }
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: enabled ? "OTLP on" : "OTLP off", primaryAction: UIAction { [weak self] _ in
                guard let self, !comparing else { return }
                comparing = true
                Task { @MainActor [self] in
                    await self.stopMonitor()
                    self.enabled.toggle()
                    self.comparing = false
                    self.showLiveScreen()
                }
            }
        )
        // Keep the original toolbar usable on narrow phones. Reuse its existing
        // Update/Layout actions in one explicit menu alongside the comparison.
        var actions = controller.navigationItem.rightBarButtonItems?.compactMap(\.primaryAction) ?? []
        actions.append(UIAction(title: "Compare") { [weak self] _ in self?.startComparison() })
        controller.navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Actions", menu: UIMenu(children: actions))]
        navigation.isToolbarHidden = false
        navigation.setViewControllers([controller], animated: false)
    }

    func startComparison() {
        guard !comparing, endpointIsValid, let navigation else { return }
        comparing = true
        Task { @MainActor [self] in
            await stopMonitor()
            let report = await LabBenchmark.run(in: navigation, endpoint: endpoint)
            do {
                let file = try FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                ).appendingPathComponent("telemetry-benchmark.json")
                try report.data().write(to: file, options: .atomic)
                showReport(report, file: file)
            } catch {
                showMessage("Report failed", detail: error.localizedDescription)
            }
            comparing = false
        }
    }

    private func stopMonitor() async {
        // Detach the emitting screen before stopping its SDK. New screens get a new
        // instance identifier, so restarting never resets the same cumulative series.
        navigation?.setViewControllers([], animated: false)
        await monitor?.shutdown()
        monitor = nil
    }

    private func showReport(_ report: LabBenchmark.Report, file: URL) {
        let rows: [SummaryRow] = [
            .init(id: "complete", title: report.errors.isEmpty ? "Benchmark complete" : "Benchmark invalid",
                  detail: "4 balanced pairs · 20 samples per mode per pair · 1,000 mixed rows"),
            .init(id: "disabled", title: "Telemetry disabled", detail: milliseconds(report.disabledMedian) + " median"),
            .init(id: "otlp", title: "OTLP enabled", detail: milliseconds(report.otlpMedian) + " median"),
            .init(id: "scope", title: "Update completion time",
                  detail: "Includes diff application and layout. Does not measure displayed frames or GPU work. Simulator results are diagnostic, not a performance budget."),
            .init(id: "delivery", title: "Verify delivery separately",
                  detail: "The JSON report contains every sample and exporter instance. Use the workbench verification script to confirm backend receipt."),
        ] + report.errors.enumerated().map { .init(id: "error.\($0.offset)", title: "Validation failed", detail: $0.element) }
        let controller = summaryScreen(title: "Comparison", rows: rows)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Share report", primaryAction: UIAction { [weak controller] _ in
                let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                share.popoverPresentationController?.barButtonItem = controller?.navigationItem.rightBarButtonItem
                controller?.present(share, animated: true)
            }
        )
        navigation?.setViewControllers([controller], animated: false)
    }

    private func milliseconds(_ value: Double) -> String { String(format: "%.3f ms", value * 1_000) }

    private func showMessage(_ title: String, detail: String) {
        navigation?.setViewControllers([summaryScreen(title: title, rows: [.init(id: "message", title: title, detail: detail)])], animated: false)
    }

    private struct SummaryRow: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    private func summaryScreen(title: String, rows: [SummaryRow]) -> UIViewController {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, SummaryRow> { cell, _, row in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = row.title
            content.secondaryText = row.detail
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = content
        }
        let renderer = ScreenCellRenderer<SummaryRow> { collection, index, row in
            collection.dequeueConfiguredReusableCell(using: registration, for: index, item: row)
        }
        let controller = Screen(rows) { _ in renderer }.title { title }.makeViewController()
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Lab", primaryAction: UIAction { [weak self] _ in self?.showLiveScreen() }
        )
        navigation?.isToolbarHidden = true
        return controller
    }
}
