//
//  EQModels.swift
//  QQPlayer
//
//  EQ helper types: Double rounding extension and EQError
//

import Foundation

// Helper extension for rounding doubles
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - Errors

enum EQError: Error, LocalizedError {
    case cannotDeleteBuiltInPreset
    case invalidImportData
    case invalidGraphicEQFormat
    case presetNotFound

    var errorDescription: String? {
        switch self {
        case .cannotDeleteBuiltInPreset:
            return "Cannot delete built-in presets"
        case .invalidImportData:
            return "Invalid preset import data"
        case .invalidGraphicEQFormat:
            return "Invalid GraphicEQ format. Expected format: 'GraphicEQ: freq1 gain1; freq2 gain2; ...'"
        case .presetNotFound:
            return "Preset not found"
        }
    }
}
