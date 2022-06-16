import Foundation
import WordPressKit

protocol QRLoginVerifyView {
    func render(response: QRLoginValidationResponse)
    func renderCompletion()

    func showLoading()
    func showAuthenticating()

    func showNoConnectionError()
    func showQRLoginError(error: QRLoginError?)
    func showAuthenticationFailedError()
}

class QRLoginVerifyCoordinator {
    private let parentCoordinator: QRLoginCoordinator
    private let view: QRLoginVerifyView
    private let token: QRLoginToken
    private var state: ViewState = .verifyingCode
    private let service: QRLoginService

    init(token: QRLoginToken,
         view: QRLoginVerifyView,
         parentCoordinator: QRLoginCoordinator,
         service: QRLoginService? = nil,
         context: NSManagedObjectContext = ContextManager.sharedInstance().mainContext) {
        self.token = token
        self.view = view
        self.parentCoordinator = parentCoordinator
        self.service = service ?? QRLoginService(managedObjectContext: context)
    }

    enum ViewState {
        case verifyingCode
        case waitingForUserVerification
        case authenticating
        case error
        case done
    }
}

// MARK: - View Interactions
extension QRLoginVerifyCoordinator {
    func start() {
        state = .verifyingCode

        view.showLoading()

        service.validate(token: token) { response in
            self.state = .waitingForUserVerification
            self.view.render(response: response)
        } failure: { _, qrLoginError in
            self.state = .error

            // Check if we have no connection
            let appDelegate = WordPressAppDelegate.shared

            guard
                let connectionAvailable = appDelegate?.connectionAvailable, connectionAvailable == true
            else {
                self.view.showNoConnectionError()
                return
            }

            self.view.showQRLoginError(error: qrLoginError)
        }
    }

    func confirm() {
        // If we're in the done state, dismiss the flow
        // If we're in the error state, do something
        switch state {
            case .done:
                parentCoordinator.dismiss()
                return
            case .error:
                parentCoordinator.scanAgain()
                return
            default: break
        }

        // TODO: Make network request to log the user in
        view.showAuthenticating()
        state = .authenticating

        service.authenticate(token: token) { success in
            self.state = .done
            self.view.renderCompletion()
        } failure: { error in
            self.state = .error
            self.view.showAuthenticationFailedError()
        }
    }

    func cancel() {
        parentCoordinator.dismiss()
    }
}
