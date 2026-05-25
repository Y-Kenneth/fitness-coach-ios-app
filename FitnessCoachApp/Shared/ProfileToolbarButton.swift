import SwiftUI

/// A person.crop.circle button that opens ProfileView as a sheet.
///
/// Use inside a `.toolbar { ToolbarItem(placement: .navigationBarTrailing) { ... } }`
/// block on any tab root that already has a NavigationStack.
struct ProfileToolbarButton: View {
    @State private var showingProfile = false

    var body: some View {
        Button(action: { showingProfile = true }) {
            Image(systemName: "person.crop.circle")
                .font(.title3)
        }
        .accessibilityLabel("Profile")
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
    }
}
