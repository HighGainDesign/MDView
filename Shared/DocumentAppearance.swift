import Foundation

enum DocumentAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var colorScheme: String { self == .system ? "light dark" : rawValue }
}
