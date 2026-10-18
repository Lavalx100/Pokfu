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
