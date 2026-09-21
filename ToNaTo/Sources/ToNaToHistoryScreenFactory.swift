import Foundation
import NestedA11yIDs
import ScreenKit
import SwiftUI
import UIKit

enum ToNaToHistoryScreenFactory {
    @MainActor
    static func makeHistoryScreen(
        historyStore: ToNaToHistoryStore = .shared
    ) -> ControllerScreen<UIViewController> {
        ControllerScreen<UIViewController> {
            let controller = UIHostingController(
                rootView: ToNaToHistoryListView(historyStore: historyStore)
            )
            controller.title = "History"
            return controller
        }
    }
}

private struct ToNaToHistoryListView: View {
    let historyStore: ToNaToHistoryStore

    var body: some View {
        List {
            if historyStore.snapshots.isEmpty {
                Text("No snapshots yet.")
                    .font(ToNaToTheme.Typography.bodyRegular)
                    .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                    .nestedAccessibilityIdentifier("empty")
            } else {
                ForEach(historyStore.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timestampText(for: snapshot.createdAt))
                            .font(ToNaToTheme.Typography.heroEyebrow)
                            .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                            .nestedAccessibilityIdentifier(
                                "row.\(snapshot.id.uuidString).timestamp")
                        Text(cheapestText(for: snapshot))
                            .font(ToNaToTheme.Typography.bodyRegular)
                            .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                            .nestedAccessibilityIdentifier("row.\(snapshot.id.uuidString).cheapest")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .a11yRoot("history")
    }

    private func timestampText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Snapshot: \(formatter.string(from: date))"
    }

    private func cheapestText(for snapshot: ToNaToSnapshot) -> String {
        guard let cheapest = snapshot.cheapest,
            let entry = snapshot.entries.first(where: { $0.id == cheapest.entryID })
        else {
            return "Cheapest: unavailable"
        }
        return "Cheapest: \(entry.name) (\(snapshot.currency.currencySymbol)\(String(format: "%.2f/kg", cheapest.pricePerKilogram)))"
    }
}
