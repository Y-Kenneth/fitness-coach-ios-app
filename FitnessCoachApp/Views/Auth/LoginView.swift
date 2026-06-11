import SwiftUI

private struct TopRounded: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var toastMessage: String?
    @AppStorage("devSkipLogin") private var devSkipLogin = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                LoginBackground(size: geo.size)
                formPanel(safeBottom: geo.safeAreaInsets.bottom)
            }
        }
        .ignoresSafeArea()
        .authToast(message: $toastMessage)
        .fullScreenCover(isPresented: $showRegister) {
            RegisterView().environmentObject(auth)
        }
    }

    private func formPanel(safeBottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign In")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Good to see you again.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Fields
            VStack(spacing: 12) {
                AuthTextField(placeholder: "Email", icon: "envelope",
                              text: $email, keyboardType: .emailAddress)
                AuthSecureField(placeholder: "Password", icon: "lock",
                                text: $password)
            }

            // Button
            Button(action: { Task { await signIn() } }) {
                Group {
                    if auth.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Text("Sign In").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FCPrimaryButtonStyle())
            .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

            // Register link
            HStack {
                Spacer()
                Button(action: { showRegister = true }) {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundColor(.white.opacity(0.55))
                        Text("Create one")
                            .foregroundColor(AppConstants.Color.accent)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                }
                Spacer()
            }

            // Dev bypass — skip Firebase login for on-device testing
            Button(action: { devSkipLogin = true }) {
                Text("Skip (Testing Only)")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        // Bottom padding = safe area + extra breathing room
        .padding(.bottom, safeBottom + 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Color.black.opacity(0.50)
                Color(red: 0.02, green: 0.10, blue: 0.08).opacity(0.55)
            }
        )
        // clipShape on the WHOLE panel — both corners round correctly
        .clipShape(TopRounded(radius: 28))
    }

    private func signIn() async {
        await auth.signIn(email: email, password: password)
        if let err = auth.errorMessage { toastMessage = err }
    }
}

// MARK: - Background

private struct LoginBackground: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Color.black

            Image("hero_loginpage")
                .resizable()
                .scaledToFill()
                .frame(width: size.width + 120, height: size.height)
                .offset(x: 60)
                .clipped()
                .frame(width: size.width, height: size.height)

            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.55), Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )

            RadialGradient(
                colors: [AppConstants.Color.accent.opacity(0.35), AppConstants.Color.accent.opacity(0.12), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0, endRadius: size.width * 0.85
            )

            RadialGradient(
                colors: [AppConstants.Color.accentDark.opacity(0.28), .clear],
                center: UnitPoint(x: 0.05, y: 1.0),
                startRadius: 0, endRadius: size.width * 0.65
            )
        }
    }
}
