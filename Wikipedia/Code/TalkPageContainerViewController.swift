
import UIKit

@objc(WMFTalkPageContainerViewController)
class TalkPageContainerViewController: ViewController, HintPresenting {
    
    private let talkPageTitle: String
    private let siteURL: URL
    private let type: TalkPageType
    private let dataStore: MWKDataStore
    private let controller: TalkPageController
    private let talkPageSemanticContentAttribute: UISemanticContentAttribute
    private var talkPage: TalkPage? {
        didSet {
            introTopic = talkPage?.topics?.first(where: { ($0 as? TalkPageTopic)?.isIntro == true}) as? TalkPageTopic
        }
    }
    private var introTopic: TalkPageTopic?
    private var topicListViewController: TalkPageTopicListViewController?
    private var replyListViewController: TalkPageReplyListViewController?
    private var headerView: TalkPageHeaderView?
    private var addButton: UIBarButtonItem?
    
    @objc static let WMFReplyPublishedNotificationName = "WMFReplyPublishedNotificationName"
    @objc static let WMFTopicPublishedNotificationName = "WMFTopicPublishedNotificationName"
    
    var hintController: HintController?
    
    lazy private(set) var fakeProgressController: FakeProgressController = {
        let progressController = FakeProgressController(progress: navigationBar, delegate: navigationBar)
        progressController.delay = 0.0
        return progressController
    }()
    
    private var repliesAreDisabled = true {
        didSet {
            replyListViewController?.repliesAreDisabled = repliesAreDisabled
        }
    }
    
    required init(title: String, siteURL: URL, type: TalkPageType, dataStore: MWKDataStore, controller: TalkPageController? = nil) {
        self.talkPageTitle = title
        self.siteURL = siteURL
        self.type = type
        self.dataStore = dataStore
        
        if let controller = controller {
            self.controller = controller
        } else {
            self.controller = TalkPageController(moc: dataStore.viewContext, title: talkPageTitle, siteURL: siteURL, type: type)
        }
        
        assert(title.contains(":"), "Title must already be prefixed with namespace.")
        
        let language = siteURL.wmf_language
        talkPageSemanticContentAttribute = MWLanguageInfo.semanticContentAttribute(forWMFLanguage: language)
        
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        fetch()
        setupNavigationBar()
    }
    
    override func apply(theme: Theme) {
        super.apply(theme: theme)
        view.backgroundColor = theme.colors.paperBackground
    }
}

//MARK: Private

private extension TalkPageContainerViewController {
    
    func fetch() {
        fakeProgressController.start()
        
        controller.fetchTalkPage { [weak self] (result) in
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                
                switch result {
                case .success(let fetchResult):
                    if !fetchResult.isInitialLocalResult {
                        self.fakeProgressController.stop()
                        self.addButton?.isEnabled = true
                        self.repliesAreDisabled = false
                    }
                    
                    self.talkPage = try? self.dataStore.viewContext.existingObject(with: fetchResult.objectID) as? TalkPage
                    if let talkPage = self.talkPage {
                        if let topics = talkPage.topics, topics.count > 0 {
                            self.hideEmptyView()
                        } else {
                            self.wmf_showEmptyView(of: .emptyTalkPage, theme: self.theme, frame: self.view.bounds)
                        }
                        self.setupTopicListViewControllerIfNeeded(with: talkPage)
                        if let headerView = self.headerView,
                            let introTopic = self.introTopic {
                            self.configure(header: headerView, introTopic: introTopic)
                            self.updateScrollViewInsets()
                        }
                    } else {
                        self.showEmptyView()
                    }
                case .failure(let error):
                    self.showEmptyView()
                    self.fakeProgressController.stop()
                    self.showNoInternetConnectionAlertOrOtherWarning(from: error)
                }
            }
        }
    }
    
    func setupTopicListViewControllerIfNeeded(with talkPage: TalkPage) {
        if topicListViewController == nil {
            topicListViewController = TalkPageTopicListViewController(dataStore: dataStore, talkPageTitle: talkPageTitle, talkPage: talkPage, siteURL: siteURL, type: type, talkPageSemanticContentAttribute: talkPageSemanticContentAttribute)
            topicListViewController?.apply(theme: theme)
            let belowView: UIView = wmf_emptyView ?? navigationBar
            wmf_add(childController: topicListViewController, andConstrainToEdgesOfContainerView: view, belowSubview: belowView)
            topicListViewController?.delegate = self
        }
    }
    
    @objc func tappedAdd(_ sender: UIBarButtonItem) {
        let topicNewVC = TalkPageTopicNewViewController.init()
        topicNewVC.delegate = self
        topicNewVC.apply(theme: theme)
        navigationController?.pushViewController(topicNewVC, animated: true)
    }
    
    func setupAddBarButton() {
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(tappedAdd(_:)))
        addButton.tintColor = theme.colors.link
        navigationItem.rightBarButtonItem = addButton
        navigationBar.updateNavigationItems()
        addButton.isEnabled = false
        self.addButton = addButton
        
    }
    
    func setupNavigationBar() {
        
        setupAddBarButton()
        
        if let headerView = TalkPageHeaderView.wmf_viewFromClassNib() {
            self.headerView = headerView
            configure(header: headerView, introTopic: nil)
            headerView.delegate = self
            navigationBar.isBarHidingEnabled = false
            navigationBar.isUnderBarViewHidingEnabled = true
            useNavigationBarVisibleHeightForScrollViewInsets = true
            navigationBar.addUnderNavigationBarView(headerView)
            navigationBar.underBarViewPercentHiddenForShowingTitle = 0.6
            navigationBar.title = controller.displayTitle
            updateScrollViewInsets()
        }
    }
    
    func configure(header: TalkPageHeaderView, introTopic: TalkPageTopic?) {
        
        var headerText: String
        switch type {
        case .user:
            headerText = WMFLocalizedString("talk-page-title-user-talk", value: "User Talk", comment: "This title label is displayed at the top of a talk page topic list, if the talk page type is a user talk page.").localizedUppercase
        case .article:
            headerText = WMFLocalizedString("talk-page-title-article-talk", value: "article Talk", comment: "This title label is displayed at the top of a talk page topic list, if the talk page type is an article talk page.").localizedUppercase
        }
        
        let languageTextFormat = WMFLocalizedString("talk-page-info-active-conversations", value: "Active conversations on %1$@ Wikipedia", comment: "This information label is displayed at the top of a talk page topic list. %1$@ is replaced by the language wiki they are using - for example, 'Active conversations on English Wikipedia'.")
        
        let genericInfoText = WMFLocalizedString("talk-page-info-active-conversations-generic", value: "Active conversations on Wikipedia", comment: "This information label is displayed at the top of a talk page topic list. This is fallback text in case a specific wiki language cannot be determined.")
        
        let infoText = stringWithLocalizedCurrentSiteLanguageReplacingPlaceholderInString(string: languageTextFormat, fallbackGenericString: genericInfoText)
        
        var introText: String?
        let sortDescriptor = NSSortDescriptor(key: "sort", ascending: true)
        if let first5IntroReplies = introTopic?.replies?.sortedArray(using: [sortDescriptor]).prefix(5) {
            let replyTexts = Array(first5IntroReplies).compactMap { return ($0 as? TalkPageReply)?.text }
            introText = replyTexts.joined(separator: "<br />")
        }
        
        let viewModel = TalkPageHeaderView.ViewModel(header: headerText, title: controller.displayTitle, info: infoText, intro: introText)
        
        header.configure(viewModel: viewModel)
        header.delegate = self
        header.semanticContentAttributeOverride = talkPageSemanticContentAttribute
        header.apply(theme: theme)
    }
    
    func stringWithLocalizedCurrentSiteLanguageReplacingPlaceholderInString(string: String, fallbackGenericString: String) -> String {
        
        if let code = siteURL.wmf_language,
            let language = (Locale.current as NSLocale).wmf_localizedLanguageNameForCode(code) {
            return NSString.localizedStringWithFormat(string as NSString, language) as String
        } else {
            return fallbackGenericString
        }
    }
    
    func absoluteURL(for url: URL) -> URL? {
        
        var absoluteUrl: URL?
        
        if let firstPathComponent = url.pathComponents.first,
            firstPathComponent == ".",
            url.host == nil,
            url.scheme == nil {
            
            var pathComponents = Array(url.pathComponents.dropFirst()) // replace ./ with wiki/
            pathComponents.insert("/wiki/", at: 0)
            
            absoluteUrl = siteURL.wmf_URL(withPath: pathComponents.joined(), isMobile: true)
            
        } else if url.host != nil && url.scheme != nil {
            absoluteUrl = url
        }
        
        return absoluteUrl
    }
    
    func pushTalkPage(title: String, siteURL: URL) {
        
        let talkPageContainerVC = TalkPageContainerViewController(title: title, siteURL: siteURL, type: .user, dataStore: self.dataStore)
        talkPageContainerVC.apply(theme: self.theme)
        self.navigationController?.pushViewController(talkPageContainerVC, animated: true)
    }
    
    func showUserActionSheet(siteURL: URL, absoluteURL: URL) {
        
        let alertController = UIAlertController(title: WMFLocalizedString("talk-page-link-user-action-sheet-title", value: "User pages", comment: "Title of action sheet that displays when user taps a user page link in talk pages"), message: nil, preferredStyle: .actionSheet)
        let safariAction = UIAlertAction(title: WMFLocalizedString("talk-page-link-user-action-sheet-safari", value: "View User page in Safari", comment: "Title of action sheet button that takes user to a user page in Safari after tapping a user page link in talk pages."), style: .default) { (_) in
            self.openURLInSafari(url: absoluteURL)
        }
        let talkAction = UIAlertAction(title: WMFLocalizedString("talk-page-link-user-action-sheet-app", value: "View User Talk page in app", comment: "Title of action sheet button that takes user to a user talk page in the app after tapping a user page link in talk pages."), style: .default) { (_) in
            
            let title = absoluteURL.lastPathComponent
            if let firstColon = title.range(of: ":") {
                var titleWithoutNamespace = title
                titleWithoutNamespace.removeSubrange(title.startIndex..<firstColon.upperBound)
                let titleWithTalkPageNamespace = TalkPageType.user.titleWithCanonicalNamespacePrefix(title: titleWithoutNamespace, siteURL: siteURL)
                self.pushTalkPage(title: titleWithTalkPageNamespace, siteURL: siteURL)
            }
        }
        let cancelAction = UIAlertAction(title: CommonStrings.cancelActionTitle, style: .cancel, handler: nil)
        
        alertController.addAction(safariAction)
        alertController.addAction(talkAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    func openURLInSafari(url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    func toggleLinkDeterminationState(loadingViewController: FakeLoading & ViewController, shouldDisable: Bool) {
        
        if shouldDisable {
            loadingViewController.fakeProgressController.start()
        } else {
            loadingViewController.fakeProgressController.stop()
        }
        
        loadingViewController.scrollView?.isUserInteractionEnabled = !shouldDisable
        loadingViewController.navigationItem.rightBarButtonItem?.isEnabled = !shouldDisable
    }
    
    func tappedLink(_ url: URL, loadingViewController: FakeLoading & ViewController) {
        guard let absoluteURL = absoluteURL(for: url) else {
            showNoInternetConnectionAlertOrOtherWarning(from: TalkPageError.unableToDetermineAbsoluteURL)
            return
        }
        
        toggleLinkDeterminationState(loadingViewController: loadingViewController, shouldDisable: true)
        
        self.dataStore.articleSummaryController.updateOrCreateArticleSummariesForArticles(withURLs: [absoluteURL]) { [weak self, weak loadingViewController] (articles, error) in
            
            guard let self = self,
            let loadingViewController = loadingViewController else {
                return
            }
            
            self.toggleLinkDeterminationState(loadingViewController: loadingViewController, shouldDisable: false)
            
            if let error = error {
                self.showNoInternetConnectionAlertOrOtherWarning(from: error)
                return
            }
            
            if let namespace = articles.first?.pageNamespace,
                
                //convert absoluteURL into a siteURL that TalkPageType.user.titleWithCanonicalNamespacePrefix will recognize to prefix the canonical name
                let languageCode = absoluteURL.wmf_language,
                let siteURL = MWKLanguageLinkController.sharedInstance().language(forLanguageCode: languageCode)?.siteURL() {
                
                switch namespace {
                case .userTalk:
                    let lastPathComponent = url.lastPathComponent
                    self.pushTalkPage(title: lastPathComponent, siteURL: siteURL)
                case .user:
                    self.showUserActionSheet(siteURL: siteURL, absoluteURL: absoluteURL)
                case .main:
                    self.wmf_pushArticle(with: absoluteURL, dataStore: self.dataStore, theme: self.theme, animated: true)
                default:
                    self.openURLInSafari(url: absoluteURL)
                }
            } else {
                self.openURLInSafari(url: absoluteURL)
            }
        }
    }

    func pushToReplyThread(topic: TalkPageTopic) {
        let replyListViewController = TalkPageReplyListViewController(dataStore: dataStore, topic: topic, talkPageSemanticContentAttribute: talkPageSemanticContentAttribute)
        replyListViewController.delegate = self
        replyListViewController.apply(theme: theme)
        replyListViewController.repliesAreDisabled = repliesAreDisabled
        self.replyListViewController = replyListViewController
        navigationController?.pushViewController(replyListViewController, animated: true)
    }
}

// MARK: Empty & error states

extension TalkPageContainerViewController {
    private func hideEmptyView() {
        navigationBar.setNavigationBarPercentHidden(0, underBarViewPercentHidden: 0, extendedViewPercentHidden: 0, topSpacingPercentHidden: 0, animated: true)
        wmf_hideEmptyView()
    }

    private func showEmptyView() {
        navigationBar.setNavigationBarPercentHidden(1, underBarViewPercentHidden: 1, extendedViewPercentHidden: 1, topSpacingPercentHidden: 0, animated: true)
        wmf_showEmptyView(of: .unableToLoadTalkPage, theme: self.theme, frame: self.view.bounds)
    }

    private func showNoInternetConnectionAlertOrOtherWarning(from error: Error, noInternetConnectionAlertMessage: String = CommonStrings.noInternetConnection) {
        if (error as NSError).wmf_isNetworkConnectionError() {
            WMFAlertManager.sharedInstance.showErrorAlertWithMessage(noInternetConnectionAlertMessage, sticky: true, dismissPreviousAlerts: true)
        } else if let talkPageError = error as? TalkPageError {
            WMFAlertManager.sharedInstance.showWarningAlert(talkPageError.localizedDescription, sticky: true, dismissPreviousAlerts: true)
        }  else {
            WMFAlertManager.sharedInstance.showErrorAlertWithMessage(error.localizedDescription, sticky: true, dismissPreviousAlerts: true)
        }
    }
}

//MARK: TalkPageTopicNewViewControllerDelegate

extension TalkPageContainerViewController: TalkPageTopicNewViewControllerDelegate {
    func tappedPublish(subject: String, body: String, viewController: TalkPageTopicNewViewController) {
        
        guard let talkPage = talkPage else {
            assertionFailure("Missing Talk Page")
            return
        }
        
        viewController.postDidBegin()
        controller.addTopic(toTalkPageWith: talkPage.objectID, title: talkPageTitle, siteURL: siteURL, subject: subject, body: body) { [weak self] (result) in
            DispatchQueue.main.async {
                viewController.postDidEnd()

                switch result {
                case .success(let result):
                    if result != .success {
                        self?.fetch()
                    }
                    self?.navigationController?.popViewController(animated: true)
                    NotificationCenter.default.post(name: Notification.Name(TalkPageContainerViewController.WMFTopicPublishedNotificationName), object: nil)
                case .failure(let error):
                    self?.showNoInternetConnectionAlertOrOtherWarning(from: error, noInternetConnectionAlertMessage: WMFLocalizedString("talk-page-error-unable-to-post-topic", value: "No internet connection. Unable to post topic.", comment: "Error message appearing when user attempts to post a new talk page topic while being offline"))
                }
            }
        }
    }
}

//MARK: TalkPageTopicListDelegate

extension TalkPageContainerViewController: TalkPageTopicListDelegate {    
    func scrollViewDidScroll(_ scrollView: UIScrollView, viewController: TalkPageTopicListViewController) {
        hintController?.dismissHintDueToUserInteraction()
    }
    
    func tappedTopic(_ topic: TalkPageTopic, viewController: TalkPageTopicListViewController) {
        pushToReplyThread(topic: topic)
    }

    func didBecomeActiveAfterCompletingActivity(ofType completedActivityType: UIActivity.ActivityType?) {
        if completedActivityType == .openInSafari {
            fetch()
        }
    }
}

//MARK: TalkPageReplyListViewControllerDelegate

extension TalkPageContainerViewController: TalkPageReplyListViewControllerDelegate {
    func tappedPublish(topic: TalkPageTopic, composeText: String, viewController: TalkPageReplyListViewController) {
        
        viewController.postDidBegin()
        controller.addReply(to: topic, title: talkPageTitle, siteURL: siteURL, body: composeText) { (result) in
            DispatchQueue.main.async {
                viewController.postDidEnd()
                NotificationCenter.default.post(name: Notification.Name(TalkPageContainerViewController.WMFReplyPublishedNotificationName), object: nil)
                
                switch result {
                case .success:
                    break
                case .failure(let error):
                    self.showNoInternetConnectionAlertOrOtherWarning(from: error, noInternetConnectionAlertMessage: WMFLocalizedString("talk-page-error-unable-to-post-reply", value: "No internet connection. Unable to post reply.", comment: "Error message appearing when user attempts to post a new talk page reply while being offline"))
                }
            }
        }
    }
    
    func tappedLink(_ url: URL, viewController: TalkPageReplyListViewController) {
        tappedLink(url, loadingViewController: viewController)
    }
}

extension TalkPageContainerViewController: TalkPageHeaderViewDelegate {
    func tappedLink(_ url: URL, headerView: TalkPageHeaderView) {
        tappedLink(url, loadingViewController: self)
    }
    
    func tappedIntro(headerView: TalkPageHeaderView) {
        if let introTopic = self.introTopic {
            pushToReplyThread(topic: introTopic)
        }
    }
}
