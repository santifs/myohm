import SwiftUI

// MARK: - Environment Keys

private struct NavigationPathKey: @preconcurrency EnvironmentKey {
    @MainActor
    static let defaultValue: Binding<NavigationPath> = .constant(NavigationPath())
}

extension EnvironmentValues {
    var navigationPath: Binding<NavigationPath> {
        get { self[NavigationPathKey.self] }
        set { self[NavigationPathKey.self] = newValue }
    }
}