import AuthenticationServices
import CryptoKit
import UIKit

/// Shows the Sign in with Apple sheet without a SignInWithAppleButton, so
/// Delete Account can ask an Apple user to re-confirm. The fresh one-time
/// authorization code it returns is what the delete-account function
/// needs to revoke the app's Apple authorization (Guideline 5.1.1(v)).
final class AppleReauthenticator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleReauthCredential, Error>?
    private var rawNonce: String?

    func reauthenticate() async throws -> AppleReauthCredential {
        let raw = AuthManager.randomNonce()
        rawNonce = raw
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [] // re-confirm only; no name/email needed
        request.nonce = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let code = String(data: codeData, encoding: .utf8),
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            finish(.failure(AccountDeletionError.appleReauthRequired))
            return
        }
        finish(.success(AppleReauthCredential(
            appleUserID: credential.user, authorizationCode: code,
            identityToken: token, rawNonce: rawNonce)))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(AccountDeletionError.appleReauthRequired))
        }
    }

    @available(iOS, deprecated: 26.0, message: "uses the scene-less anchor as a last resort")
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
            return key
        }
        return scenes.first.map { ASPresentationAnchor(windowScene: $0) } ?? Self.detachedAnchor()
    }

    /// Last-resort anchor when no window scene exists (never expected while the
    /// app is foregrounded). The scene-less init is deprecated in iOS 26 and no
    /// scene-based alternative exists without a scene, so it is isolated in a
    /// function that is itself marked deprecated, which keeps the build clean.
    @available(iOS, deprecated: 26.0)
    private static func detachedAnchor() -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    private func finish(_ result: Result<AppleReauthCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        rawNonce = nil
    }
}
