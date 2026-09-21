import Patchwork
import ScreenKit
import SwiftUI
import UIKit

/// A conventional UIKit owner using Patchwork registrations directly.
/// ScreenKit supplies the renderer value type; this controller owns every update.
@MainActor
final class LegacyContentProbe: UIViewController {
    private struct Row: Identifiable {
        let id: Int
        var revision = 0

        var detail: String { "Item \(id) · Update \(revision)" }
    }

    private var rows = (0..<8).map { Row(id: $0) }
    private var rowsByID: [Int: Row] = [:]
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!

    // Registrations are created once and retained independently of snapshots.
    private let legacyRenderer: ScreenCellRenderer<Row>
    private let swiftUIRenderer: ScreenCellRenderer<Row>

    init() {
        legacyRenderer = Patchwork.legacyCell(LegacyOwnerCell.self) { cell, row in
            cell.label.text = "UIKit cell\n" + row.detail
            cell.accessibilityLabel = "UIKit cell, " + row.detail
            cell.accessibilityIdentifier = "legacy.row.\(row.id)"
        }
        swiftUIRenderer = Patchwork.swiftUI { (row: Row) in
            VStack(alignment: .leading, spacing: 6) {
                Label("SwiftUI island", systemImage: "square.on.square")
                    .font(.headline)
                Text(row.detail)
                    .font(.subheadline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("legacy.row.\(row.id)")
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init()")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Legacy"
        view.backgroundColor = .systemBackground

        let layout = UICollectionViewCompositionalLayout.list(using: .init(appearance: .insetGrouped))
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.accessibilityIdentifier = "legacy.collection"
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            [weak self] collection, indexPath, id in
            guard let self, let row = rowsByID[id] else { return nil }
            let renderer = id.isMultiple(of: 2) ? legacyRenderer : swiftUIRenderer
            return renderer.cell(in: collection, at: indexPath, item: row)
        }

        let update = UIBarButtonItem(title: "Update", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            for index in rows.indices {
                rows[index].revision += 1
            }
            applyRows()
        })
        update.accessibilityIdentifier = "legacy.update"

        let reverse = UIBarButtonItem(title: "Reverse", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            rows.reverse()
            applyRows()
        })
        reverse.accessibilityIdentifier = "legacy.reverse"
        navigationItem.rightBarButtonItems = [update, reverse]

        applyRows()
    }

    private func applyRows() {
        let previousIDs = Set(dataSource.snapshot().itemIdentifiers)
        rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(rows.map(\.id))
        snapshot.reconfigureItems(rows.map(\.id).filter { previousIDs.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

@MainActor
private final class LegacyOwnerCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(frame:)")
    }
}
