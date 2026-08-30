//
//  CloudDownloadError.swift
//  QQPlayer
//
//  Errors for CloudDownloadManager iCloud downloads
//

import Foundation

enum CloudDownloadError: Error {
    case fileNotFound
    case downloadFailed
    case hasConflicts
    case iCloudNotAvailable
    case authenticationRequired
    case accessDenied
}
