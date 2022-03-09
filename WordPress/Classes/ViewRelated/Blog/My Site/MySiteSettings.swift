import Foundation

/// A helper class for My Site that manages the default section to display
///
final class MySiteSettings {

    private let userDefaults: UserDefaults

    var defaultSection: MySiteViewController.Section {
        let rawValue = userDefaults.integer(forKey: Constants.defaultSectionKey)
        return MySiteViewController.Section(rawValue: rawValue) ?? .siteMenu
    }

    // MARK: - Init

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func setDefaultSection(_ tab: MySiteViewController.Section) {
        userDefaults.set(tab.rawValue, forKey: Constants.defaultSectionKey)
    }

    private enum Constants {
        static let defaultSectionKey = "MySiteDefaultSectionKey"
    }
}
