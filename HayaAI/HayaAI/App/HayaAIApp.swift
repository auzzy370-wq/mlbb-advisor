import SwiftUI
import FirebaseCore

@main
struct HayaAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appRouter = AppRouter()
    @StateObject private var authService = AuthenticationService()
    @StateObject private var heroDatabaseService = HeroDatabaseService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appRouter)
                .environmentObject(authService)
                .environmentObject(heroDatabaseService)
                .preferredColorScheme(.dark)
        }
    }
}
