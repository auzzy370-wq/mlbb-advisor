import Foundation
import FirebaseAuth
import Combine

// MARK: - Authentication Service
@MainActor
final class AuthenticationService: ObservableObject, AuthenticationServiceProtocol {

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentProfile: UserProfile? = nil
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var authError: AuthError? = nil

    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        setupAuthListener()
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    // MARK: - Auth Listener

    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let user {
                    self.isAuthenticated = true
                    self.currentProfile = self.buildProfile(from: user)
                } else {
                    self.isAuthenticated = false
                    self.currentProfile = nil
                }
                self.isLoading = false
            }
        }
    }

    // MARK: - Protocol

    nonisolated var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    func signIn(email: String, password: String) async throws -> UserProfile {
        isLoading = true
        authError = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let profile = buildProfile(from: result.user)
            currentProfile = profile
            isAuthenticated = true
            isLoading = false
            return profile
        } catch {
            isLoading = false
            let err = mapFirebaseError(error)
            authError = err
            throw err
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws -> UserProfile {
        isLoading = true
        authError = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            var profile = buildProfile(from: result.user)
            profile.displayName = displayName
            currentProfile = profile
            isAuthenticated = true
            isLoading = false
            return profile
        } catch {
            isLoading = false
            let err = mapFirebaseError(error)
            authError = err
            throw err
        }
    }

    func signOut() async throws {
        do {
            try Auth.auth().signOut()
            isAuthenticated = false
            currentProfile = nil
        } catch {
            throw mapFirebaseError(error)
        }
    }

    func currentUser() async throws -> UserProfile? { currentProfile }

    func updateProfile(_ profile: UserProfile) async throws {
        currentProfile = profile
    }

    // MARK: - Apple Sign In (future)
    func signInWithApple() async throws -> UserProfile {
        throw AuthError.notImplemented
    }

    // MARK: - Helpers

    private func buildProfile(from user: User) -> UserProfile {
        UserProfile(
            id: user.uid,
            displayName: user.displayName ?? "Player",
            email: user.email ?? "",
            avatarURL: user.photoURL?.absoluteString
        )
    }

    private func mapFirebaseError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        switch nsError.code {
        case AuthErrorCode.wrongPassword.rawValue: return .wrongPassword
        case AuthErrorCode.invalidEmail.rawValue: return .invalidEmail
        case AuthErrorCode.emailAlreadyInUse.rawValue: return .emailInUse
        case AuthErrorCode.userNotFound.rawValue: return .userNotFound
        case AuthErrorCode.weakPassword.rawValue: return .weakPassword
        default: return .unknown(error.localizedDescription)
        }
    }
}

// MARK: - Auth Errors
enum AuthError: Error, LocalizedError, Equatable {
    case wrongPassword
    case invalidEmail
    case emailInUse
    case userNotFound
    case weakPassword
    case notImplemented
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return "Incorrect password. Please try again."
        case .invalidEmail: return "Invalid email address."
        case .emailInUse: return "This email is already registered."
        case .userNotFound: return "No account found with this email."
        case .weakPassword: return "Password must be at least 6 characters."
        case .notImplemented: return "This sign-in method is not yet available."
        case .unknown(let msg): return msg
        }
    }

    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
