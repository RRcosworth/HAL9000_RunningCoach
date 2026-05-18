import Foundation

enum HealthAuthorizationState: Equatable {
    case unavailable
    case notDetermined
    case sharingDenied
    case authorized
}
