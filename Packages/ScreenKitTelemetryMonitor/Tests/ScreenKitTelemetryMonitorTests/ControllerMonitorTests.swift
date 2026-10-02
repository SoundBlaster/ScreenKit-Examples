#if canImport(UIKit)
import OpenTelemetryProtocolExporterHttp
import ScreenKit
import ScreenKitTelemetryMonitor
import UIKit
import XCTest

@MainActor
final class ControllerMonitorTests: XCTestCase {
    struct Item: Identifiable { let id: Int; var title: String }

    func testVisibleControllerUpdateReachesTheOfficialHTTPExporters() async throws {
        let client = CapturingClient()
        let monitor = ScreenTelemetryMonitor(endpoint: URL(string: "http://127.0.0.1:4318")!, serviceName: "screenkit-ui-test", source: "ui-test", interval: 3600, httpClient: client)
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            cell.contentConfiguration = content
        }
        let renderer = ScreenCellRenderer<Item> { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        let controller = Screen([Item(id: 1, title: "Before")]) { _ in renderer }
            .telemetry(monitor.adapter, name: "visible-catalog").makeViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let settled = expectation(description: "Visible update settled")
        controller.setItems([Item(id: 1, title: "After")], animated: false) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 10)
        let cell = try XCTUnwrap(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual((cell.contentConfiguration as? UIListContentConfiguration)?.text, "After")
        XCTAssertTrue(client.requests.isEmpty)
        await monitor.flush()
        XCTAssertEqual(Set(client.requests.compactMap { $0.url?.path }), ["/v1/traces", "/v1/metrics"])
        XCTAssertEqual(monitor.adapter.invalidEventCount, 0)
        XCTAssertEqual(monitor.adapter.activeSpanCount, 0)
        await monitor.shutdown()
    }
}
#endif
