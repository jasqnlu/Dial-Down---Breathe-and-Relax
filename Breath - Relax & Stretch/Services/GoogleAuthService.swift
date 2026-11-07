import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - GoogleAuthService
// Sign in with Google via OAuth 2.0 Authorization Code + PKCE, using
// ASWebAuthenticationSession directly — no GoogleSignIn SDK / SPM dependency,
// no Info.plist URL scheme needed (the session intercepts its own redirect).
//
// SETUP:
//   1. Google Cloud Console → APIs & Services → Credentials →
//      Create OAuth client ID → iOS → enter this app's Bundle ID.
//   2. Copy the generated Client ID (e.g. "123456-abc.apps.googleusercontent.com")
//      into `clientID` below.
//   That's it — no other configuration needed.

final class GoogleAuthService: NSObject {
    static let shared = GoogleAuthService()
    private override init() {}

    // Replace with your iOS OAuth Client ID from Google Cloud Console.
    private let clientID = "100179065649-o6avkunmdq6sf6gvd3huimp1lkcbft2p.apps.googleusercontent.com"

    static var isConfigured: Bool {
        !shared.clientID.contains("YOUR_CLIENT_ID")
    }

    /// Google's convention for iOS OAuth clients: the reversed client id is
    /// also the redirect URL scheme.
    private var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    private var redirectURI: String { "\(redirectScheme):/oauth2redirect/google" }

    private var presentationAnchor: ASPresentationAnchor?

    struct GoogleUser {
        let email: String
        let name: String
    }

    /// Everything a caller needs to complete a Supabase id_token exchange
    /// after a successful Google sign-in.
    struct GoogleSignInResult {
        let idToken: String
        let nonce: String
        let user: GoogleUser
    }

    enum GoogleAuthError: LocalizedError, Equatable {
        case notConfigured, cancelled, invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:   return "Google Sign-In hasn't been configured yet."
            case .cancelled:       return "Sign-in was cancelled."
            case .invalidResponse: return "Google didn't return a valid response."
            }
        }
    }

    @MainActor
    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> GoogleSignInResult {
        guard Self.isConfigured else { throw GoogleAuthError.notConfigured }
        self.presentationAnchor = presentationAnchor

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 16)
        let rawNonce = Self.randomURLSafeString(length: 32)
        let hashedNonce = Self.sha256Hex(rawNonce)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: hashedNonce),
        ]

        let callbackURL = try await authenticate(url: components.url!, callbackScheme: redirectScheme)

        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
            returnedState == state,
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw GoogleAuthError.invalidResponse }

        let tokens = try await exchangeCode(code: code, verifier: verifier)
        let user = try await fetchUserInfo(accessToken: tokens.accessToken)
        return GoogleSignInResult(idToken: tokens.idToken, nonce: rawNonce, user: user)
    }

    @MainActor
    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleAuthError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let accessToken: String
        let idToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case idToken = "id_token"
        }
    }

    private func exchangeCode(code: String, verifier: String) async throws -> (accessToken: String, idToken: String) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleAuthError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return (decoded.accessToken, decoded.idToken)
    }

    private struct UserInfoResponse: Decodable {
        let email: String
        let name: String?
    }

    private func fetchUserInfo(accessToken: String) async throws -> GoogleUser {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleAuthError.invalidResponse
        }
        let info = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return GoogleUser(email: info.email, name: info.name ?? info.email)
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Hex-digest SHA-256, for the OIDC nonce (Google/Supabase expect hex,
    /// unlike the base64url PKCE code_challenge above). Not `private` so
    /// GoogleAuthServiceTests can verify it against a known test vector —
    /// same pattern as `SupabaseService.isValidAPIHost`.
    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        var hexString = ""
        withUnsafeBytes(of: digest) { bytes in
            for byte in bytes {
                hexString.append(String(format: "%02x", byte))
            }
        }
        return hexString
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let presentationAnchor { return presentationAnchor }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.lazy.compactMap(\.keyWindow).first { return window }
        guard let scene = scenes.first else { preconditionFailure("Google sign-in needs a window scene") }
        return ASPresentationAnchor(windowScene: scene)
    }
}

// MARK: - Presentation anchor helper

extension ASPresentationAnchor {
    static var currentWindow: ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
