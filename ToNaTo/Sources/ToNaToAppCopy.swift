import Foundation
import SwiftUI
import UIKit

enum ToNaToAppCopy {
    static let title = "ToNaTo"
    static let tagline = "Compare price per unit in seconds."

    static let frameworkLinkageLabel = "ScreenKit + Patchwork linked"

}

enum ToNaToTheme {
    enum Palette {
        static let brand = UIColor(red: 0.18, green: 0.53, blue: 0.34, alpha: 1)
        static let accent = UIColor.systemGreen
        static let accentSoft = UIColor.systemGreen.withAlphaComponent(0.14)
        static let accentBorder = UIColor.systemGreen.withAlphaComponent(0.6)

        static let surface = UIColor.systemBackground
        static let groupedBackground = UIColor.systemGroupedBackground
        static let groupedCardBackground = UIColor.secondarySystemGroupedBackground

        static let textPrimary = UIColor.label
        static let textSecondary = UIColor.secondaryLabel
    }

    enum SwiftUIColor {
        static var brand: Color { Color(uiColor: Palette.brand) }
        static var accent: Color { Color(uiColor: Palette.accent) }
        static var accentSoft: Color { Color(uiColor: Palette.accentSoft) }
        static var textPrimary: Color { Color(uiColor: Palette.textPrimary) }
        static var textSecondary: Color { Color(uiColor: Palette.textSecondary) }
    }

    enum Typography {
        static let aboutTitleSize: CGFloat = 34
        static let detailTitleSize: CGFloat = 24
        static let heroSubtitleSize: CGFloat = 22

        static var appTitle: Font {
            .system(size: aboutTitleSize, weight: .bold, design: .rounded)
        }

        static var sectionTitle: Font {
            .system(size: detailTitleSize, weight: .bold, design: .rounded)
        }

        static var heroEyebrow: Font {
            .system(size: 14, weight: .semibold, design: .rounded)
        }

        static var heroHeadline: Font {
            .system(size: heroSubtitleSize, weight: .bold, design: .rounded)
        }

        static var bodyEmphasis: Font {
            .system(size: 16, weight: .semibold)
        }

        static var bodyRegular: Font {
            .system(size: 13, weight: .regular, design: .rounded)
        }

        static var captionStrong: Font {
            .system(size: 11, weight: .bold, design: .rounded)
        }
    }

    enum UIKitTypography {
        static var compareHeader: UIFont {
            .preferredFont(forTextStyle: .title3)
        }

        static var compareHeaderSubtitle: UIFont {
            .preferredFont(forTextStyle: .subheadline)
        }

        static var compareFooter: UIFont {
            .preferredFont(forTextStyle: .headline)
        }

        static var compareRowName: UIFont {
            .preferredFont(forTextStyle: .headline)
        }

        static var compareFieldLabel: UIFont {
            .preferredFont(forTextStyle: .caption1)
        }
    }
}
