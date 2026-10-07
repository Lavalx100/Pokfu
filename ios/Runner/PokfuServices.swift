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

enum AIProviderError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case invalidResponse
    case emptyResponse
    case requestFailed(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Connect an AI provider in Settings → AI Providers first."
        case .invalidEndpoint:
            return "The AI endpoint is not a valid HTTPS URL."
        case .invalidResponse:
            return "The AI provider returned an unexpected response."
        case .emptyResponse:
            return "The AI provider returned an empty response."
        case .requestFailed(let message):
            return message
        case .httpStatus(let status, let message):
            return "AI provider returned HTTP \(status): \(message)"
        }
    }
}

struct AIProviderClient {
    static func normalizedEndpoint(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            throw AIProviderError.invalidEndpoint
        }

        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") {
            if !path.isEmpty { path += "/" }
            path += "chat/completions"
        }
        components.path = "/" + path
        guard let url = components.url else { throw AIProviderError.invalidEndpoint }
        return url
    }

    static func complete(
        provider: AIProviderKind,
        configuration: AIProviderConfiguration,
        apiKey: String,
        context: String,
        session: URLSession = .shared
    ) async throws -> String {
        let url = try normalizedEndpoint(configuration.endpoint)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw AIProviderError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        if provider == .openRouter {
            request.setValue(PokfuBrand.privacyURL.absoluteString, forHTTPHeaderField: "HTTP-Referer")
            request.setValue(PokfuBrand.name, forHTTPHeaderField: "X-Title")
        }

        let body: [String: Any] = [
            "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": [
                [
                    "role": "system",
                    "content": "You are Pokfu's Moodle study tutor. Use only the Moodle context supplied by the app. Teach the student with concise explanations, worked examples, hints, and questions. Do not claim to submit work, change grades, or perform actions that were not completed. If the context does not contain the answer, say so clearly."
                ],
                ["role": "user", "content": context]
            ],
            "stream": false,
            "max_tokens": 1400
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw AIProviderError.httpStatus(http.statusCode, errorMessage(from: data) ?? "The request was rejected.")
            }
            return try responseText(from: data)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.requestFailed(error.localizedDescription)
        }
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = dictionary["error"] as? [String: Any] {
            return text(from: error["message"]) ?? text(from: error["code"])
        }
        return text(from: dictionary["message"])
    }

    static func responseText(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let choices = dictionary["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = text(from: message["content"]),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func text(from value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let values = value as? [Any] {
            return values.compactMap { item -> String? in
                if let dictionary = item as? [String: Any] {
                    return text(from: dictionary["text"] ?? dictionary["content"] ?? dictionary["value"])
                }
                return text(from: item)
            }.joined()
        }
        if let dictionary = value as? [String: Any] {
            return text(from: dictionary["text"] ?? dictionary["content"] ?? dictionary["value"] ?? dictionary["message"])
        }
        return nil
    }
}

@MainActor
final class AIProviderStore: ObservableObject {
    @Published private(set) var configurations: [AIProviderKind: AIProviderConfiguration] = [:]
    @Published private(set) var activeProvider: AIProviderKind?
    @Published private(set) var workingProvider: AIProviderKind?

    private let persistence: PersistenceStore
    private let keychain: KeychainStore
    private let configurationKey = "ai_provider_configurations_v1"
    private let activeProviderKey = "ai_active_provider"

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.keychain = persistence.keychain
        load()
    }

    var configuredProviders: [AIProviderKind] {
        AIProviderKind.allCases.filter { isConfigured($0) }
    }

    var activeProviderName: String? { activeProvider?.name }

    func configuration(for provider: AIProviderKind) -> AIProviderConfiguration {
        configurations[provider] ?? AIProviderConfiguration(endpoint: provider.defaultEndpoint, model: provider.defaultModel)
    }

    func apiKey(for provider: AIProviderKind) -> String? {
        keychain.get(keychainKey(for: provider))
    }

    func isConfigured(_ provider: AIProviderKind) -> Bool {
        configuration(for: provider).enabled && !(apiKey(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func save(provider: AIProviderKind, endpoint: String, model: String, apiKey: String) throws {
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.notConfigured
        }
        _ = try AIProviderClient.normalizedEndpoint(endpoint)
        configurations[provider] = AIProviderConfiguration(endpoint: endpoint, model: model, enabled: true)
        keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: keychainKey(for: provider))
        persistConfigurations()
        if activeProvider == nil || !isConfigured(activeProvider!) {
            activeProvider = provider
            persistActiveProvider()
        }
    }

    func disconnect(_ provider: AIProviderKind) {
        keychain.delete(keychainKey(for: provider))
        configurations.removeValue(forKey: provider)
        persistConfigurations()
        if activeProvider == provider {
            activeProvider = configuredProviders.first
            persistActiveProvider()
        }
    }

    func select(_ provider: AIProviderKind?) {
        guard let provider else {
            activeProvider = nil
            persistActiveProvider()
            return
        }
        guard isConfigured(provider) else { return }
        activeProvider = provider
        persistActiveProvider()
    }

    func complete(context: String) async throws -> String {
        guard let provider = activeProvider,
              let configuration = configurations[provider],
              isConfigured(provider),
              let key = apiKey(for: provider) else {
            throw AIProviderError.notConfigured
        }
        workingProvider = provider
        defer { workingProvider = nil }
        return try await AIProviderClient.complete(provider: provider, configuration: configuration, apiKey: key, context: context)
    }

    func test(provider: AIProviderKind) async throws {
        guard let configuration = configurations[provider],
              let key = apiKey(for: provider),
              isConfigured(provider) else { throw AIProviderError.notConfigured }
        workingProvider = provider
        defer { workingProvider = nil }
        _ = try await AIProviderClient.complete(
            provider: provider,
            configuration: configuration,
            apiKey: key,
            context: "Reply with exactly: Pokfu connection successful."
        )
    }

    private func load() {
        if let data = persistence.defaults.data(forKey: configurationKey),
           let stored = try? JSONDecoder().decode([String: AIProviderConfiguration].self, from: data) {
            configurations = stored.reduce(into: [:]) { result, item in
                if let provider = AIProviderKind(rawValue: item.key) { result[provider] = item.value }
            }
        }
        if let raw = persistence.defaults.string(forKey: activeProviderKey),
           let provider = AIProviderKind(rawValue: raw),
           isConfigured(provider) {
            activeProvider = provider
        } else {
            activeProvider = configuredProviders.first
        }
    }

    private func persistConfigurations() {
        let values = configurations.reduce(into: [String: AIProviderConfiguration]()) { result, item in
            result[item.key.rawValue] = item.value
        }
        if let data = try? JSONEncoder().encode(values) {
            persistence.defaults.set(data, forKey: configurationKey)
        }
    }

    private func persistActiveProvider() {
        if let activeProvider { persistence.defaults.set(activeProvider.rawValue, forKey: activeProviderKey) }
        else { persistence.defaults.removeObject(forKey: activeProviderKey) }
    }

    private func keychainKey(for provider: AIProviderKind) -> String {
        "ai_api_key_(provider.rawValue)"
    }
}

struct MoodleSubrequest {
    let function: String
    let params: [String: Any]
}

final class MoodleAPIClient {
    let domain: String
    var wsToken: String?
    var privateToken: String?
    var siteInfo: MoodleSiteInfo?

    init(domain: String = PokfuBrand.moodleDomain) {
        self.domain = domain
    }

    var isAuthenticated: Bool { wsToken != nil }

    var authURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/admin/tool/mobile/launch.php"
        components.queryItems = [
            URLQueryItem(name: "service", value: "moodle_mobile_app"),
            URLQueryItem(name: "passport", value: "100"),
            URLQueryItem(name: "urlscheme", value: PokfuBrand.urlScheme)
        ]
        return components.url!
    }

    func handleAuthToken(_ raw: String) throws -> (String, String?) {
        // Moodle redirects to `<scheme>://token=<base64 payload>`. On iOS,
        // URL.query is nil for that form because `token=...` is parsed as the
        // host, so accept the complete callback URL as well as the legacy
        // `token=...` payload passed by the legacy Cuckoo client.
        var payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: payload),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            payload = "token=\(token)"
        } else if let schemeRange = payload.range(of: "://") {
            payload = String(payload[schemeRange.upperBound...])
            while payload.hasPrefix("/") { payload.removeFirst() }
        }
        payload = payload.removingPercentEncoding ?? payload
        guard payload.hasPrefix("token") else { throw MoodleServiceError.authentication }
        var token = payload.components(separatedBy: "token=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? payload
        if token.count > 180, token.hasSuffix("#") { token.removeLast() }
        guard let decoded = Data(base64Encoded: token), let string = String(data: decoded, encoding: .utf8) else {
            throw MoodleServiceError.authentication
        }
        let values = string.components(separatedBy: ":::")
        guard values.count >= 2, !values[1].isEmpty else { throw MoodleServiceError.authentication }
        return (values[1], values.count == 3 ? values[2] : nil)
    }

    func fetchSiteInfo() async throws -> MoodleSiteInfo {
        let object = try await call(function: MoodleFunction.siteInfo)
        return try decode(MoodleSiteInfo.self, object: object)
    }

    func fetchCourses(userID: Int) async throws -> [MoodleCourse] {
        let object = try await call(function: MoodleFunction.enrolledCourses, params: ["userid": userID, "returnusercount": 0])
        return try decode([MoodleCourse].self, object: object)
    }

    func fetchEvents(courseIDs: [Int]) async throws -> [MoodleEvent] {
        let start = Int(Date().timeIntervalSince1970)
        let options: [String: Any] = ["userevents": "1", "siteevents": "1", "timestart": "\(start)", "timeend": "0"]
        let object = try await callExternal(subrequests: [MoodleSubrequest(function: MoodleFunction.calendarEvents, params: ["options": options, "events": ["courseids": courseIDs]])])
        guard let response = object["responses"] as? [[String: Any]], let raw = response.first?["data"] as? String,
              let data = raw.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] else { throw MoodleServiceError.invalidResponse }
        return try decode([MoodleEvent].self, object: events)
    }

    func fetchCourseContents(courseID: Int) async throws -> [MoodleCourseSection] {
        let options: [[String: String]] = [
            ["name": "excludemodules", "value": "0"],
            ["name": "excludecontents", "value": "0"],
            ["name": "includestealthmodules", "value": "1"]
        ]
        let object = try await callExternal(subrequests: [
            MoodleSubrequest(function: MoodleFunction.courseContents, params: ["courseid": courseID, "options": options])
        ])
        let payload = try externalResponsePayload(named: MoodleFunction.courseContents, from: object)
        guard let json = payload as? [[String: Any]] else { throw MoodleServiceError.invalidResponse }
        return try decode([MoodleCourseSection].self, object: json)
    }

    func fetchGrades(courseID: Int, userID: Int) async throws -> [MoodleCourseGrade] {
        let object = try await call(function: MoodleFunction.grades, params: ["courseid": courseID, "userid": userID])
        guard let tables = object as? [String: Any],
              let list = tables["tables"] as? [Any],
              let firstTable = list.first as? [String: Any],
              let data = firstTable["tabledata"] as? [Any] else { return [] }
        return data.compactMap { row in
            guard let row = row as? [String: Any] else { return nil }
            return try? decode(MoodleCourseGrade.self, object: row)
        }
    }

    func fetchSearchResults(query: String, courseIDs: [Int] = [], page: Int = 0) async throws -> [MoodleSearchResult] {
        var params: [String: Any] = [
            "query": query,
            "page": page,
            "filters[mycoursesonly]": 1,
            "filters[order]": "relevance"
        ]
        for (index, courseID) in courseIDs.enumerated() {
            params["filters[courseids][\(index)]"] = courseID
        }
        let object = try await call(function: MoodleFunction.searchResults, params: params)
        guard let dictionary = object as? [String: Any],
              let rawResults = dictionary["results"] else {
            throw MoodleServiceError.invalidResponse
        }
        return try decode([MoodleSearchResult].self, object: rawResults)
    }

    func updateCompletion(cmid: Int, completed: Bool) async throws {
        _ = try await callExternal(subrequests: [MoodleSubrequest(function: MoodleFunction.updateCompletion, params: ["cmid": cmid, "completed": completed])])
    }

    func updateAutoLoginKey() async throws -> MoodleAutoLoginInfo {
        guard let privateToken else { throw MoodleServiceError.notAuthenticated }
        let object = try await call(function: MoodleFunction.autoLoginKey, params: ["privatetoken": privateToken])
        guard let dictionary = object as? [String: Any], let key = dictionary["key"] as? String else { throw MoodleServiceError.invalidResponse }
        return MoodleAutoLoginInfo(key: key, lastRequested: Date().epoch)
    }

    func buildAutoLoginURL(for url: String, userID: Int, key: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/admin/tool/mobile/autologin.php"
        components.queryItems = [
            URLQueryItem(name: "userid", value: "\(userID)"),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "urltogo", value: url)
        ]
        return components.url
    }

    func authenticatedFileURL(for module: MoodleCourseModule) -> URL? {
        guard let raw = module.fileURL?.absoluteString,
              let privateToken,
              let siteKey = siteInfo?.userprivateaccesskey,
              var components = URLComponents(string: raw) else { return nil }
        let path = components.path.split(separator: "/").map(String.init)
        guard let pluginIndex = path.firstIndex(where: { $0 == "pluginfile.php" }) else { return nil }
        // Moodle returns either `/pluginfile.php/<context>/...` or
        // `/webservice/pluginfile.php/<temporary-token>/<context>/...`.
        // `tokenpluginfile.php` needs the private access key and, for the
        // webservice form, the temporary token must be removed.
        let hasWebServicePrefix = pluginIndex > 0 && path[pluginIndex - 1] == "webservice"
        var remainder = Array(path.dropFirst(pluginIndex + 1))
        if hasWebServicePrefix, !remainder.isEmpty { remainder.removeFirst() }
        components.path = "/" + (["tokenpluginfile.php", siteKey] + remainder).joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "forcedownload", value: "1"), URLQueryItem(name: "offline", value: "1"), URLQueryItem(name: "token", value: privateToken)]
        return components.url
    }

    func download(module: MoodleCourseModule, to directory: URL) async throws -> URL {
        guard let url = authenticatedFileURL(for: module) ?? module.fileURL else { throw MoodleServiceError.noDownloadURL }
        let destination = directory.appendingPathComponent(module.fileName ?? "download")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MoodleServiceError.invalidResponse }
        if module.fileExtension == "pdf",
           let preview = String(data: data.prefix(512), encoding: .utf8)?.lowercased(),
           preview.contains("<html") || preview.contains("<!doctype") {
            throw MoodleServiceError.invalidResponse
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func call(function: String, params: [String: Any] = [:]) async throws -> Any {
        var all = params
        all["moodlewssettinglang"] = "en_us"
        all["wsfunction"] = function
        all["wstoken"] = wsToken ?? ""
        return try await send(all)
    }

    private func callExternal(subrequests: [MoodleSubrequest]) async throws -> [String: Any] {
        var params: [String: Any] = ["moodlewssettinglang": "en_us", "wsfunction": MoodleFunction.external, "wstoken": wsToken ?? ""]
        for (index, request) in subrequests.enumerated() {
            params["requests[\(index)][function]"] = request.function
            params["requests[\(index)][arguments]"] = try jsonString(request.params)
            params["requests[\(index)][settingfilter]"] = "1"
            params["requests[\(index)][settingfileurl]"] = "1"
        }
        guard let object = try await send(params) as? [String: Any] else { throw MoodleServiceError.invalidResponse }
        return object
    }

    private func externalResponsePayload(named function: String, from object: [String: Any]) throws -> Any {
        guard let responses = object["responses"] as? [[String: Any]] else {
            throw MoodleServiceError.invalidResponse
        }
        guard let response = responses.first(where: { $0["function"] as? String == function }) ?? responses.first,
              let raw = response["data"] else {
            throw MoodleServiceError.invalidResponse
        }
        if let string = raw as? String {
            guard let data = string.data(using: .utf8) else { throw MoodleServiceError.invalidResponse }
            return try JSONSerialization.jsonObject(with: data, options: [])
        }
        return raw
    }

    private func send(_ parameters: [String: Any]) async throws -> Any {
        guard wsToken != nil else { throw MoodleServiceError.notAuthenticated }
        let url = URL(string: "https://\(domain)/webservice/rest/server.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("moodleappfs://localhost", forHTTPHeaderField: "Origin")
        request.setValue("MoodleMobile 4.3.0 (43001)", forHTTPHeaderField: "User-Agent")
        var requestParameters = parameters
        // Moodle's REST endpoint defaults successful responses to XML. The
        // native client decodes JSON, so this must be sent with every request.
        requestParameters["moodlewsrestformat"] = "json"
        request.httpBody = requestParameters.map { key, value in
            let string: String
            if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) {
                string = json
            } else {
                string = String(describing: value)
            }
            return "\(formEncode(key))=\(formEncode(string))"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw MoodleServiceError.server("Moodle could not complete the request.") }
        let object = try JSONSerialization.jsonObject(with: data)
        if let dictionary = object as? [String: Any], dictionary["exception"] as? String == "moodle_exception" {
            throw MoodleServiceError.server(dictionary["message"] as? String ?? "Moodle returned an error.")
        }
        return object
    }

    private func decode<T: Decodable>(_ type: T.Type, object: Any) throws -> T {
        guard JSONSerialization.isValidJSONObject(object) else { throw MoodleServiceError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(type, from: data)
    }

    private func jsonString(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(decoding: data, as: UTF8.self)
    }

    private func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? value
    }
}

final class MoodleAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL, completion: @escaping (String?) -> Void) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: PokfuBrand.urlScheme) { [weak self] callback, _ in
            self?.session = nil
            // The Moodle callback is `pokfu://token=...`, not a query URL.
            // Passing the absolute URL preserves the token payload exactly;
            // MoodleAPIClient.handleAuthToken normalizes both callback forms.
            completion(callback?.absoluteString)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}

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

@MainActor
final class MoodleStore: ObservableObject {
    @Published private(set) var siteInfo: MoodleSiteInfo?
    @Published private(set) var courses: [MoodleCourse] = []
    @Published private(set) var events: [MoodleEvent] = []
    @Published private(set) var status: MoodleManagerStatus = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoggedIn = false

    let api: MoodleAPIClient
    let persistence: PersistenceStore
    let settings: SettingsStore
    private let auth = MoodleAuthCoordinator()
    private var lastEventFetch: Date?

    init(persistence: PersistenceStore, settings: SettingsStore) {
        self.persistence = persistence
        self.settings = settings
        self.api = MoodleAPIClient()
        api.wsToken = persistence.keychain.get(MoodleStorageKey.wsToken) ?? persistence.loadString(MoodleStorageKey.wsToken)
        api.privateToken = persistence.keychain.get(MoodleStorageKey.privateToken) ?? persistence.loadString(MoodleStorageKey.privateToken)
        siteInfo = persistence.loadJSON(MoodleSiteInfo.self, from: MoodleStorageKey.siteInfo)
        api.siteInfo = siteInfo
        courses = persistence.loadStringListJSON(MoodleCourse.self, from: MoodleStorageKey.courses)
        events = persistence.loadStringListJSON(MoodleEvent.self, from: MoodleStorageKey.events)
        isLoggedIn = api.isAuthenticated
    }

    func bootstrap() {
        guard isLoggedIn else { return }
        Task { await refresh(forceEvents: false) }
    }

    func startAuthentication() {
        auth.start(url: api.authURL) { [weak self] raw in
            guard let raw else { return }
            Task { @MainActor in await self?.finishAuthentication(raw) }
        }
    }

    func clearError() { errorMessage = nil }

    func finishAuthentication(_ raw: String) async {
        do {
            let (token, privateToken) = try api.handleAuthToken(raw)
            guard token != api.wsToken else { return }
            guard let privateToken else { throw MoodleServiceError.authentication }
            api.wsToken = token
            api.privateToken = privateToken
            siteInfo = try await api.fetchSiteInfo()
            api.siteInfo = siteInfo
            guard let userID = siteInfo?.userid else { throw MoodleServiceError.invalidResponse }
            courses = try await api.fetchCourses(userID: userID)
            events = mergeFetchedEvents(try await api.fetchEvents(courseIDs: courses.map(\.id)))
            saveAll()
            isLoggedIn = true
            errorMessage = nil
        } catch {
            api.wsToken = nil
            api.privateToken = nil
            errorMessage = error.localizedDescription
        }
    }

    func refresh(forceEvents: Bool = true) async {
        guard isLoggedIn, let userID = siteInfo?.userid ?? persistence.loadJSON(MoodleSiteInfo.self, from: MoodleStorageKey.siteInfo)?.userid else { return }
        status = .updating
        do {
            if siteInfo == nil { siteInfo = try await api.fetchSiteInfo() }
            courses = try await api.fetchCourses(userID: userID)
            if forceEvents || lastEventFetch == nil || Date().timeIntervalSince(lastEventFetch!) > 7200 {
                events = mergeFetchedEvents(try await api.fetchEvents(courseIDs: courses.map(\.id)))
                lastEventFetch = Date()
            }
            saveAll()
            status = .idle
            errorMessage = nil
        } catch {
            status = .error
            errorMessage = error.localizedDescription
        }
    }

    func groupedEvents() -> [(String, [MoodleEvent])] {
        let grouping = EventGrouping(rawValue: settings.int(SettingKey.eventGrouping)) ?? .time
        var filtered = events.filter { !$0.expired && !$0.isArchived }
        filtered.sort {
            if grouping == .course {
                let lhs = course(for: $0)?.fullname ?? "z"
                let rhs = course(for: $1)?.fullname ?? "z"
                return lhs < rhs
            }
            return $0.time < $1.time
        }
        switch grouping {
        case .none: return [("ALL EVENTS", filtered)]
        case .course: return Dictionary(grouping: filtered) { course(for: $0)?.courseCode ?? "OTHERS" }.sorted { $0.key < $1.key }
        case .time:
            let groups = Dictionary(grouping: filtered) { event in
                let remaining = event.remainingTime
                if remaining < 7 * 86400 { return "WITHIN A WEEK" }
                if remaining < 30 * 86400 { return "WITHIN A MONTH" }
                return "AFTER A MONTH"
            }
            return ["WITHIN A WEEK", "WITHIN A MONTH", "AFTER A MONTH"].compactMap { key in groups[key].map { (key, $0) } }
        }
    }

    func course(for event: MoodleEvent) -> MoodleCourse? { courses.first { $0.id == event.courseid } }
    var archivedEvents: [MoodleEvent] { events.filter(\.isArchived).sorted { $0.time > $1.time } }
    func events(on date: Date) -> [MoodleEvent] { events.filter { !$0.isArchived && Calendar.current.isDate($0.time, inSameDayAs: date) } }

    func workload(on date: Date) -> Double {
        events.reduce(0) { total, event in
            let days = Calendar.current.dateComponents([.day], from: date.startOfDay, to: event.time.startOfDay).day ?? 0
            guard days >= 0, days <= 60, !event.isCompleted, !event.isArchived else { return total }
            return min(4, total + 0.2 * (1 / Double(days + 1)) + 0.8 * Double(30 - days) / 30)
        }
    }

    func toggleCompletion(_ event: MoodleEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updatedEvent = events[index]
        updatedEvent.completed = !event.isCompleted
        events = events.map { $0.id == updatedEvent.id ? updatedEvent : $0 }
        saveEvents()
        if settings.bool(SettingKey.syncCompletion, default: true), let cmid = event.cmid {
            Task {
                try? await api.updateCompletion(cmid: cmid, completed: events[index].completed ?? false)
            }
        }
    }

    func mergeFetchedEvents(_ fetched: [MoodleEvent]) -> [MoodleEvent] {
        let previousByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        var refreshed = fetched.map { event in
            var event = event
            if let previous = previousByID[event.id] {
                // Completion and archive state are local user actions. Moodle
                // can lag behind the UI action, so a refresh must not erase a
                // state that was already saved on this device.
                event.completed = previous.completed ?? event.completed
                event.archived = previous.archived ?? event.archived
            }
            return event
        }
        let fetchedIDs = Set(fetched.map(\.id))
        refreshed.append(contentsOf: events.filter { $0.isCustom && !fetchedIDs.contains($0.id) })
        return refreshed
    }

    func setArchived(_ event: MoodleEvent, archived: Bool) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updatedEvent = events[index]
        updatedEvent.archived = archived
        events = events.map { $0.id == updatedEvent.id ? updatedEvent : $0 }
        saveEvents()
    }

    func addCustomEvent(_ event: MoodleEvent) { events.removeAll { $0.id == event.id }; events.append(event); saveEvents() }
    func removeEvent(_ event: MoodleEvent) { events.removeAll { $0.id == event.id }; saveEvents() }
    func toggleFavorite(_ course: MoodleCourse) {
        guard courses.contains(where: { $0.id == course.id }) else { return }
        courses = courses.map { value in
            guard value.id == course.id else { return value }
            var updated = value
            updated.customFavorite = !course.isFavorite
            return updated
        }
        persistence.saveStringListJSON(courses, for: MoodleStorageKey.courses)
    }
    func setCourseColor(_ course: MoodleCourse, color: Color?) {
        guard courses.contains(where: { $0.id == course.id }) else { return }
        courses = courses.map { value in
            guard value.id == course.id else { return value }
            var updated = value
            updated.colorHex = color?.hexString
            return updated
        }
        persistence.saveCourseColors()
        persistence.saveStringListJSON(courses, for: MoodleStorageKey.courses)
    }

    func clearCourseCache() {
        courses = courses.map { course in var course = course; course.cachedContents = nil; course.cachedTime = nil; return course }
        persistence.saveStringListJSON(courses, for: MoodleStorageKey.courses)
        persistence.clearCachedFiles()
    }

    func loadContents(for course: MoodleCourse, force: Bool = false) async -> [MoodleCourseSection]? {
        if !force,
           let index = courses.firstIndex(where: { $0.id == course.id }),
           let cached = courses[index].cachedContents,
           let timestamp = courses[index].cachedTime,
           !cached.isEmpty,
           Date().timeIntervalSince1970 - timestamp < 3600 {
            return cached
        }
        for attempt in 0..<2 {
            do {
                let content = try await api.fetchCourseContents(courseID: course.id)
                if !content.isEmpty, courses.contains(where: { $0.id == course.id }) {
                    courses = courses.map { value in
                        guard value.id == course.id else { return value }
                        var updated = value
                        updated.cachedContents = content
                        updated.cachedTime = Date().epoch
                        return updated
                    }
                    persistence.saveStringListJSON(courses, for: MoodleStorageKey.courses)
                }
                return content
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
        return nil
    }

    func loadGrades(for course: MoodleCourse) async throws -> [MoodleCourseGrade] {
        guard let userID = siteInfo?.userid, userID > 0 else {
            throw MoodleServiceError.notAuthenticated
        }
        return try await api.fetchGrades(courseID: course.id, userID: userID)
    }

    func searchAllCourses(query: String, courseID: Int? = nil) async -> [MoodleSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, isLoggedIn else { return [] }

        let courseIDs = courseID.map { [$0] } ?? courses.map(\.id)
        var remoteResults: [MoodleSearchResult] = []
        if let results = try? await api.fetchSearchResults(query: query, courseIDs: courseIDs) {
            remoteResults = results.map { result in
                var result = result
                if result.coursefullname.isEmpty, let course = courses.first(where: { $0.id == result.courseid }) {
                    result.coursefullname = course.fullname
                }
                return result
            }
        }

        let localResults = localSearchResults(query: query, courseID: courseID)
        var merged: [MoodleSearchResult] = []
        var seen = Set<String>()
        for result in remoteResults + localResults {
            let key = result.id.isEmpty
                ? "\(result.courseid)|\(result.displayTitle)|\(result.displayContent.prefix(80))"
                : result.id
            guard seen.insert(key).inserted else { continue }
            merged.append(result)
        }
        return Array(merged.prefix(30))
    }

    func tutorAttachmentCandidates(
        for query: String,
        results: [MoodleSearchResult],
        limit: Int = 4
    ) async -> [MoodleTutorAttachmentCandidate] {
        var likelyCourseIDs = results
            .map(\.courseid)
            .filter { $0 > 0 }
            .reduce(into: [Int]()) { ids, id in
                if !ids.contains(id) { ids.append(id) }
            }
        for result in results where likelyCourseIDs.count < 4 && result.courseid == 0 {
            if let course = courses.first(where: {
                !$0.fullname.isEmpty &&
                (result.coursefullname.localizedCaseInsensitiveContains($0.fullname) ||
                 $0.fullname.localizedCaseInsensitiveContains(result.coursefullname))
            }), !likelyCourseIDs.contains(course.id) {
                likelyCourseIDs.append(course.id)
            }
        }
        likelyCourseIDs = Array(likelyCourseIDs.prefix(4))

        // Search results can identify a course before its contents have been
        // cached. Load only the likely courses, rather than downloading every
        // course just to prepare a share.
        for courseID in likelyCourseIDs {
            if let course = courses.first(where: { $0.id == courseID }),
               course.cachedContents?.isEmpty != false {
                _ = await loadContents(for: course)
            }
        }

        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count > 1 }
        guard !terms.isEmpty else { return [] }

        var candidates: [MoodleTutorAttachmentCandidate] = []
        for course in courses {
            for section in course.cachedContents ?? [] where section.isVisible {
                for module in section.modules where module.uservisible && module.isTutorShareableFile {
                    let fileText = [
                        module.name,
                        module.fileName ?? "",
                        module.description ?? "",
                        section.name,
                        course.fullname
                    ].joined(separator: " ").lowercased()
                    let moduleURL = module.url
                    let resultMatchesModule = results.contains { result in
                        guard result.courseid == course.id else { return false }
                        if let moduleURL, !moduleURL.isEmpty,
                           result.url == moduleURL || result.contexturl == moduleURL {
                            return true
                        }
                        return result.displayTitle.lowercased().contains(module.name.lowercased())
                    }
                    let courseHasResult = results.contains { $0.courseid == course.id }
                    let termScore = terms.reduce(0) { total, term in
                        total
                            + fileText.components(separatedBy: term).count - 1
                            + (module.name.lowercased().contains(term) ? 5 : 0)
                            + ((module.fileName ?? "").lowercased().contains(term) ? 4 : 0)
                    }
                    let score = termScore
                        + (resultMatchesModule ? 12 : 0)
                        + (courseHasResult && resultMatchesModule ? 2 : 0)
                    guard score > 0 else { continue }
                    candidates.append(
                        MoodleTutorAttachmentCandidate(
                            id: "\(course.id)-\(module.id)",
                            module: module,
                            courseName: course.fullname,
                            score: score
                        )
                    )
                }
            }
        }

        return candidates
            .sorted {
                if $0.score == $1.score { return $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map { $0 }
    }

    func prepareTutorAttachments(_ candidates: [MoodleTutorAttachmentCandidate]) async -> [MoodleTutorAttachment] {
        guard !candidates.isEmpty else { return [] }
        let root = persistence.applicationSupport.appendingPathComponent("tutor-attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let maximumFileSize = 20 * 1024 * 1024
        let maximumTotalSize = 40 * 1024 * 1024
        var totalSize = 0
        var attachments: [MoodleTutorAttachment] = []

        for candidate in candidates {
            let directory = root.appendingPathComponent(candidate.id, isDirectory: true)
            let fileURL: URL
            if let existing = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first {
                fileURL = existing
            } else {
                guard let downloaded = try? await api.download(module: candidate.module, to: directory) else { continue }
                fileURL = downloaded
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attributes[.size] as? NSNumber else { continue }
            let size = fileSize.intValue
            guard size > 0, size <= maximumFileSize, totalSize + size <= maximumTotalSize else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            totalSize += size
            attachments.append(
                MoodleTutorAttachment(
                    id: candidate.id,
                    fileName: fileURL.lastPathComponent,
                    courseName: candidate.courseName,
                    fileURL: fileURL
                )
            )
        }
        return attachments
    }

    func contextPack(
        for question: String,
        results: [MoodleSearchResult],
        attachments: [MoodleTutorAttachment] = []
    ) -> String {
        var lines = [
            "Pokfu Moodle context",
            "Student question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))",
            "Use only the supplied Moodle context. Explain concepts and guide the student; do not claim that you submitted work.",
            ""
        ]
        if !attachments.isEmpty {
            lines.append("The share includes the following relevant Moodle files. Use the attached files as primary supporting material:")
            for attachment in attachments {
                lines.append("- \(attachment.fileName) (\(attachment.courseName))")
            }
            var remainingExcerptCharacters = 9_000
            for attachment in attachments where remainingExcerptCharacters > 0 {
                guard let excerpt = attachmentExcerpt(for: attachment), !excerpt.isEmpty else { continue }
                let excerptText = String(excerpt.prefix(min(3_000, remainingExcerptCharacters)))
                lines.append("")
                lines.append("### Extracted text from \(attachment.fileName)")
                lines.append(excerptText)
                remainingExcerptCharacters -= excerptText.count
            }
            lines.append("")
        }
        for (index, result) in results.prefix(8).enumerated() {
            let course = result.courseCode.isEmpty ? result.coursefullname : result.courseCode
            let source = result.url ?? result.contexturl ?? "Moodle"
            let content = String(result.displayContent.prefix(1800))
            lines.append("### Source \(index + 1): \(result.displayTitle)")
            if !course.isEmpty { lines.append("Course: \(course)") }
            lines.append("URL: \(source)")
            if !content.isEmpty { lines.append(content) }
            lines.append("")
        }
        if results.isEmpty {
            lines.append("No matching Moodle material was found. Say so clearly and suggest a narrower search.")
        }
        return lines.joined(separator: "\n")
    }

    private func attachmentExcerpt(for attachment: MoodleTutorAttachment) -> String? {
        let extensionName = attachment.fileURL.pathExtension.lowercased()
        if extensionName == "pdf", let document = PDFDocument(url: attachment.fileURL) {
            return (0..<min(document.pageCount, 8))
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if ["txt", "md", "csv"].contains(extensionName) {
            return try? String(contentsOf: attachment.fileURL, encoding: .utf8)
        }
        return nil
    }

    private func localSearchResults(query: String, courseID: Int?) -> [MoodleSearchResult] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count > 1 }
        guard !terms.isEmpty else { return [] }

        var documents: [MoodleSearchResult] = []
        for course in courses where courseID.map({ course.id == $0 }) ?? true {
            let courseURL = "https://\(api.domain)/course/view.php?id=\(course.id)"
            let courseText = MoodleText.plain([course.fullname, course.summary].joined(separator: " "))
            if !courseText.isEmpty { documents.append(MoodleSearchResult(id: "course-\(course.id)", title: course.fullname, content: courseText, url: courseURL, courseID: course.id, courseName: course.fullname, type: "course")) }
            for section in course.cachedContents ?? [] where section.isVisible {
                let sectionText = MoodleText.plain([section.name, section.summary].joined(separator: " "))
                if !sectionText.isEmpty {
                    documents.append(MoodleSearchResult(id: "section-\(course.id)-\(section.id)", title: section.name.isEmpty ? "Section \(section.section)" : section.name, content: sectionText, url: courseURL, courseID: course.id, courseName: course.fullname, type: "section"))
                }
                for module in section.modules where module.uservisible {
                    let moduleText = MoodleText.plain([module.name, module.description ?? ""].joined(separator: " "))
                    guard !moduleText.isEmpty else { continue }
                    documents.append(MoodleSearchResult(id: "module-\(course.id)-\(module.id)", title: module.name.isEmpty ? "Course material" : module.name, content: moduleText, url: module.url ?? courseURL, courseID: course.id, courseName: course.fullname, type: module.modname ?? "module"))
                }
            }
        }

        func score(_ result: MoodleSearchResult) -> Int {
            let haystack = "\(result.displayTitle) \(result.displayContent)".lowercased()
            return terms.reduce(0) { total, term in
                let occurrences = haystack.components(separatedBy: term).count - 1
                let titleBoost = result.displayTitle.lowercased().contains(term) ? 5 : 0
                return total + occurrences + titleBoost
            }
        }

        return documents
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
            .prefix(30)
            .map { $0 }
    }

    func openMoodleURL(_ raw: String?) async -> URL? {
        guard let raw, let fallback = URL(string: raw) else { return nil }
        guard let userID = siteInfo?.userid, userID > 0 else { return fallback }
        let key: String
        if let saved = persistence.loadJSON(MoodleAutoLoginInfo.self, from: MoodleStorageKey.autoLoginInfo), Date().epoch - saved.lastRequested < 600 { key = saved.key }
        else if let fresh = try? await api.updateAutoLoginKey() { key = fresh.key; persistence.save(fresh, for: MoodleStorageKey.autoLoginInfo) }
        else { return fallback }
        return api.buildAutoLoginURL(for: raw, userID: userID, key: key) ?? fallback
    }

    func materialURL(for module: MoodleCourseModule) async -> URL? {
        if let raw = module.url, !raw.isEmpty {
            return await openMoodleURL(raw)
        }
        return api.authenticatedFileURL(for: module) ?? module.fileURL
    }

    func logout() {
        api.wsToken = nil
        api.privateToken = nil
        siteInfo = nil
        courses = []
        events = events.filter(\.isCustom)
        isLoggedIn = false
        for key in [MoodleStorageKey.siteInfo, MoodleStorageKey.autoLoginInfo, MoodleStorageKey.courses, MoodleStorageKey.events] {
            persistence.defaults.removeObject(forKey: key)
            persistence.removeCache(for: key)
        }
        persistence.saveStringListJSON(events, for: MoodleStorageKey.events)
        persistence.keychain.delete(MoodleStorageKey.wsToken)
        persistence.keychain.delete(MoodleStorageKey.privateToken)
    }

    private func saveAll() {
        if let siteInfo { persistence.save(siteInfo, for: MoodleStorageKey.siteInfo) }
        if let token = api.wsToken { persistence.keychain.set(token, for: MoodleStorageKey.wsToken) }
        if let token = api.privateToken { persistence.keychain.set(token, for: MoodleStorageKey.privateToken) }
        persistence.saveStringListJSON(courses, for: MoodleStorageKey.courses)
        saveEvents()
    }

    private func saveEvents() {
        // Completion and archive changes must be durable before the action
        // returns. An async write can be lost when the user immediately
        // backgrounds or terminates the app.
        persistence.saveStringListJSON(events, for: MoodleStorageKey.events)
        WidgetBridge.shared.update(events: events, courses: courses)
    }
}

enum PokfuAIAvailability {
    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static var label: String {
        appleIntelligenceAvailable ? "On-device Apple Intelligence" : "Share context to your AI app"
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private final class AppleIntelligenceTutor {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: """
        You are Pokfu's Moodle study tutor. Use only the Moodle context included in each request.
        Help the student understand their coursework with concise explanations, worked examples,
        hints, and questions that encourage learning. Never claim to submit assignments, change
        grades, or perform actions that were not actually completed in Pokfu. If the context does
        not contain the answer, say that clearly and suggest a narrower Moodle search.
        """)
    }

    func respond(to prompt: String) async throws -> String {
        try await session.respond(to: prompt).content
    }
}
#endif

@MainActor
final class MoodleTutorViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var messages: [MoodleTutorMessage] = []
    @Published private(set) var results: [MoodleSearchResult] = []
    @Published private(set) var attachments: [MoodleTutorAttachment] = []
    @Published private(set) var shareText = ""
    @Published private(set) var isWorking = false
    @Published private(set) var attachmentMessage: String?
    @Published var errorMessage: String?

    private let moodle: MoodleStore
    private let ai: AIProviderStore

    init(moodle: MoodleStore, ai: AIProviderStore) {
        self.moodle = moodle
        self.ai = ai
    }

    var canShare: Bool { !shareText.isEmpty }
    var shareItems: [Any] {
        var items: [Any] = [shareText]
        items.append(contentsOf: attachments.map { $0.fileURL as Any })
        return items
    }

    func ask() async {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isWorking else { return }

        query = ""
        errorMessage = nil
        isWorking = true
        messages.append(MoodleTutorMessage(role: .user, text: question))

        let found = await moodle.searchAllCourses(query: question)
        results = found
        let candidates = await moodle.tutorAttachmentCandidates(for: question, results: found)
        attachments = await moodle.prepareTutorAttachments(candidates)
        attachmentMessage = attachments.count < candidates.count
            ? "Some relevant Moodle files could not be downloaded. The text context is still ready to share."
            : nil
        let context = moodle.contextPack(for: question, results: found, attachments: attachments)
        shareText = context

        if ai.activeProvider != nil {
            do {
                let response = try await ai.complete(context: context)
                messages.append(MoodleTutorMessage(role: .assistant, text: response))
            } catch {
                errorMessage = error.localizedDescription
                messages.append(MoodleTutorMessage(role: .assistant, text: "The selected AI provider could not answer. Check its endpoint, model, quota, or API key in Settings → AI Providers. Your Moodle context is still ready to share."))
            }
        } else {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
                do {
                    let tutor = AppleIntelligenceTutor()
                    let response = try await tutor.respond(to: context)
                    let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        messages.append(MoodleTutorMessage(role: .assistant, text: text))
                    } else {
                        messages.append(MoodleTutorMessage(role: .assistant, text: "I couldn't generate a response. Try asking a narrower question."))
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    messages.append(MoodleTutorMessage(role: .assistant, text: "Apple Intelligence couldn't answer right now. Your Moodle context is ready to share to another AI app."))
                }
            } else {
                messages.append(fallbackMessage(resultCount: found.count, attachmentCount: attachments.count))
            }
            #else
            messages.append(fallbackMessage(resultCount: found.count, attachmentCount: attachments.count))
            #endif
        }

        isWorking = false
    }

    func clearConversation() {
        messages = []
        results = []
        attachments = []
        shareText = ""
        attachmentMessage = nil
        errorMessage = nil
    }

    private func fallbackMessage(resultCount: Int, attachmentCount: Int) -> MoodleTutorMessage {
        let sourceText = resultCount == 1 ? "one Moodle source" : "\(resultCount) Moodle sources"
        let fileText: String
        if attachmentCount == 1 {
            fileText = " One relevant file is attached."
        } else if attachmentCount > 1 {
            fileText = " \(attachmentCount) relevant files are attached."
        } else {
            fileText = ""
        }
        return MoodleTutorMessage(
            role: .assistant,
            text: "I found \(sourceText).\(fileText) No connected AI provider is available, so use the Share button to send the Moodle context and files to another AI app. You can connect Qwen, GLM, Doubao, DeepSeek, or OpenRouter in Settings → AI Providers."
        )
    }
}

@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [EventReminder] = []
    private let persistence: PersistenceStore
    private let settings: SettingsStore
    private weak var moodle: MoodleStore?

    init(persistence: PersistenceStore, settings: SettingsStore, moodle: MoodleStore) {
        self.persistence = persistence
        self.settings = settings
        self.moodle = moodle
        reminders = persistence.loadStringListJSON(EventReminder.self, from: MoodleStorageKey.reminders)
    }

    func create() -> EventReminder { EventReminder() }
    func save(_ reminder: EventReminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) { reminders[index] = reminder } else { reminders.append(reminder) }
        persist()
        schedule(reminder)
    }
    func remove(_ reminder: EventReminder) {
        reminders.removeAll { $0.id == reminder.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminder.scheduledNotifications.map(String.init))
        persist()
    }
    func applied(to event: MoodleEvent) -> [EventReminder] {
        reminders.filter { reminder in
            guard !(reminder.disabled ?? false) else { return false }
            if event.isArchived { return false }
            if settings.bool(SettingKey.ignoreCompleted, default: true) && event.isCompleted { return false }
            if settings.bool(SettingKey.ignoreCustom) && event.isCustom { return false }
            guard reminder.rules.isEmpty else { return event.matches(reminder, course: moodle?.course(for: event)) }
            return true
        }
    }
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func rescheduleAll() { reminders.forEach(schedule) }

    private func persist() { persistence.saveStringListJSON(reminders, for: MoodleStorageKey.reminders) }
    private func schedule(_ reminder: EventReminder) {
        guard let moodle else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminder.scheduledNotifications.map(String.init))
        var updated = reminder
        updated.scheduledNotifications = []
        for event in moodle.events where applied(to: event).contains(where: { $0.id == reminder.id }) {
            let date = reminder.scheduleDate(for: event)
            guard date > Date() else { continue }
            let identifier = abs(event.id &* 31 &+ reminder.id)
            let content = UNMutableNotificationContent()
            content.title = reminder.title ?? "Pokfu Reminder"
            content.body = "\(moodle.course(for: event)?.courseCode ?? "") \(event.name)".trimmingCharacters(in: .whitespaces)
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: String(identifier), content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            updated.scheduledNotifications.append(identifier)
        }
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) { reminders[index] = updated; persistence.saveStringListJSON(reminders, for: MoodleStorageKey.reminders) }
    }
}

extension EventReminder {
    func scheduleDate(for event: MoodleEvent) -> Date {
        var date = event.time
        date = Calendar.current.date(byAdding: unit.calendarComponent, value: -amount, to: date) ?? date
        if let hour, let min {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = min
            date = Calendar.current.date(from: components) ?? date
        }
        return date
    }
}

@available(iOS 16.1, *)
struct PokfuEventAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}
    var id = UUID()
}

@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private let defaults = UserDefaults(suiteName: PokfuBrand.appGroup) ?? .standard
    private var liveActivityID: String?
    private var pinnedEventID: Int?

    func update(events: [MoodleEvent], courses: [MoodleCourse]) {
        let next = events.filter { !$0.isCompleted && !$0.isArchived && !$0.expired }.sorted { $0.time < $1.time }.first
        guard let next else {
            defaults.set(false, forKey: "hasEvent")
            WidgetCenter.shared.reloadTimelines(ofKind: "PokfuUpcomingEventWidget")
            return
        }
        let course = courses.first { $0.id == next.courseid }
        defaults.set(true, forKey: "hasEvent")
        defaults.set(String(next.id), forKey: "eventId")
        defaults.set(course?.courseCode ?? "", forKey: "courseCode")
        defaults.set(course?.color.hexString ?? "#4F46E5", forKey: "courseColorHex")
        defaults.set(next.name, forKey: "eventTitle")
        defaults.set(next.timestart, forKey: "eventDueDate")
        defaults.set(Date().epoch, forKey: "currentDate")
        WidgetCenter.shared.reloadTimelines(ofKind: "PokfuUpcomingEventWidget")
    }

    @available(iOS 16.1, *)
    func reconcileActivities(events: [MoodleEvent], courses: [MoodleCourse]) async {
        for activity in Activity<PokfuEventAttributes>.activities {
            let prefix = activity.id
            guard let rawEventID = defaults.string(forKey: "\(prefix)_eventId"),
                  let eventID = Int(rawEventID),
                  let event = events.first(where: { $0.id == eventID }),
                  !event.expired, !event.isCompleted else {
                await activity.end(dismissalPolicy: .immediate)
                continue
            }
            let course = courses.first { $0.id == event.courseid }
            defaults.set(course?.courseCode ?? "", forKey: "\(prefix)_courseCode")
            defaults.set(course?.color.hexString ?? "#4F46E5", forKey: "\(prefix)_courseColorHex")
            defaults.set(event.name, forKey: "\(prefix)_eventTitle")
            defaults.set(event.timestart, forKey: "\(prefix)_eventDueDate")
            defaults.set(Date().epoch, forKey: "\(prefix)_currentDate")
        }
    }

    @available(iOS 16.1, *)
    func pin(event: MoodleEvent, course: MoodleCourse?) async {
        let activityID = UUID()
        let prefix = activityID.uuidString
        defaults.set(String(event.id), forKey: "\(prefix)_eventId")
        defaults.set(course?.courseCode ?? "", forKey: "\(prefix)_courseCode")
        defaults.set(course?.color.hexString ?? "#4F46E5", forKey: "\(prefix)_courseColorHex")
        defaults.set(event.name, forKey: "\(prefix)_eventTitle")
        defaults.set(event.timestart, forKey: "\(prefix)_eventDueDate")
        defaults.set(Date().epoch, forKey: "\(prefix)_currentDate")
        do {
            let activity = try Activity.request(attributes: PokfuEventAttributes(id: activityID), contentState: .init(), pushType: nil)
            liveActivityID = activity.id
            pinnedEventID = event.id
        } catch {}
    }

    @available(iOS 16.1, *)
    func endPinnedActivity() async {
        for activity in Activity< PokfuEventAttributes >.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
        liveActivityID = nil
        pinnedEventID = nil
    }
}

@MainActor
final class PokfuAppState: ObservableObject {
    let persistence: PersistenceStore
    let settings: SettingsStore
    let moodle: MoodleStore
    let ai: AIProviderStore
    let reminders: ReminderStore
    private var childSubscriptions = Set<AnyCancellable>()

    init() {
        let persistence = PersistenceStore()
        let settings = SettingsStore(persistence: persistence)
        let moodle = MoodleStore(persistence: persistence, settings: settings)
        let ai = AIProviderStore(persistence: persistence)
        self.persistence = persistence
        self.settings = settings
        self.moodle = moodle
        self.ai = ai
        self.reminders = ReminderStore(persistence: persistence, settings: settings, moodle: moodle)

        // Views receive the app state as their environment object. Forward
        // nested store changes so event completion/archive changes invalidate
        // the home list immediately instead of only on the next navigation.
        moodle.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childSubscriptions)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childSubscriptions)
        ai.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childSubscriptions)
        reminders.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &childSubscriptions)
    }

    func start() {
        if NSClassFromString("XCTestCase") != nil { return }
        moodle.bootstrap()
        reminders.rescheduleAll()
        WidgetBridge.shared.update(events: moodle.events, courses: moodle.courses)
        if #available(iOS 16.1, *) {
            Task { @MainActor in
                await WidgetBridge.shared.reconcileActivities(events: moodle.events, courses: moodle.courses)
            }
        }
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
