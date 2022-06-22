import Foundation
import Gridicons
import UIKit
import WebKit
import WordPressShared

protocol WebKitAuthenticatable {
    var authenticator: RequestAuthenticator? { get }
    func authenticatedRequest(for url: URL, on webView: WKWebView, completion: @escaping (URLRequest) -> Void)
}

extension WebKitAuthenticatable {
    func authenticatedRequest(for url: URL, on webView: WKWebView, completion: @escaping (URLRequest) -> Void) {
        guard let authenticator = authenticator else {
            return completion(URLRequest(url: url))
        }

        DispatchQueue.main.async {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            authenticator.request(url: url, cookieJar: cookieStore) { (request) in
                completion(request)
            }
        }
    }
}

class WebKitViewController: UIViewController, WebKitAuthenticatable {
    @objc let webView: WKWebView
    @objc let progressView = WebProgressView()
    @objc let titleView = NavigationTitleView()
    let analyticsSource: String?

    @objc lazy var backButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage.gridicon(.chevronLeft).imageFlippedForRightToLeftLayoutDirection(),
                               style: .plain,
                               target: self,
                               action: #selector(goBack))
        button.title = NSLocalizedString("Back", comment: "Previous web page")
        return button
    }()
    @objc lazy var forwardButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .gridicon(.chevronRight),
                               style: .plain,
                               target: self,
                               action: #selector(goForward))
        button.title = NSLocalizedString("Forward", comment: "Next web page")
        return button
    }()
    @objc lazy var shareButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .gridicon(.shareiOS),
                               style: .plain,
                               target: self,
                               action: #selector(share))
        button.title = NSLocalizedString("Share", comment: "Button label to share a web page")
        return button
    }()
    @objc lazy var safariButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .gridicon(.globe),
                               style: .plain,
                               target: self,
                               action: #selector(openInSafari))
        button.title = NSLocalizedString("Safari", comment: "Button label to open web page in Safari")
        button.accessibilityHint = NSLocalizedString("Opens the web page in Safari", comment: "Accessibility hint to open web page in Safari")
        return button
    }()
    @objc lazy var refreshButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .gridicon(.refresh), style: .plain, target: self, action: #selector(WebKitViewController.refresh))
        button.title = NSLocalizedString("Refresh", comment: "Button label to refres a web page")
        return button
    }()
    @objc lazy var closeButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .gridicon(.cross), style: .plain, target: self, action: #selector(WebKitViewController.close))
        button.title = NSLocalizedString("Dismiss", comment: "Dismiss a view. Verb")
        return button
    }()

    @objc var customOptionsButton: UIBarButtonItem?

    @objc let url: URL?
    @objc let authenticator: RequestAuthenticator?
    @objc let navigationDelegate: WebNavigationDelegate?
    @objc var secureInteraction = false
    @objc var addsWPComReferrer = false
    @objc var customTitle: String?
    private let opensNewInSafari: Bool
    let linkBehavior: LinkBehavior

    private var reachabilityObserver: Any?
    private var tapLocation = CGPoint(x: 0.0, y: 0.0)
    private var widthConstraint: NSLayoutConstraint?
    private var stackViewBottomAnchor: NSLayoutConstraint?
    private var onClose: (() -> Void)?

    private var barButtonTintColor: UIColor {
        .listIcon
    }

    private var navBarTitleColor: UIColor {
        .text
    }


    private struct WebViewErrors {
        static let frameLoadInterrupted = 102
    }

    /// Precautionary variable that's in place to make sure the web view doesn't run into an endless loop of reloads if it encounters an error.
    private var hasAttemptedAuthRecovery = false

    @objc init(configuration: WebViewControllerConfiguration) {
        let config = WKWebViewConfiguration()
        // The default on iPad is true. We want the iPhone to be true as well.
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: config)
        url = configuration.url
        customOptionsButton = configuration.optionsButton
        secureInteraction = configuration.secureInteraction
        addsWPComReferrer = configuration.addsWPComReferrer
        customTitle = configuration.customTitle
        authenticator = configuration.authenticator
        navigationDelegate = configuration.navigationDelegate
        linkBehavior = configuration.linkBehavior
        opensNewInSafari = configuration.opensNewInSafari
        onClose = configuration.onClose
        analyticsSource = configuration.analyticsSource

        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        startObservingWebView()
    }

    fileprivate init(url: URL, parent: WebKitViewController, configuration: WKWebViewConfiguration, source: String? = nil) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.url = url
        customOptionsButton = parent.customOptionsButton
        secureInteraction = parent.secureInteraction
        addsWPComReferrer = parent.addsWPComReferrer
        customTitle = parent.customTitle
        authenticator = parent.authenticator
        navigationDelegate = parent.navigationDelegate
        linkBehavior = parent.linkBehavior
        opensNewInSafari = parent.opensNewInSafari
        analyticsSource = source
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        startObservingWebView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.title))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
    }

    private func startObservingWebView() {
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.title), options: [.new], context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: [.new], context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: [.new], context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.isLoading), options: [], context: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(light: UIColor.muriel(color: .gray, .shade0), dark: .basicBackground)

        let stackView = UIStackView(arrangedSubviews: [
            progressView,
            webView
            ])
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        let edgeConstraints = [
            view.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            view.topAnchor.constraint(equalTo: stackView.topAnchor),
            view.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
        ]
        edgeConstraints.forEach({ $0.priority = UILayoutPriority(rawValue: UILayoutPriority.defaultHigh.rawValue - 1) })

        NSLayoutConstraint.activate(edgeConstraints)

        // we are pinning the top and bottom of the stack view to the safe area to prevent unintentionally hidden content/overlaps (ie cookie acceptance popup) then center the horizontal constraints vertically
        let safeArea = self.view.safeAreaLayoutGuide

        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.topAnchor.constraint(equalTo: safeArea.topAnchor).isActive = true

        // this constraint saved as a varible so it can be deactivated when the toolbar is hidden, to prevent unintended pinning to the safe area
        let stackViewBottom = stackView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        stackViewBottomAnchor = stackViewBottom
        NSLayoutConstraint.activate([stackViewBottom])

        let stackWidthConstraint = stackView.widthAnchor.constraint(equalToConstant: 0)
        stackWidthConstraint.priority = UILayoutPriority.defaultLow
        widthConstraint = stackWidthConstraint
        NSLayoutConstraint.activate([stackWidthConstraint])

        configureNavigation()
        configureToolbar()
        addTapGesture()
        webView.customUserAgent = WPUserAgent.wordPress()
        webView.navigationDelegate = self
        webView.uiDelegate = self

        loadWebViewRequest()

        track(.webKitViewDisplayed)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopWaitingForConnectionRestored()
        ReachabilityUtils.dismissNoInternetConnectionNotice()

        track(.webKitViewDismissed)
    }

    @objc func loadWebViewRequest() {
        if ReachabilityUtils.alertIsShowing() {
            dismiss(animated: false)
        }
        guard let url = url else {
            return
        }

        authenticatedRequest(for: url, on: webView) { [weak self] (request) in
            self?.load(request: request)
        }
    }

    @objc func load(request: URLRequest) {
        var request = request
        if addsWPComReferrer {
            request.setValue(WPComReferrerURL, forHTTPHeaderField: "Referer")
        }

        webView.load(request)
    }

    // MARK: Navigation bar setup

    @objc func configureNavigation() {
        setupNavBarTitleView()
        setupRefreshButton()

        // Modal styling
        // Proceed only if this Modal, and it's the only view in the stack.
        // We're not changing the NavigationBar style, if we're sharing it with someone else!
        guard isModal() else {
            return
        }

        setupCloseButton()
        styleNavBar()
    }

    private func setupRefreshButton() {
        if let customOptionsButton = customOptionsButton {
            navigationItem.rightBarButtonItems = [refreshButton, customOptionsButton]
        } else if !secureInteraction {
            navigationItem.rightBarButtonItem = refreshButton
        }
    }

    private func setupCloseButton() {
        navigationItem.leftBarButtonItem = closeButton
    }

    private func setupNavBarTitleView() {
        titleView.titleLabel.text = NSLocalizedString("Loading...", comment: "Loading. Verb")

        titleView.titleLabel.textColor = navBarTitleColor
        titleView.subtitleLabel.textColor = .neutral(.shade30)

        if let title = customTitle {
            self.title = title
        } else {
            navigationItem.titleView = titleView
        }
    }

    private func styleNavBar() {
        guard let navigationBar = navigationController?.navigationBar else {
            return
        }
        navigationBar.barStyle = .default

        // Remove serif title bar formatting
        navigationBar.standardAppearance.titleTextAttributes = [:]

        navigationBar.shadowImage = UIImage(color: WPStyleGuide.webViewModalNavigationBarShadow())
        navigationBar.setBackgroundImage(UIImage(color: WPStyleGuide.webViewModalNavigationBarBackground()), for: .default)

        fixBarButtonsColorForBoldText(on: navigationBar)
    }

    // MARK: ToolBar setup

    @objc func configureToolbar() {
        navigationController?.isToolbarHidden = secureInteraction

        guard !secureInteraction else {
            // if not a secure interaction/view, no toolbar is displayed, so deactivate constraint pinning stack view to safe area
            stackViewBottomAnchor?.isActive = false
            return
        }

        styleToolBar()
        configureToolbarButtons()
        styleToolBarButtons()
    }

    func configureToolbarButtons() {

        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let items = [
            backButton,
            space,
            forwardButton,
            space,
            shareButton,
            space,
            safariButton
        ]
        setToolbarItems(items, animated: false)
    }

    private func styleToolBar() {
        guard let toolBar = navigationController?.toolbar else {
            return
        }

        let appearance = UIToolbarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(light: .white, dark: .appBarBackground)

        toolBar.standardAppearance = appearance

        if #available(iOS 15.0, *) {
            toolBar.scrollEdgeAppearance = appearance
        }

        fixBarButtonsColorForBoldText(on: toolBar)
    }

    private func styleToolBarButtons() {
        navigationController?.toolbar.items?.forEach(styleToolBarButton)
    }

    /// Sets the width of the web preview
    /// - Parameter width: The width value to set the webView to
    func setWidth(_ width: CGFloat?, viewSize: CGSize? = nil) {
        if let width = width {
            let zoomAdjustedWidth = width * (UIScreen.main.scale / UIScreen.main.nativeScale)

            var horizontalViewBound: CGFloat
            if let viewWidth = viewSize?.width {
                horizontalViewBound = viewWidth
            } else if let superViewWidth = view.superview?.frame.width {
                horizontalViewBound = superViewWidth
            } else {
                horizontalViewBound = zoomAdjustedWidth
            }

            widthConstraint?.constant = min(zoomAdjustedWidth, horizontalViewBound)
            widthConstraint?.priority = UILayoutPriority.defaultHigh
        } else {
            widthConstraint?.priority = UILayoutPriority.defaultLow
        }
    }

    // MARK: Helpers

    private func fixBarButtonsColorForBoldText(on bar: UIView) {
        if UIAccessibility.isBoldTextEnabled {
            bar.tintColor = .listIcon
        }
    }

    private func styleBarButton(_ button: UIBarButtonItem) {
        button.tintColor = barButtonTintColor
    }

    private func styleToolBarButton(_ button: UIBarButtonItem) {
        button.tintColor = .listIcon
    }

    // MARK: Reachability Helpers

    private func reloadWhenConnectionRestored() {
        reachabilityObserver = ReachabilityUtils.observeOnceInternetAvailable { [weak self] in
            self?.loadWebViewRequest()
        }
    }

    private func stopWaitingForConnectionRestored() {
        guard let reachabilityObserver = reachabilityObserver else {
            return
        }

        NotificationCenter.default.removeObserver(reachabilityObserver)
        self.reachabilityObserver = nil
    }

    private func addTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(webViewTapped(_:)))
        tapGesture.delegate = self
        webView.addGestureRecognizer(tapGesture)
    }

    // MARK: User Actions
    @objc func close() {
        dismiss(animated: true, completion: onClose)
    }

    @objc func share() {
        guard let url = webView.url else {
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityViewController.modalPresentationStyle = .popover
        activityViewController.popoverPresentationController?.barButtonItem = shareButton

        activityViewController.completionWithItemsHandler = { (type, completed, _, _) in
            if completed, let type = type?.rawValue {
                WPActivityDefaults.trackActivityType(type)
            }
        }
        present(activityViewController, animated: true)
        track(.webKitViewShareTapped)
    }

    @objc func refresh() {
        webView.reload()
        track(.webKitViewReloadTapped)
    }

    @objc func goBack() {
        webView.goBack()
        track(.webKitViewNavigatedBack)
    }

    @objc func goForward() {
        webView.goForward()
        track(.webKitViewNavigatedForward)
    }

    @objc func openInSafari() {
        guard let url = webView.url else {
            return
        }
        UIApplication.shared.open(url)
        track(.webKitViewOpenInSafariTapped)
    }

    ///location is used to present a document menu in tap location on iOS 13
    @objc func webViewTapped(_ sender: UITapGestureRecognizer) {
      self.tapLocation = sender.location(in: view)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let object = object as? WKWebView,
            object == webView,
            let keyPath = keyPath else {
                return
        }

        switch keyPath {
        case #keyPath(WKWebView.title):
            titleView.titleLabel.text = webView.title
        case #keyPath(WKWebView.url):
            // If the site has no title, use the url.
            if webView.title?.nonEmptyString() == nil {
                titleView.titleLabel.text = webView.url?.host
            }
            titleView.subtitleLabel.text = webView.url?.host
            let haveUrl = webView.url != nil
            shareButton.isEnabled = haveUrl
            safariButton.isEnabled = haveUrl
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = haveUrl }
        case #keyPath(WKWebView.estimatedProgress):
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress == 1
        case #keyPath(WKWebView.isLoading):
            backButton.isEnabled = webView.canGoBack
            forwardButton.isEnabled = webView.canGoForward
        default:
            assertionFailure("Observed change to web view that we are not handling")
        }

        // Set the title for the HUD which shows up on tap+hold w/ accessibile font sizes enabled
        navigationItem.title = "\(titleView.titleLabel.text ?? "")\n\n\(String(describing: titleView.subtitleLabel.text ?? ""))"

        // Accessibility values which emulate those found in Safari
        navigationItem.accessibilityLabel = NSLocalizedString("Title", comment: "Accessibility label for web page preview title")
        navigationItem.titleView?.accessibilityValue = titleView.titleLabel.text
        navigationItem.titleView?.accessibilityTraits = .updatesFrequently
    }

    private func track(_ event: WPAnalyticsEvent) {
        let properties: [AnyHashable: Any] = [
            "source": analyticsSource ?? "unknown"
        ]

        WPAnalytics.track(event, properties: properties)
    }
}

extension WebKitViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        if let delegate = navigationDelegate {
            let policy = delegate.shouldNavigate(request: navigationAction.request)
            if let redirect = policy.redirectRequest {
                load(request: redirect)
            }
            decisionHandler(policy.action)
            return
        }

        // Allow request if it is to `wp-login` for 2fa
        if let url = navigationAction.request.url, authenticator?.isLogin(url: url) == true {
            decisionHandler(.allow)
            return
        }

        // Check for link protocols such as `tel:` and set the correct behavior
        if let url = navigationAction.request.url, let scheme = url.scheme {
            let linkProtocols = ["tel", "sms", "mailto"]
            if linkProtocols.contains(scheme) && UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
        }

        let policy = linkBehavior.handle(navigationAction: navigationAction, for: webView)

        decisionHandler(policy)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame, let authenticator = authenticator, !hasAttemptedAuthRecovery else {
            decisionHandler(.allow)
            return
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        authenticator.decideActionFor(response: navigationResponse.response, cookieJar: cookieStore) { [unowned self] action in
            switch action {
            case .reload:
                decisionHandler(.cancel)

                /// We've cleared the stored cookies so let's try again.
                self.hasAttemptedAuthRecovery = true
                self.loadWebViewRequest()
            case .allow:
                decisionHandler(.allow)
            }
        }
    }
}

extension WebKitViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
            let url = navigationAction.request.url {

            if opensNewInSafari {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                let controller = WebKitViewController(url: url, parent: self, configuration: configuration, source: analyticsSource)
                let navController = UINavigationController(rootViewController: controller)
                present(navController, animated: true)
                return controller.webView
            }
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        dismiss(animated: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DDLogInfo("\(NSStringFromClass(type(of: self))) Error Loading [\(error)]")

        // Don't show Frame Load Interrupted errors
        let code = (error as NSError).code
        if code == WebViewErrors.frameLoadInterrupted {
            return
        }

        if !ReachabilityUtils.isInternetReachable() {
            ReachabilityUtils.showNoInternetConnectionNotice()
            reloadWhenConnectionRestored()
        } else {
            DDLogError("WebView \(webView) didFailProvisionalNavigation: \(error.localizedDescription)")
        }
    }
}

extension WebKitViewController: UIPopoverPresentationControllerDelegate {
     func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
       handleDocumentMenuPresentation(presented: popoverPresentationController)
     }

    private func handleDocumentMenuPresentation(presented: UIPopoverPresentationController) {
          presented.sourceView = webView
          presented.sourceRect = CGRect(origin: tapLocation, size: CGSize(width: 0, height: 0))
      }
}

extension WebKitViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      return true
    }
}
