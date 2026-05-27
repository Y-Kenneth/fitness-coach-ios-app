import SwiftUI

/// A small teal initial-circle button that opens ProfileView as a sheet.
/// Replaces the system person.crop.circle to match the v2 mockups.
struct ProfileToolbarButton: View {
    @EnvironmentObject private var profileVM: ProfileViewModel
    @State private var showingProfile = false

    var body: some View {
        Button(action: { showingProfile = true }) {
            Group {
                if UIImage(named: "profile_photo") != nil {
                    Image("profile_photo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(AppConstants.Color.accent, lineWidth: 1.5))
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppConstants.Color.accent, AppConstants.Color.accentDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 6)
                        Text(profileVM.profile.name.prefix(1).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
            }
        }
        .accessibilityLabel("Profile")
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
    }
}
