import Foundation

enum DocumentAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: String { self == .system ? "light dark" : rawValue }
}
