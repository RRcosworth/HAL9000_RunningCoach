import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case training
    case analysis
    case raceLog
    case coach
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:    return "Today"
        case .training: return "Training"
        case .analysis: return "Analysis"
        case .raceLog:  return "Race Log"
        case .coach:    return "Coach"
        case .profile:  return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .training: return "figure.run"
        case .analysis: return "chart.line.uptrend.xyaxis"
        case .raceLog:  return "flag.checkered"
        case .coach:    return "message.fill"
        case .profile:  return "person.circle.fill"
        }
    }
}
