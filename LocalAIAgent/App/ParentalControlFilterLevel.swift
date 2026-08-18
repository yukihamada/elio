
import Foundation
import SwiftUI

enum ParentalControlFilterLevel: String, Codable, CaseIterable, Identifiable {
    case strict = "strict"
    case moderate = "moderate"
    case lenient = "lenient"

    var id: String { self.rawValue }
    var localizedName: String {
        switch self {
        case .strict: return String(localized: "parental.filter_level.strict")
        case .moderate: return String(localized: "parental.filter_level.moderate")
        case .lenient: return String(localized: "parental.filter_level.lenient")
        }
    }
}
