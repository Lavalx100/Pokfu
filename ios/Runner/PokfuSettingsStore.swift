import ActivityKit
import AuthenticationServices
import Combine
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import PDFKit
import Security
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var values: [String: Any] = [:]
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        for key in [SettingKey.deadlineDisplay, SettingKey.eventGrouping, SettingKey.courseSorting, SettingKey.courseFiltering, SettingKey.calendarFormat, SettingKey.defaultTab, SettingKey.themeMode] {
            if let value = persistence.defaults.object(forKey: key) { values[key] = value }
        }
        for key in [SettingKey.onlyShowResources, SettingKey.showFavoriteCourses, SettingKey.syncCompletion, SettingKey.greyOutCompleted, SettingKey.differentiateCustom, SettingKey.openResourceInBrowser, SettingKey.showWorkload, SettingKey.ignoreCompleted, SettingKey.ignoreCustom, SettingKey.showProgress, SettingKey.autoPinEvent] {
            if let value = persistence.defaults.object(forKey: key) { values[key] = value }
        }
    }

    func int(_ key: String, default defaultValue: Int = 0) -> Int { (values[key] as? Int) ?? (persistence.defaults.object(forKey: key) as? Int) ?? defaultValue }
    func bool(_ key: String, default defaultValue: Bool = false) -> Bool { (values[key] as? Bool) ?? (persistence.defaults.object(forKey: key) as? Bool) ?? defaultValue }
    func set(_ key: String, _ value: Any) {
        values[key] = value
        persistence.defaults.set(value, forKey: key)
    }

    var theme: ColorScheme? {
        switch int(SettingKey.themeMode) {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}
