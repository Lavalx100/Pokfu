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
