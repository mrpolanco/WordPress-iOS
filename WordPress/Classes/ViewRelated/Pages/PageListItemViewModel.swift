import Foundation

final class PageListItemViewModel {
    let page: Page
    let title: NSAttributedString
    let badgeIcon: UIImage?
    let badges: String
    let imageURL: URL?
    let accessibilityIdentifier: String?

    init(page: Page) {
        self.page = page
        self.title = makeContentAttributedString(for: page)
        self.badgeIcon = makeBadgeIcon(for: page)
        self.badges = makeBadgesString(for: page)
        self.imageURL = page.featuredImageURL
        self.accessibilityIdentifier = page.slugForDisplay()
    }
}

private func makeContentAttributedString(for page: Page) -> NSAttributedString {
    let page = page.hasRevision() ? page.revision : page
    let title = page?.titleForDisplay() ?? ""
    return NSAttributedString(string: title, attributes: [
        .font: WPStyleGuide.fontForTextStyle(.callout, fontWeight: .semibold),
        .foregroundColor: UIColor.text
    ])
}

private func makeBadgeIcon(for page: Page) -> UIImage? {
    if page.isSiteHomepage {
        return UIImage(named: "home")
    }
    if page.isSitePostsPage {
        return UIImage(named: "posts")
    }
    return nil
}

private func makeBadgesString(for page: Page) -> String {
    var badges: [String] = []
    if page.isSiteHomepage {
        badges.append(Strings.badgeHomepage)
    } else if page.isSitePostsPage {
        badges.append(Strings.badgePosts)
    }
    if let displayDate = page.displayDate() {
        badges.append(displayDate.capitalized)
    }
    if page.hasPrivateState {
        badges.append(Strings.badgePrivatePage)
    }
    if page.hasPendingReviewState {
        badges.append(Strings.badgePendingReview)
    }
    if page.hasLocalChanges() {
        badges.append(Strings.badgeLocalChanges)
    }
    return badges.joined(separator: " · ")
}

private enum Strings {
    static let badgeHomepage = NSLocalizedString("pageList.badgeHomepage", value: "Homepage", comment: "Badge for page cells")
    static let badgePosts = NSLocalizedString("pageList.badgePosts", value: "Posts page", comment: "Badge for page cells")
    static let badgePrivatePage = NSLocalizedString("pageList.badgePrivate", value: "Private", comment: "Badge for page cells")
    static let badgePendingReview = NSLocalizedString("pageList.badgePendingReview", value: "Pending review", comment: "Badge for page cells")
    static let badgeLocalChanges = NSLocalizedString("pageList.badgeLocalChanges", value: "Local changes", comment: "Badge for page cells")
}
