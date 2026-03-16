//  AppearanceSettings.swift
//  Pique
//
//  Shared between the main app and the QuickLook extension via an App Group.

import Foundation

/// The appearance to use when rendering a preview.
enum AppearanceOverride: String, CaseIterable {
    case system   // follow macOS system appearance (default)
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

enum AppearanceSettings {
    static let appGroupID = "group.io.macadmins.pique"
    private static let key = "appearanceOverrides"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Returns the stored appearance override for a file extension, defaulting to `.system`.
    static func override(for ext: String) -> AppearanceOverride {
        let raw = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        guard let value = raw[ext.lowercased()],
              let override = AppearanceOverride(rawValue: value) else {
            return .system
        }
        return override
    }

    /// Persists an appearance override for a file extension.
    /// Setting `.system` removes the entry entirely (returns to default behaviour).
    static func setOverride(_ value: AppearanceOverride, for ext: String) {
        var raw = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        if value == .system {
            raw.removeValue(forKey: ext.lowercased())
        } else {
            raw[ext.lowercased()] = value.rawValue
        }
        defaults.set(raw, forKey: key)
    }
}
