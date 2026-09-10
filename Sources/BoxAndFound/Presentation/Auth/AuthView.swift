import AuthenticationServices
import SwiftUI

/// The sign-in and sign-up form.
///
/// Passive by construction: it reads `presenter.viewState` and sends intents
/// back. Every text field is a one-way `Binding` — `get` reads the state,
/// `set` calls an intent — so nothing on screen can change without the
/// presenter deciding it did.
///
/// Sign in with Apple sits above the other providers because Apple requires it
/// to be at least as prominent as any other third-party button once one is
/// offered — and offering Google or Facebook without it fails review outright.
struct AuthView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var presenter = AuthPresenter()
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    var body: some View {
        let state = presenter.viewState

        ScrollView {
            VStack(spacing: 20) {
                header(state)
                modePicker(state)
                fields(state)
                notice(state)
                submitButton(state)
                divider
                providers(state)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bfBg)
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ state: AuthViewState) -> some View {
        Text(state.heading)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color.bfText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modePicker(_ state: AuthViewState) -> some View {
        Picker("", selection: Binding(
            get: { state.mode },
            set: { presenter.modeSelected($0) }
        )) {
            ForEach(state.modes) { option in
                Text(option.title).tag(option.mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(state.isSubmitting)
    }

    private func fields(_ state: AuthViewState) -> some View {
        VStack(spacing: 12) {
            if state.isNameFieldVisible {
                labelled("Name") {
                    TextField("Optional", text: Binding(
                        get: { state.name },
                        set: { presenter.nameChanged($0) }
                    ))
                    .textContentType(.name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                }
            }

            labelled("Email") {
                TextField("you@example.com", text: Binding(
                    get: { state.email },
                    set: { presenter.emailChanged($0) }
                ))
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
                    let password = Binding(
                        get: { state.password },
                        set: { presenter.passwordChanged($0) }
                    )
                    Group {
                        if state.isPasswordVisible {
                            TextField("", text: password)
                        } else {
                            SecureField("", text: password)
                        }
                    }
                    .textContentType(state.mode == .signIn ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await presenter.submitTapped() } }

                    Button {
                        presenter.passwordVisibilityToggled()
                    } label: {
                        Image(systemName: state.isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(Color.bfTextMuted)
                    }
                    .accessibilityLabel(state.isPasswordVisible ? "Hide password" : "Show password")
                }
            }

            if let hint = state.passwordHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Color.bfTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func notice(_ state: AuthViewState) -> some View {
        if let notice = state.notice {
            let tint: Color = notice.kind == .error ? .bfDanger : .bfGreen
            let background: Color = notice.kind == .error ? .bfDangerSoft : .bfGreenSoft
            Text(notice.text)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(background, in: .rect(cornerRadius: 10))
        }
    }

    private func submitButton(_ state: AuthViewState) -> some View {
        Button {
            focus = nil
            Task { await presenter.submitTapped() }
        } label: {
            ZStack {
                Text(state.submitTitle).opacity(state.isSubmitting ? 0 : 1)
                if state.isSubmitting {
                    ProgressView().tint(.white)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.bfAccent, in: .rect(cornerRadius: 12))
            .opacity(state.isSubmitEnabled ? 1 : 0.5)
        }
        .disabled(!state.isSubmitEnabled)
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

    private func providers(_ state: AuthViewState) -> some View {
        VStack(spacing: 12) {
            ForEach(state.providers) { button in
                switch button.kind {
                case .apple:
                    SignInWithAppleButton(.continue) { request in
                        presenter.appleRequestPrepared(request)
                    } onCompletion: { result in
                        Task { await presenter.appleSignInCompleted(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(.rect(cornerRadius: 12))
                case .google, .facebook:
                    providerButton(button)
                }
            }
        }
        .disabled(state.isSubmitting)
    }

    private func providerButton(_ button: AuthViewState.ProviderButton) -> some View {
        Button {
            Task { await presenter.providerTapped(button.kind) }
        } label: {
            Text(button.title)
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
}
