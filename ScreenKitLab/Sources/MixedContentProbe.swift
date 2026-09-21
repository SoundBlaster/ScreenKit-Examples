import Observation
import Patchwork
import ScreenKit
import SwiftUI
import UIKit

@MainActor
@Observable
final class ProbeRow: Identifiable {
    enum Kind: Int, CaseIterable { case legacy, configuration, swiftUI, uiView }
    nonisolated let id: Int
    let kind: Kind
    var revision = 0
    var draft = ""
    var expanded = false

    init(id: Int) {
        self.id = id
        kind = Kind(rawValue: id % Kind.allCases.count)!
    }

    var detail: String {
        let value = "Item \(id) · Update \(revision)"
        return expanded ? value + "\nThe same model now has longer content. Its identity and saved draft stay unchanged while the cell resizes." : value
    }
}

@MainActor
@Observable
final class ProbeStore {
    let allRows = (0..<40).map(ProbeRow.init)
    var rows: [ProbeRow]
    var revision = 0
    var grid = false

    init() { rows = allRows }

    func update() {
        revision += 1
        for row in allRows {
            row.revision = revision
            row.expanded.toggle()
        }
    }
}

@MainActor
enum MixedContentProbe {
    static func makeRenderers() -> (ProbeRow) -> ScreenCellRenderer<ProbeRow> {
        let legacy: ScreenCellRenderer<ProbeRow> = Patchwork.legacyCell(ProbeLegacyCell.self) { cell, row in
            cell.label.text = "UIKit cell\n" + row.detail
            cell.accessibilityIdentifier = "row.\(row.id)"
        }
        let configured: ScreenCellRenderer<ProbeRow> = Patchwork.configuration { row, state in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = "Content configuration"
            content.secondaryText = row.detail
            content.image = UIImage(systemName: "square.stack.3d.up")
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.textProperties.color = state.isSelected ? .systemBlue : .label
            return content
        }
        let swiftUI: ScreenCellRenderer<ProbeRow> = Patchwork.swiftUI { row in ProbeSwiftUIRow(row: row) }
        let uiView: ScreenCellRenderer<ProbeRow> = Patchwork.uiView(make: { UILabel() }) { label, row in
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.text = "Existing UIView\n" + row.detail
            label.accessibilityIdentifier = "row.\(row.id)"
        }
        return { row in
            switch row.kind {
            case .legacy: legacy
            case .configuration: configured
            case .swiftUI: swiftUI
            case .uiView: uiView
            }
        }
    }

    static func makeScreen() -> ScreenViewController<Int, ProbeRow> {
        let store = ProbeStore()
        let controller = Screen(store.rows, renderer: makeRenderers())
        .title { "Mixed · \(store.revision)" }
        .layout { environment in
            if store.grid {
                let columns = environment.container.effectiveContentSize.width > 600 ? 3 : 2
                let spacing: CGFloat = 12
                let width = (environment.container.effectiveContentSize.width - 32 - spacing * CGFloat(columns - 1)) / CGFloat(columns)
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(width), heightDimension: .estimated(140)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(140)),
                    repeatingSubitem: item,
                    count: columns
                )
                group.interItemSpacing = .fixed(12)
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
                section.interGroupSpacing = 12
                return section
            }
            return .list(using: .init(appearance: .insetGrouped), layoutEnvironment: environment)
        }
        .makeViewController()

        let explicitUpdates: Bool
        if #available(iOS 26.0, *) {
            explicitUpdates = ProcessInfo.processInfo.arguments.contains("--explicit-updates")
        } else {
            explicitUpdates = true
        }
        controller.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Update", primaryAction: UIAction { [weak controller] _ in
                store.update()
                // Exercise explicit refresh alongside native tracking; unit tests use plain models.
                if explicitUpdates { controller?.refreshContent() }
            }),
            UIBarButtonItem(title: "Layout", primaryAction: UIAction { [weak controller] _ in
                controller?.view.endEditing(true)
                store.grid.toggle()
                if #available(iOS 27, *), !explicitUpdates { return }
                controller?.invalidateLayout()
            }),
        ]
        controller.toolbarItems = [
            UIBarButtonItem(title: "Reverse", primaryAction: UIAction { [weak controller] _ in
                store.rows.reverse()
                controller?.setItems(store.rows, animated: false)
            }),
            .flexibleSpace(),
            UIBarButtonItem(title: "Remove first", primaryAction: UIAction { [weak controller] _ in
                guard !store.rows.isEmpty else { return }
                store.rows.removeFirst()
                controller?.setItems(store.rows, animated: false)
            }),
            .flexibleSpace(),
            UIBarButtonItem(title: "Restore", primaryAction: UIAction { [weak controller] _ in
                store.rows = store.allRows
                controller?.setItems(store.rows, animated: false) { [weak controller] in
                    controller?.collectionView.setContentOffset(.zero, animated: false)
                }
            }),
        ]
        return controller
    }
}

final class ProbeLegacyCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
}

private struct ProbeSwiftUIRow: View {
    @Bindable var row: ProbeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SwiftUI island", systemImage: "square.on.square")
                .font(.headline)
            Text(row.detail)
                .font(.subheadline)
            TextField("A draft that survives reuse", text: $row.draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("draft.\(row.id)")
        }
    }
}
