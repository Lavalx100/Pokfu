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

enum PokfuBrand {
    static let name = "Pokfu"
    static let bundleID = "com.pokfu.app"
    static let appGroup = "group.com.pokfu.app"
    static let urlScheme = "pokfu"
    static let legacyURLScheme = "cuckoo"
    static let moodleDomain = "moodle.hku.hk"
    static let upstreamURL = URL(string: "https://github.com/thermitex/cuckoo-flutter")!
    static let privacyURL = URL(string: "https://pokfu.netlify.app/")!
    static let contactEmail = "jad.kh1@outlook.com"
    static let contactURL = URL(string: "mailto:\(contactEmail)")!
}

enum SettingKey {
    static let deadlineDisplay = "settings_deadline_display"
    static let eventGrouping = "settings_event_grouping"
    static let courseSorting = "settings_course_sorting"
    static let courseFiltering = "settings_course_filtering"
    static let onlyShowResources = "settings_only_show_resources"
    static let showFavoriteCourses = "settings_show_fav_courses"
    static let calendarFormat = "settings_calendar_format"
    static let syncCompletion = "settings_sync_completion"
    static let greyOutCompleted = "settings_grey_out_completed"
    static let differentiateCustom = "settings_differentiate_custom"
    static let defaultTab = "settings_default_tab"
    static let themeMode = "settings_theme_mode"
    static let openResourceInBrowser = "settings_open_res_in_browser"
    static let showWorkload = "settings_show_wl_indicator"
    static let ignoreCompleted = "settings_reminder_ignore_completed"
    static let ignoreCustom = "settings_reminder_ignore_custom"
    static let showProgress = "settings_progress_indicator"
    static let autoPinEvent = "settings_auto_pin_event"
}

enum MoodleStorageKey {
    static let wsToken = "moodle_wstoken"
    static let privateToken = "moodle_privatetoken"
    static let autoLoginInfo = "moodle_autologininfo"
    static let siteInfo = "moodle_site_info"
    static let courses = "moodle_courses"
    static let events = "moodle_events"
    static let reminders = "event_reminders"
    static let colorMapping = "color_registry_mapping"
}

enum MoodleFunction {
    static let siteInfo = "core_webservice_get_site_info"
    static let enrolledCourses = "core_enrol_get_users_courses"
    static let external = "tool_mobile_call_external_functions"
    static let calendarEvents = "core_calendar_get_calendar_events"
    static let eventByID = "core_calendar_get_calendar_event_by_id"
    static let completionStatus = "core_completion_get_activities_completion_status"
    static let autoLoginKey = "tool_mobile_get_autologin_key"
    static let updateCompletion = "core_completion_update_activity_completion_status_manually"
    static let courseContents = "core_course_get_contents"
    static let recordCourseView = "core_course_view_course"
    static let grades = "gradereport_user_get_grades_table"
    static let searchResults = "core_search_get_results"
}

enum MoodleServiceError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)
    case authentication
    case noDownloadURL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Connect to Moodle to continue."
        case .invalidResponse: return "Moodle returned an unexpected response."
        case .server(let message): return message
        case .authentication: return "Moodle authentication was not completed."
        case .noDownloadURL: return "This resource cannot be downloaded."
        }
    }
}

final class KeychainStore {
    private let service: String

    init(service: String = PokfuBrand.bundleID) {
        self.service = service
    }

    func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class PersistenceStore {
    let defaults: UserDefaults
    let keychain: KeychainStore
    let applicationSupport: URL

    init(
        applicationSupportDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        let base = applicationSupportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pokfu", isDirectory: true)
        applicationSupport = base
        try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        migrateLegacySecrets()
        migrateLegacyCaches()
        loadCourseColors()
    }

    private func migrateLegacySecrets() {
        for key in [MoodleStorageKey.wsToken, MoodleStorageKey.privateToken] where keychain.get(key) == nil {
            if let value = defaults.string(forKey: key) {
                keychain.set(value, for: key)
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func cacheURL(for key: String) -> URL {
        applicationSupport.appendingPathComponent("\(key).json")
    }

    private func migrateLegacyCaches() {
        for key in [MoodleStorageKey.autoLoginInfo, MoodleStorageKey.siteInfo, MoodleStorageKey.courses, MoodleStorageKey.events, MoodleStorageKey.reminders] {
            let destination = cacheURL(for: key)
            guard !FileManager.default.fileExists(atPath: destination.path), let legacy = defaults.object(forKey: key) else { continue }
            let data: Data?
            if let string = legacy as? String { data = string.data(using: .utf8) }
            else if let strings = legacy as? [String] {
                let objects = strings.compactMap { string -> Any? in
                    guard let value = string.data(using: .utf8) else { return nil }
                    return try? JSONSerialization.jsonObject(with: value)
                }
                data = try? JSONSerialization.data(withJSONObject: objects)
            }
            else { data = nil }
            if let data { try? data.write(to: destination, options: .atomic) }
        }
    }

    private func loadCourseColors() {
        guard let data = defaults.string(forKey: MoodleStorageKey.colorMapping)?.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else { return }
        CourseColorRegistry.mapping = map
    }

    func loadString(_ key: String) -> String? { defaults.string(forKey: key) }

    func loadStringList(_ key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func loadJSON<T: Decodable>(_ type: T.Type, from key: String) -> T? {
        if let data = try? Data(contentsOf: cacheURL(for: key)), let value = try? JSONDecoder().decode(type, from: data) { return value }
        guard let string = defaults.string(forKey: key), let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func loadStringListJSON<T: Decodable>(_ type: T.Type, from key: String) -> [T] {
        if let data = try? Data(contentsOf: cacheURL(for: key)), let values = try? JSONDecoder().decode([T].self, from: data) { return values }
        return loadStringList(key).compactMap { string in
            guard let data = string.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }

    func save<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: cacheURL(for: key), options: .atomic)
    }

    func saveStringListJSON<T: Encodable>(_ values: [T], for key: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: cacheURL(for: key), options: .atomic)
    }

    func removeCache(for key: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: key))
    }

    func saveCourseColors() {
        guard let data = try? JSONSerialization.data(withJSONObject: CourseColorRegistry.mapping),
              let string = String(data: data, encoding: .utf8) else { return }
        defaults.set(string, forKey: MoodleStorageKey.colorMapping)
    }

    func clearCachedFiles() {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pokfu", isDirectory: true)
        try? FileManager.default.removeItem(at: cache)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    }
}
