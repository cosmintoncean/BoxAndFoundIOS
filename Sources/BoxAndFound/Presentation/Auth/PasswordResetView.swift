import SwiftUI

/// Step two of a password reset: the emailed link has been opened, the session
/// it carries is live, and the only thing left is the new password.
///
/// Shown in place of the whole app, so it deliberately offers no way further
/// in — finishing or backing out are the two exits.
struct PasswordResetView: View {
    @State private var presenter: PasswordResetPresenter
    @FocusState private var focus: Field?

    private enum Field { case password, confirmation }

    init(onFinished: @escaping () -> Void) {
        _presenter = State(initialValue: PasswordResetPresenter(onFinished: onFinished))
    }

    var body: some View {
        let state = presenter.viewState

        ScrollView {
            VStack(spacing: 20) {
                header
                fields(state)
                notice(state)
                submitButton(state)
                cancelButton(state)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bfBg)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a new password")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.bfText)
            Text("This replaces the password on your account. You will stay signed in on this device.")
                .font(.subheadline)
                .foregroundStyle(Color.bfTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fields(_ state: PasswordResetViewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            labelled("New password") {
                secureRow(
                    text: Binding(
                        get: { state.password },
                        set: { presenter.passwordChanged($0) }
                    ),
                    isVisible: state.isPasswordVisible,
                    field: .password,
                    submitLabel: .next,
                    onSubmit: { focus = .confirmation }
                )
            }

            Text(state.passwordHint)
                .font(.footnote)
                .foregroundStyle(Color.bfTextMuted)

            labelled("Confirm new password") {
                secureRow(
                    text: Binding(
                        get: { state.confirmation },
                        set: { presenter.confirmationChanged($0) }
                    ),
                    isVisible: state.isPasswordVisible,
                    field: .confirmation,
                    submitLabel: .go,
                    onSubmit: { submit() }
                )
            }

            if let warning = state.mismatchWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(Color.bfDanger)
            }
        }
    }

    private func secureRow(
        text: Binding<String>,
        isVisible: Bool,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack {
            Group {
                if isVisible {
                    TextField("", text: text)
                } else {
                    SecureField("", text: text)
                }
            }
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)

            Button {
                presenter.passwordVisibilityToggled()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(Color.bfTextMuted)
            }
            .accessibilityLabel(isVisible ? "Hide password" : "Show password")
        }
    }

    @ViewBuilder
    private func notice(_ state: PasswordResetViewState) -> some View {
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

    private func submitButton(_ state: PasswordResetViewState) -> some View {
        Button {
            submit()
        } label: {
            ZStack {
                Text("Save new password").opacity(state.isSubmitting ? 0 : 1)
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

    private func cancelButton(_ state: PasswordResetViewState) -> some View {
        Button("Back to sign in") {
            focus = nil
            Task { await presenter.cancelTapped() }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.bfTextMuted)
        .disabled(state.isSubmitting)
    }

    private func submit() {
        focus = nil
        Task { await presenter.submitTapped() }
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
