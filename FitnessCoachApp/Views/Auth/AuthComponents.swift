import SwiftUI

// MARK: - Text fields

struct AuthTextField: View {
    let placeholder: String
    let icon: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppConstants.Color.accent)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(keyboardType)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(AppConstants.Color.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AuthSecureField: View {
    let placeholder: String
    let icon: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppConstants.Color.accent)
                .frame(width: 20)

            SecureField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(AppConstants.Color.accent)
                .textContentType(.oneTimeCode)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Toast notification

struct AuthToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppConstants.Color.danger)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Color(red: 0.12, green: 0.04, blue: 0.04)
                AppConstants.Color.danger.opacity(0.12)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppConstants.Color.danger.opacity(0.4), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: AppConstants.Color.danger.opacity(0.25), radius: 16, y: 6)
    }
}

// MARK: - Toast modifier

struct AuthToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible, let msg = message {
                    AuthToast(message: msg) { dismiss() }
                        .padding(.horizontal, 16)
                        .padding(.top, 56)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isVisible)
            .onChange(of: message) { newValue in
                if newValue != nil {
                    show()
                } else {
                    isVisible = false
                }
            }
    }

    private func show() {
        dismissTask?.cancel()
        isVisible = true
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { dismiss() }
        }
    }

    private func dismiss() {
        isVisible = false
        dismissTask?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            message = nil
        }
    }
}

extension View {
    func authToast(message: Binding<String?>) -> some View {
        modifier(AuthToastModifier(message: message))
    }
}
