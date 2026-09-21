import Observation
import ScreenKit
import UIKit

enum ProbeSection: String, CaseIterable, Sendable {
    case featured = "Featured carousel"
    case catalog = "Catalog grid"
    case saved = "Saved list"
}

@MainActor
private final class ProbeSupplementaryMetadata {
    var revision = 0
}

@MainActor
@Observable
private final class SectionedStore {
    let rows = (0..<14).map(ProbeRow.init)
    var order = ProbeSection.allCases
    var draftIsSaved = false
    var singleColumn = false
    let metadata = ProbeSupplementaryMetadata()

    var sections: [ScreenSection<ProbeSection, ProbeRow>] {
        order.map { section in
            let items = rows.filter { row in
                if row.id < 4 { return section == .featured }
                if row.id == 6, draftIsSaved { return section == .saved }
                return section == (row.id < 10 ? .catalog : .saved)
            }
            return ScreenSection(id: section, items: items)
        }
    }
}

@MainActor
enum SectionedContentProbe {
    static func makeScreen() -> ScreenViewController<ProbeSection, ProbeRow> {
        let store = SectionedStore()
        let header = UICollectionView.SupplementaryRegistration<ProbeSectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { _, _, _ in }
        let footer = UICollectionView.SupplementaryRegistration<ProbeSectionHeader>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { _, _, _ in }
        let headerRenderer = ScreenSupplementaryRenderer<ProbeSection>(
            elementKind: UICollectionView.elementKindSectionHeader,
            make: { collection, indexPath in collection.dequeueConfiguredReusableSupplementary(using: header, for: indexPath) },
            update: { view, section in
                let revision = store.metadata.revision
                view.label.text = section.rawValue + (revision == 0 ? "" : " · \(revision)")
                view.accessibilityIdentifier = "section.\(section)"
            }
        )
        let footerRenderer = ScreenSupplementaryRenderer<ProbeSection>(
            elementKind: UICollectionView.elementKindSectionFooter,
            make: { collection, indexPath in collection.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath) },
            update: { view, section in
                view.label.font = .preferredFont(forTextStyle: .caption1)
                view.label.textColor = .secondaryLabel
                view.label.text = "\(section.rawValue) · metadata \(store.metadata.revision)"
                view.accessibilityIdentifier = "footer.\(section)"
            }
        )
        let controller = Screen(store.sections, renderer: MixedContentProbe.makeRenderers())
            .title { "Sections" }
            .layout { section, environment in
                if section == .saved {
                    var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                    configuration.headerMode = .supplementary
                    configuration.footerMode = .supplementary
                    return .list(using: configuration, layoutEnvironment: environment)
                }
                let width = environment.container.effectiveContentSize.width - 32
                let columns = store.singleColumn ? 1 : 2
                let itemWidth = section == .featured ? width * 0.8 : (width - CGFloat(columns - 1) * 12) / CGFloat(columns)
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .absolute(itemWidth), heightDimension: .estimated(160)
                ))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .absolute(section == .featured ? itemWidth : width), heightDimension: .estimated(160)),
                    repeatingSubitem: item,
                    count: section == .featured ? 1 : columns
                )
                group.interItemSpacing = .fixed(12)
                let layout = NSCollectionLayoutSection(group: group)
                layout.interGroupSpacing = 12
                layout.contentInsets = .init(top: 8, leading: 16, bottom: 20, trailing: 16)
                if section == .featured { layout.orthogonalScrollingBehavior = .groupPaging }
                layout.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                ), NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(32)),
                    elementKind: UICollectionView.elementKindSectionFooter,
                    alignment: .bottom
                )]
                return layout
            }
            .supplementary([headerRenderer, footerRenderer])
            .makeViewController()

        controller.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Headers", primaryAction: UIAction { [weak controller] _ in
                store.metadata.revision += 1
                controller?.refreshSupplementaryContent()
            }),
            UIBarButtonItem(title: "Density", primaryAction: UIAction { [weak controller] _ in
                controller?.view.endEditing(true)
                store.singleColumn.toggle()
                if #available(iOS 27, *), !ProcessInfo.processInfo.arguments.contains("--explicit-updates") { return }
                controller?.invalidateLayout()
            }),
        ]
        controller.toolbarItems = [
            UIBarButtonItem(title: "Move draft", primaryAction: UIAction { [weak controller] _ in
                guard let controller else { return }
                controller.view.endEditing(true)
                store.draftIsSaved.toggle()
                if !store.order.contains(.saved) { store.order.append(.saved) }
                let sections = store.sections
                controller.setSections(sections, animated: true) { [weak controller] in
                    guard let controller else { return }
                    scrollToDraft(in: controller)
                }
            }),
            .flexibleSpace(),
            UIBarButtonItem(title: "Reorder", primaryAction: UIAction { [weak controller] _ in
                store.order.reverse()
                controller?.setSections(store.sections, animated: true)
            }),
            .flexibleSpace(),
            UIBarButtonItem(title: "Changes", menu: UIMenu(children: [
                UIAction(title: "Toggle Saved") { [weak controller] _ in
                    if store.order.contains(.saved) { store.order.removeAll { $0 == .saved } }
                    else { store.order.append(.saved) }
                    controller?.setSections(store.sections, animated: true)
                },
                UIAction(title: "Burst updates") { [weak controller] _ in
                    guard let controller else { return }
                    setStatus("Applying…", on: controller)
                    let original = store.sections
                    controller.setSections(Array(original.reversed()), animated: true)
                    controller.refreshSupplementaryContent()
                    controller.setSections(original.filter { $0.id != .saved }, animated: true)
                    controller.setSections(original, animated: true) { [weak controller] in
                        guard let controller else { return }
                        setStatus("3 applied", on: controller)
                        scrollToDraft(in: controller)
                    }
                },
            ])),
        ]
        return controller
    }

    private static func setStatus(_ text: String, on controller: UIViewController) {
        if #available(iOS 26.0, *) {
            controller.navigationItem.subtitle = text
        } else {
            let label = UILabel()
            label.numberOfLines = 2
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.text = "Sections\n" + text
            label.sizeToFit()
            controller.navigationItem.titleView = label
        }
    }

    private static func scrollToDraft(in controller: ScreenViewController<ProbeSection, ProbeRow>) {
        for (sectionIndex, sectionID) in controller.sectionIDs.enumerated() {
            if let itemIndex = controller.itemIDs(in: sectionID).firstIndex(of: 6) {
                controller.collectionView.scrollToItem(at: IndexPath(item: itemIndex, section: sectionIndex), at: .top, animated: false)
                return
            }
        }
    }
}

final class ProbeSectionHeader: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
}
