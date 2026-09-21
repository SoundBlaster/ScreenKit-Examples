import NestedA11yIDs
import Observation
import Patchwork
import ScreenKit
import SwiftUI
import UIKit

extension ToNaToCompareScreenFactory {
    @MainActor
    static func makeCompareScreen(
        model: ToNaToCompareModel = .shared,
        historyStore: ToNaToHistoryStore = .shared
    ) -> ControllerScreen<ScreenViewController<Int, ToNaToCompareItem>> {
        ControllerScreen {
            let session = ToNaToCompareSession(model: model)
            let controller = Screen(session.items()) { session.renderer(for: $0) }
                .title { "Compare" }
                .layout { environment in
                    var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                    configuration.showsSeparators = false
                    configuration.backgroundColor = ToNaToTheme.Palette.groupedBackground
                    return .list(using: configuration, layoutEnvironment: environment)
                }
                .makeViewController()
            session.attach(to: controller)
            let sortControl = UISegmentedControl(items: SortMode.allCases.map(\.title))
            sortControl.accessibilityLabel = "Sort products by"
            sortControl.accessibilityIdentifier = "compare.sort"
            sortControl.selectedSegmentIndex = segmentIndex(for: model.sortMode)
            sortControl.addAction(UIAction { [weak sortControl, weak session] _ in
                guard let index = sortControl?.selectedSegmentIndex, let mode = sortMode(forSegmentIndex: index) else { return }
                model.sortMode = mode
                session?.render()
            }, for: .valueChanged)
            session.sortControl = sortControl
            controller.navigationItem.titleView = sortControl
            controller.navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "Save", primaryAction: UIAction { [weak controller] _ in
                    // EditingChanged has already committed every character, even before debounce fires.
                    historyStore.record(entries: model.entries, currency: model.currency)
                    controller?.view.endEditing(true)
                    controller?.navigationController?.pushViewController(
                        ToNaToHistoryScreenFactory.makeHistoryScreen(historyStore: historyStore).makeViewController(), animated: true)
                }),
                UIBarButtonItem(title: "History", primaryAction: UIAction { [weak controller] _ in
                    controller?.view.endEditing(true)
                    controller?.navigationController?.pushViewController(
                        ToNaToHistoryScreenFactory.makeHistoryScreen(historyStore: historyStore).makeViewController(), animated: true)
                }),
            ]
            return controller
        }
    }
}

/// Owned by the screen's renderer closure; never retained by the shared model.
/// The Observation callback and pending task hold weak references, so dropping a screen cancels work.
@MainActor
final class ToNaToCompareSession {
    let model: ToNaToCompareModel
    weak var controller: ScreenViewController<Int, ToNaToCompareItem>?
    weak var sortControl: UISegmentedControl?
    private var displayEntries: [ProductEntry]
    private var lastSortMode: ToNaToCompareScreenFactory.SortMode
    private var pendingRender: Task<Void, Never>?

    private lazy var entryRenderer: ScreenCellRenderer<ToNaToCompareItem> = Patchwork.uiView(
        make: { [model] in ToNaToEntryView(model: model) },
        update: { view, item in view.update(item) }
    )
    private lazy var heroRenderer: ScreenCellRenderer<ToNaToCompareItem> = Patchwork.swiftUI { item in
        if case .hero(let summary) = item.content { ToNaToCompareHeroView(summary: summary) }
    }
    private lazy var addRenderer: ScreenCellRenderer<ToNaToCompareItem> = Patchwork.uiView(
        make: { [weak self] in
            let button = UIButton(type: .system)
            button.setTitle("Add product", for: .normal)
            button.accessibilityIdentifier = ToNaToCompareScreenFactory.addProductButtonAccessibilityIdentifier
            button.addAction(UIAction { [weak self] _ in self?.model.addProduct(); self?.render() }, for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            return button
        }, update: { _, _ in }
    )
    private lazy var textRenderer: ScreenCellRenderer<ToNaToCompareItem> = Patchwork.configuration { item, _ in
        var configuration = UIListContentConfiguration.cell()
        switch item.content {
        case .header:
            configuration.text = ToNaToCompareScreenFactory.compareHeaderTitle
            configuration.textProperties.font = ToNaToTheme.UIKitTypography.compareHeader
            configuration.secondaryText = "Edit price and quantity to compare normalized unit costs."
        case .footer(let text): configuration.text = text
        default: break
        }
        configuration.textProperties.color = ToNaToTheme.Palette.textPrimary
        configuration.secondaryTextProperties.color = ToNaToTheme.Palette.textSecondary
        return configuration
    }

    init(model: ToNaToCompareModel) {
        self.model = model
        displayEntries = model.entries
        lastSortMode = model.sortMode
    }

    deinit { pendingRender?.cancel() }

    func attach(to controller: ScreenViewController<Int, ToNaToCompareItem>) {
        self.controller = controller
        observe()
    }

    func renderer(for item: ToNaToCompareItem) -> ScreenCellRenderer<ToNaToCompareItem> {
        switch item.content {
        case .entry: entryRenderer
        case .hero: heroRenderer
        case .addProduct: addRenderer
        case .header, .footer: textRenderer
        }
    }

    func items() -> [ToNaToCompareItem] {
        if model.autoSortEnabled || model.sortMode != lastSortMode {
            displayEntries = ToNaToCompareScreenFactory.sortedEntries(entries: model.entries, mode: model.sortMode, referenceUnit: model.referenceUnit)
        } else {
            displayEntries = ToNaToCompareScreenFactory.entriesPreservingDisplayOrder(latestEntries: model.entries, currentDisplay: displayEntries)
        }
        lastSortMode = model.sortMode
        return ToNaToCompareScreenFactory.makeCompareItems(entries: displayEntries, currency: model.currency, referenceUnit: model.referenceUnit)
    }

    func render() {
        pendingRender?.cancel()
        pendingRender = nil
        sortControl?.selectedSegmentIndex = ToNaToCompareScreenFactory.segmentIndex(for: model.sortMode)
        controller?.setItems(items(), animated: false)
    }

    private func observe() {
        withObservationTracking {
            _ = model.entries
            _ = model.sortMode
            _ = model.autoSortEnabled
            _ = model.currency
            _ = model.referenceUnit
        } onChange: { [weak self] in
            // Observation notifies before the write. Re-arm on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observe()
                self.pendingRender?.cancel()
                self.pendingRender = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(ToNaToCompareScreenFactory.computeDebounceInterval)) }
                    catch { return }
                    self?.render()
                }
            }
        }
    }
}

/// Existing UIKit form controls with a stable view lifetime across reconfiguration and moves.
@MainActor
final class ToNaToEntryView: UIView {
    let priceField = UITextField()
    let quantityField = UITextField()
    let unitControl = UISegmentedControl(items: ToNaToCompareScreenFactory.availableUnits.map(\.symbol))
    private let valueLabel = UILabel()
    private let numberLabel = UILabel()
    private let stack = UIStackView()
    private let model: ToNaToCompareModel
    private(set) var entryID: UUID?

    init(model: ToNaToCompareModel) {
        self.model = model
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 12, left: 12, bottom: 12, right: 12)
        stack.layer.cornerRadius = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (field, placeholder) in [(priceField, "Price"), (quantityField, "Weight")] {
            field.placeholder = placeholder
            field.keyboardType = .decimalPad
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            let toolbar = UIToolbar()
            toolbar.items = [.flexibleSpace(), UIBarButtonItem(title: "Done", primaryAction: UIAction { [weak self] _ in self?.endEditing(true) })]
            toolbar.sizeToFit()
            field.inputAccessoryView = toolbar
        }
        priceField.addAction(UIAction { [weak self] _ in self?.edit(.price) }, for: .editingChanged)
        quantityField.addAction(UIAction { [weak self] _ in self?.edit(.quantity) }, for: .editingChanged)
        unitControl.addAction(UIAction { [weak self] _ in
            guard let self, let id = entryID,
                  let unit = ToNaToCompareScreenFactory.unit(forSegmentIndex: unitControl.selectedSegmentIndex) else { return }
            model.updateUnit(unit, entryID: id)
            refreshComputedValue()
        }, for: .valueChanged)
        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.55
        valueLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        numberLabel.font = .preferredFont(forTextStyle: .headline)
        numberLabel.textColor = ToNaToTheme.Palette.textSecondary
        stack.addArrangedSubview(numberLabel)
        let fields = UIStackView(arrangedSubviews: [labeled("Price", priceField), labeled("Weight", quantityField), labeled("Price/Weight", valueLabel)])
        fields.spacing = 12
        fields.distribution = .fillEqually
        stack.addArrangedSubview(fields)
        stack.addArrangedSubview(labeled("Unit", unitControl))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    func update(_ item: ToNaToCompareItem) {
        guard case let .entry(entry, number, cheapest, priceForWeight) = item.content else { return }
        let isSameEntry = entryID == entry.id
        entryID = entry.id
        // Avoid assigning even equal text: UIKit selection and marked text must survive.
        if !isSameEntry || (!priceField.isFirstResponder && priceField.text != entry.priceText) { priceField.text = entry.priceText }
        if !isSameEntry || (!quantityField.isFirstResponder && quantityField.text != entry.quantityText) { quantityField.text = entry.quantityText }
        priceField.accessibilityLabel = "Price for \(entry.name)"
        quantityField.accessibilityLabel = "Weight for \(entry.name)"
        priceField.accessibilityIdentifier = "compare.price.\(entry.id.uuidString)"
        quantityField.accessibilityIdentifier = "compare.quantity.\(entry.id.uuidString)"
        unitControl.accessibilityLabel = "Unit for \(entry.name)"
        unitControl.selectedSegmentIndex = ToNaToCompareScreenFactory.segmentIndex(for: entry.unit)
        numberLabel.text = String(format: "%02d · %@", number, entry.name)
        valueLabel.text = priceForWeight
        valueLabel.accessibilityIdentifier = "compare.priceForWeight.\(entry.id.uuidString)"
        valueLabel.accessibilityLabel = "Price/Weight for \(entry.name)"
        valueLabel.accessibilityValue = priceForWeight
        stack.backgroundColor = cheapest ? ToNaToTheme.Palette.accentSoft : ToNaToTheme.Palette.groupedCardBackground
        stack.layer.borderWidth = cheapest ? 1 : 0
        stack.layer.borderColor = ToNaToTheme.Palette.accentBorder.cgColor
    }

    private func edit(_ field: ProductEntryField) {
        guard let entryID else { return }
        let text = field == .price ? priceField.text : quantityField.text
        model.updateText(text ?? "", entryID: entryID, field: field)
        refreshComputedValue()
    }

    private func refreshComputedValue() {
        guard let entry = model.entries.first(where: { $0.id == entryID }) else { return }
        let value = ToNaToCompareScreenFactory.priceForWeightText(entry: entry, currency: model.currency, referenceUnit: model.referenceUnit)
        valueLabel.text = value
        valueLabel.accessibilityValue = value
    }

    private func labeled(_ text: String, _ control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = text
        label.font = ToNaToTheme.UIKitTypography.compareFieldLabel
        label.textColor = ToNaToTheme.Palette.textSecondary
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }
}

private struct ToNaToCompareHeroView: View {
    let summary: ToNaToCompareScreenFactory.HeroSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.title)
                .font(ToNaToTheme.Typography.heroEyebrow)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                .nestedAccessibilityIdentifier("title")

            Text(summary.subtitle)
                .font(ToNaToTheme.Typography.heroHeadline)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                .nestedAccessibilityIdentifier("subtitle")

            Text(summary.badgeText.uppercased())
                .font(ToNaToTheme.Typography.captionStrong)
                .foregroundStyle(ToNaToTheme.SwiftUIColor.accent.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(ToNaToTheme.SwiftUIColor.accentSoft)
                )
                .nestedAccessibilityIdentifier("badge")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ToNaToTheme.SwiftUIColor.accentSoft.opacity(0.95),
                            ToNaToTheme.SwiftUIColor.brand.opacity(0.12),
                            Color.yellow.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .a11yRoot("compare.hero")
    }
}
