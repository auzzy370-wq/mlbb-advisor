import SwiftUI

struct AuthenticationFlowView: View {
    @State private var showLogin = true

    var body: some View {
        ZStack {
            HayaBackground()
            if showLogin {
                LoginView(showRegister: { withAnimation(.spring()) { showLogin = false } })
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            } else {
                RegisterView(showLogin: { withAnimation(.spring()) { showLogin = true } })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            }
        }
    }
}

// MARK: - Login View
struct LoginView: View {
    var showRegister: () -> Void
    @EnvironmentObject private var authService: AuthenticationService
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)
                LogoHeader(subtitle: "Draft Smarter. Win More.")

                VStack(spacing: 16) {
                    HayaTextField(text: $email, placeholder: "Email", icon: "envelope.fill")
                        .focused($focus, equals: .email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    HayaSecureField(text: $password, placeholder: "Password")
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                }
                .padding(.horizontal, 24)

                if let error = authService.authError {
                    ErrorBannerView(message: error.localizedDescription ?? "")
                }

                HayaButton(title: "Sign In", isLoading: isLoading) { signIn() }
                    .padding(.horizontal, 24)

                HStack {
                    Text("Don't have an account?")
                        .foregroundStyle(.secondary)
                    Button("Sign Up") { showRegister() }
                        .foregroundStyle(Color.hayaGold)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)

                // Divider with label
                HStack(spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                }
                .padding(.horizontal, 24)

                Button {
                    authService.continueAsGuest()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                        Text("Continue as Guest")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)

                Text("No account needed · All core features available offline")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        Task {
            _ = try? await authService.signIn(email: email, password: password)
            isLoading = false
        }
    }
}

// MARK: - Register View
struct RegisterView: View {
    var showLogin: () -> Void
    @EnvironmentObject private var authService: AuthenticationService
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)
                LogoHeader(subtitle: "Join the Haya AI Community")

                VStack(spacing: 16) {
                    HayaTextField(text: $displayName, placeholder: "Display Name", icon: "person.fill")
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }

                    HayaTextField(text: $email, placeholder: "Email", icon: "envelope.fill")
                        .focused($focus, equals: .email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    HayaSecureField(text: $password, placeholder: "Password (6+ characters)")
                        .focused($focus, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { register() }
                }
                .padding(.horizontal, 24)

                if let error = authService.authError {
                    ErrorBannerView(message: error.localizedDescription ?? "")
                }

                HayaButton(title: "Create Account", isLoading: isLoading) { register() }
                    .padding(.horizontal, 24)

                HStack {
                    Text("Already have an account?")
                        .foregroundStyle(.secondary)
                    Button("Sign In") { showLogin() }
                        .foregroundStyle(Color.hayaGold)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func register() {
        guard !displayName.isEmpty, !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        Task {
            _ = try? await authService.signUp(email: email, password: password, displayName: displayName)
            isLoading = false
        }
    }
}
