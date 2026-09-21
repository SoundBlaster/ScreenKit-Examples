import NestedA11yIDs
import ScreenKit
import SwiftUI
import UIKit

enum ToNaToOnboardingFactory {
    struct PageModel {
        let systemImage: String
        let eyebrow: String
        let title: String
        let description: String
    }

    static let onboardingPages: [PageModel] = [
        PageModel(
            systemImage: "list.bullet.rectangle",
            eyebrow: "COMPARE",
            title: "See the Best Deal",
            description: "Add products and instantly compare price per unit."
        ),
        PageModel(
            systemImage: "star.fill",
            eyebrow: "CHEAPEST",
            title: "Never Overpay",
            description: "The best value highlights automatically as you shop."
        ),
        PageModel(
            systemImage: "clock.arrow.circlepath",
            eyebrow: "HISTORY",
            title: "Track Over Time",
            description: "Save comparisons and revisit past price checks."
        ),
    ]

    @MainActor
    static func makeOnboardingScreen() -> PagesScreen {
        let pages = onboardingPages.enumerated().map { index, page in
            AnyScreen(
                ControllerScreen {
                    UIHostingController(
                        rootView: OnboardingPageView(page: page, index: index)
                    )
                }
            )
        }
        return PagesScreen(pages)
    }
}

private struct OnboardingPageView: View {
    let page: ToNaToOnboardingFactory.PageModel
    let index: Int

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.systemImage)
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(ToNaToTheme.SwiftUIColor.brand)
                .nestedAccessibilityIdentifier("page.\(index).icon")

            VStack(spacing: 12) {
                Text(page.eyebrow)
                    .font(ToNaToTheme.Typography.heroEyebrow)
                    .foregroundStyle(ToNaToTheme.SwiftUIColor.accent)
                    .nestedAccessibilityIdentifier("page.\(index).eyebrow")

                Text(page.title)
                    .font(ToNaToTheme.Typography.appTitle)
                    .foregroundStyle(ToNaToTheme.SwiftUIColor.textPrimary)
                    .nestedAccessibilityIdentifier("page.\(index).title")

                Text(page.description)
                    .font(ToNaToTheme.Typography.bodyEmphasis)
                    .foregroundStyle(ToNaToTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .nestedAccessibilityIdentifier("page.\(index).description")
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: ToNaToTheme.Palette.surface))
        .a11yRoot("onboarding")
    }
}
