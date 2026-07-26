import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var appRouter: AppRouter

    var body: some View {
        Group {
            if authService.isLoading {
                SplashView()
            } else if authService.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationFlowView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: authService.isLoading)
    }
}
