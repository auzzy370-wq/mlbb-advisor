import SwiftUI
import Combine

enum AppRoute: Hashable {
    case login
    case register
    case dashboard
    case draftAssistant
    case heroDetail(String)
    case settings
    case profile
    case analytics
    case onboarding
}

enum AppTab: Int, CaseIterable, Identifiable {
    case dashboard = 0
    case draftAssistant
    case analytics
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .draftAssistant: return "Draft"
        case .analytics: return "Analytics"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house.fill"
        case .draftAssistant: return "shield.lefthalf.filled"
        case .analytics: return "chart.bar.xaxis"
        case .settings: return "gear"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var navigationPath: NavigationPath = NavigationPath()
    @Published var isAuthenticated: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var presentedSheet: AppRoute? = nil

    func navigate(to route: AppRoute) {
        navigationPath.append(route)
    }

    func popToRoot() {
        navigationPath = NavigationPath()
    }

    func present(_ route: AppRoute) {
        presentedSheet = route
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func switchTab(_ tab: AppTab) {
        selectedTab = tab
    }
}
