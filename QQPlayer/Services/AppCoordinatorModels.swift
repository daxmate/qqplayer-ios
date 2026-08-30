//
//  AppCoordinatorModels.swift
//  QQPlayer
//
//  AppCoordinator 配套顶层类型：Dictionary 工具扩展、iCloud 状态枚举、
//  协调器错误枚举。
//

extension Dictionary {
    func compactMapKeys<T>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let transformedKey = try transform(key) {
                result[transformedKey] = value
            }
        }
        return result
    }
}

enum iCloudStatus: Equatable {
    case available
    case notSignedIn
    case containerUnavailable
    case offline
    case authenticationRequired
    case error(Error)

    static func == (lhs: iCloudStatus, rhs: iCloudStatus) -> Bool {
        switch (lhs, rhs) {
        case (.available, .available),
             (.notSignedIn, .notSignedIn),
             (.containerUnavailable, .containerUnavailable),
             (.offline, .offline),
             (.authenticationRequired, .authenticationRequired):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

enum AppCoordinatorError: Error {
    case iCloudNotAvailable
    case iCloudNotSignedIn
    case iCloudContainerInaccessible
    case databaseError
    case indexingError
    case playlistNotFound

    var localizedDescription: String {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Drive is not available on this device."
        case .iCloudNotSignedIn:
            return "Please sign in to iCloud to use this app. Go to Settings > [Your Name] > iCloud and enable iCloud Drive."
        case .iCloudContainerInaccessible:
            return "Cannot access iCloud Drive. Please check your internet connection and iCloud Drive settings."
        case .databaseError:
            return "Database error occurred."
        case .indexingError:
            return "Error indexing music library."
        case .playlistNotFound:
            return "Playlist not found."
        }
    }
}
