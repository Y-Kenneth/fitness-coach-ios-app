import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var toastMessage: String?

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    private var canSubmit: Bool {
        !auth.isLoading
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.isEmpty
            && password.count >= 6
            && confirmPassword == password
    }

    var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create Account")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Start your fitness journey today.")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(spacing: 14) {
                        AuthTextField(
                            placeholder: "Full Name",
                            icon: "person",
                            text: $name
                        )
                        AuthTextField(
                            placeholder: "Email",
                            icon: "envelope",
                            text: $email,
                            keyboardType: .emailAddress
                        )
                        AuthSecureField(
                            placeholder: "Password (min. 6 characters)",
                            icon: "lock",
                            text: $password
                        )
                        AuthSecureField(
                            placeholder: "Confirm Password",
                            icon: "lock.fill",
                            text: $confirmPassword
                        )

                        if passwordMismatch {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(AppConstants.Color.warn)
                                Text("Passwords don't match")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppConstants.Color.warn)
                            }
                        }
                    }

                    Button(action: {
                        Task { await register() }
                    }) {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text("Create Account")
                            }
                        }
                    }
                    .buttonStyle(FCPrimaryButtonStyle())
                    .disabled(!canSubmit)

                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundStyle(.white.opacity(0.5))
                                Text("Sign in")
                                    .foregroundStyle(AppConstants.Color.accent)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 14))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.bottom, 48)
            }
        }
        .authToast(message: $toastMessage)
    }

    private func register() async {
        await auth.signUp(
            email: email,
            password: password,
            name: name.trimmingCharacters(in: .whitespaces)
        )
        if let err = auth.errorMessage {
            toastMessage = err
        }
    }
}
