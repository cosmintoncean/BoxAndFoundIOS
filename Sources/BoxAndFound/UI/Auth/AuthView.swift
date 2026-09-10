import AuthenticationServices
import SwiftUI

/// The sign-in and sign-up form, ported from the Android `AuthScreen`.
///
/// Sign in with Apple sits above the other providers because Apple requires it
/// to be at least as prominent as any other third-party button once one is
/// offered — and offering Google or Facebook without it fails review outright.
struct AuthView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = AuthViewModel()
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                modePicker
                fields
                outcome
                submitButton
                divider
                providers
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bfBg)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        Text(viewModel.mode.heading)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color.bfText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        Picker("", selection: $viewModel.mode) {
            ForEach(AuthViewModel.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.submitting)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            if viewModel.mode == .signUp {
                labelled("Name") {
                    TextField("Optional", text: $viewModel.name)
                        .textContentType(.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                }
            }

            labelled("Email") {
                TextField("you@example.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }

            labelled("Password") {
                HStack {
                    Group {
                        if viewModel.passwordVisible {
                            TextField("", text: $viewModel.password)
                        } else {
                            SecureField("", text: $viewModel.password)
                        }
                    }
                    .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.submit() } }

                    Button {
                        viewModel.passwordVisible.toggle()
                    } label: {
                        Image(systemName: viewModel.passwordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(Color.bfTextMuted)
                    }
                    .accessibilityLabel(viewModel.passwordVisible ? "Hide password" : "Show password")
                }
            }

            if viewModel.mode == .signUp {
                Text("At least \(Credentials.minPasswordLength) characters")
                    .font(.footnote)
                    .foregroundStyle(Color.bfTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var outcome: some View {
        if let failure = viewModel.visibleFailure {
            notice(failure.message, tint: .bfDanger, background: .bfDangerSoft)
        } else if viewModel.confirmationSent {
            notice(
                "Account created. Check your email to confirm your address, then sign in.",
                tint: .bfGreen,
                background: .bfGreenSoft
            )
        }
    }

    private var submitButton: some View {
        Button {
            focus = nil
            Task { await viewModel.submit() }
        } label: {
            ZStack {
                Text(viewModel.mode.action).opacity(viewModel.submitting ? 0 : 1)
                if viewModel.submitting {
                    ProgressView().tint(.white)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.bfAccent, in: .rect(cornerRadius: 12))
            .opacity(viewModel.canSubmit ? 1 : 0.5)
        }
        .disabled(!viewModel.canSubmit)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            line
            Text("or continue with")
                .font(.footnote)
                .foregroundStyle(Color.bfTextMuted)
                .fixedSize()
            line
        }
    }

    private var line: some View {
        Rectangle().fill(Color.bfBorder).frame(height: 1)
    }

    private var providers: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await viewModel.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(.rect(cornerRadius: 12))

            providerButton("Continue with Google", provider: .google)
            providerButton("Continue with Facebook", provider: .facebook)
        }
        .disabled(viewModel.submitting)
    }

    private func providerButton(_ title: String, provider: OAuthProvider) -> some View {
        Button {
            Task { await viewModel.startOAuth(provider) }
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.bfText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.bfSurface, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.bfBorder, lineWidth: 1)
                }
        }
    }

    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.bfTextMuted)
            content()
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Color.bfSurface, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.bfBorder, lineWidth: 1)
                }
                .foregroundStyle(Color.bfText)
        }
    }

    private func notice(_ text: String, tint: Color, background: Color) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(background, in: .rect(cornerRadius: 10))
    }
}
