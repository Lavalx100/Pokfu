import Foundation
import SwiftUI
import UIKit

enum MoodleManagerStatus: String, Codable {
    case idle
    case updating
    case error
}

enum MoodleTutorRole: String, Hashable {
    case user
    case assistant
}

struct MoodleTutorMessage: Identifiable, Hashable {
    let id = UUID()
    let role: MoodleTutorRole
    let text: String
}

enum AIProviderKind: String, CaseIterable, Codable, Identifiable {
    case qwen
    case glm
    case doubao
    case deepseek
    case openRouter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .qwen: return "Qwen"
        case .glm: return "GLM"
        case .doubao: return "Doubao"
        case .deepseek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        }
    }

    var subtitle: String {
        switch self {
        case .qwen: return "Alibaba Cloud Model Studio"
        case .glm: return "Zhipu AI"
        case .doubao: return "Volcengine Ark"
        case .deepseek: return "DeepSeek API"
        case .openRouter: return "Free and multi-provider routing"
        }
    }

    /// These are OpenAI-compatible base URLs. The client appends
    /// `/chat/completions` when the user enters a base URL.
    var defaultEndpoint: String {
        switch self {
        case .qwen: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .deepseek: return "https://api.deepseek.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .qwen: return "qwen-plus"
        case .glm: return "glm-4.5-flash"
        case .doubao: return "doubao-seed-1-6-flash"
        case .deepseek: return "deepseek-chat"
        case .openRouter: return "qwen/qwen3.8-27b:free"
        }
    }

    var documentationURL: URL {
        switch self {
        case .qwen: return URL(string: "https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope")!
        case .glm: return URL(string: "https://docs.bigmodel.cn/")!
        case .doubao: return URL(string: "https://www.volcengine.com/docs/82379/1399008")!
        case .deepseek: return URL(string: "https://api-docs.deepseek.com/quick_start/pricing/")!
        case .openRouter: return URL(string: "https://openrouter.ai/docs/quickstart")!
        }
    }

    var setupHint: String {
        switch self {
        case .qwen:
            return "Create a general-purpose Model Studio API key in the Singapore or Hong Kong region. Region and key must match. Enable Free Quota Only if you want to prevent charges after the trial quota is used."
        case .glm:
            return "Create an API key in the Zhipu AI open platform. New accounts may receive promotional trial tokens."
        case .doubao:
            return "Create an Ark API key and activate the model or endpoint in Volcengine Ark. Use the exact endpoint/model ID shown in your Ark console."
        case .deepseek:
            return "Create a DeepSeek API key. This provider is pay-as-you-go rather than a general unlimited free API, so set a spending limit in the provider account."
        case .openRouter:
            return "Create an OpenRouter API key and choose a model ending in :free. Free routing has daily limits and the available free models can change."
        }
    }
}

struct AIProviderConfiguration: Codable, Hashable {
    var endpoint: String
    var model: String
    var enabled: Bool = true

    init(endpoint: String, model: String, enabled: Bool = true) {
        self.endpoint = endpoint
        self.model = model
        self.enabled = enabled
    }
}

enum MoodleAuthStatus: String {
    case ignore
    case incomplete
    case failed
    case success
}

enum EventGrouping: Int, CaseIterable, Identifiable {
    case time = 0
    case course = 1
    case none = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .time: return "Time"
        case .course: return "Course"
        case .none: return "None"
        }
    }
}

enum CourseSorting: Int, CaseIterable, Identifiable {
    case courseCode = 0
    case lastAccessed = 1

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .courseCode: return "Course Code"
        case .lastAccessed: return "Last Accessed"
        }
    }
}

enum CourseFiltering: Int, CaseIterable, Identifiable {
    case all = 0
    case latestSemester = 1

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .all: return "All Courses"
        case .latestSemester: return "Latest Semester"
        }
    }
}

enum ReminderUnit: Int, CaseIterable, Identifiable, Codable {
    case seconds = 0
    case minutes = 1
    case hours = 2
    case days = 3
    case weeks = 4

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .seconds: return "seconds"
        case .minutes: return "minutes"
        case .hours: return "hours"
        case .days: return "days"
        case .weeks: return "weeks"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .seconds: return .second
        case .minutes: return .minute
        case .hours: return .hour
        case .days: return .day
        case .weeks: return .weekOfYear
        }
    }
}

enum ReminderRuleSubject: Int, CaseIterable, Identifiable, Codable {
    case courseCode = 0
    case courseName = 1
    case eventTitle = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .courseCode: return "Course Code"
        case .courseName: return "Course Name"
        case .eventTitle: return "Event Title"
        }
    }
}

enum ReminderRuleAction: Int, CaseIterable, Identifiable, Codable {
    case contains = 0
    case doesNotContain = 1
    case matches = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .contains: return "Contains"
        case .doesNotContain: return "Does Not Contain"
        case .matches: return "Matches"
        }
    }
}

enum ReminderRuleRelation: Int, CaseIterable, Identifiable, Codable {
    case and = 0
    case or = 1

    var id: Int { rawValue }
    var title: String { self == .and ? "AND" : "OR" }
}

enum MoodleEventType: String, Codable {
    case due
    case user
    case custom
    case unknown
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

struct MoodleSiteFunction: Codable, Hashable {
    var name: String = ""
    var version: String = ""
}

struct MoodleSiteInfo: Codable, Hashable {
    var sitename = ""
    var username = ""
    var firstname = ""
    var lastname = ""
    var fullname = ""
    var lang = ""
    var userid: Int = 0
    var siteurl = ""
    var userpictureurl = ""
    var functions: [MoodleSiteFunction] = []
    var userprivateaccesskey = ""
    var siteid: Int = 0

    enum CodingKeys: String, CodingKey {
        case sitename, username, firstname, lastname, fullname, lang, userid
        case siteurl, userpictureurl, functions, userprivateaccesskey, siteid
    }

    init() {}
}

struct MoodleAutoLoginInfo: Codable, Hashable {
    var key = ""
    var lastRequested: Double = 0
}

struct MoodleCourseModule: Codable, Hashable, Identifiable {
    var id: Int = 0
    var url: String?
    var name = ""
    var instance: Int?
    var contextid: Int?
    var description: String?
    var visible: Int = 1
    var uservisible = true
    var visibleoncoursepage: Int?
    var modicon: String?
    var modname: String?
    var modplural: String?
    var indent: Int?
    var customdata: String?
    var downloadcontent: Int?
    var dates: [JSONValue]?
    var contents: [JSONValue]?
    var contentsinfo: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case id, url, name, instance, contextid, description, visible, uservisible
        case visibleoncoursepage, modicon, modname, modplural, indent, customdata
        case downloadcontent, dates, contents, contentsinfo
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeInt(.id)
        url = container.decodeString(.url)
        name = container.decodeString(.name) ?? ""
        instance = container.decodeIntIfPresent(.instance)
        contextid = container.decodeIntIfPresent(.contextid)
        description = container.decodeString(.description)
        visible = container.decodeInt(.visible, default: 1)
        uservisible = container.decodeBool(.uservisible, default: true)
        visibleoncoursepage = container.decodeIntIfPresent(.visibleoncoursepage)
        modicon = container.decodeString(.modicon)
        modname = container.decodeString(.modname)
        modplural = container.decodeString(.modplural)
        indent = container.decodeIntIfPresent(.indent)
        customdata = container.decodeString(.customdata)
        downloadcontent = container.decodeIntIfPresent(.downloadcontent)
        dates = try? container.decodeIfPresent([JSONValue].self, forKey: .dates)
        contents = try? container.decodeIfPresent([JSONValue].self, forKey: .contents)
        contentsinfo = try? container.decodeIfPresent([String: JSONValue].self, forKey: .contentsinfo)
    }

    var hasDownloadableFile: Bool {
        guard (downloadcontent ?? 0) > 0, let contents, !contents.isEmpty else { return false }
        return true
    }

    var fileURL: URL? {
        guard let dictionary = contents?.first?.objectValue,
              let raw = dictionary["fileurl"]?.stringValue else { return nil }
        return URL(string: raw)
    }

    var fileName: String? {
        contents?.first?.objectValue?["filename"]?.stringValue
    }

    var fileExtension: String {
        let name = fileName ?? fileURL?.lastPathComponent ?? ""
        return URL(fileURLWithPath: name).pathExtension.lowercased()
    }

    var isTutorShareableFile: Bool {
        guard hasDownloadableFile, fileURL != nil else { return false }
        return ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "csv", "txt", "md"].contains(fileExtension)
    }
}

struct MoodleCourseSection: Codable, Hashable, Identifiable {
    var id: Int = 0
    var name = ""
    var visible: Int = 1
    var summary = ""
    var summaryformat: Int = 1
    var section: Int = 0
    var hiddenbynumsections: Int = 0
    var uservisible: Bool?
    var modules: [MoodleCourseModule] = []

    private enum CodingKeys: String, CodingKey {
        case id, name, visible, summary, summaryformat, section
        case hiddenbynumsections, uservisible, modules
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeInt(.id)
        name = container.decodeString(.name) ?? ""
        visible = container.decodeInt(.visible, default: 1)
        summary = container.decodeString(.summary) ?? ""
        summaryformat = container.decodeInt(.summaryformat, default: 1)
        section = container.decodeInt(.section)
        hiddenbynumsections = container.decodeInt(.hiddenbynumsections)
        uservisible = container.decodeBoolIfPresent(.uservisible)
        modules = (try? container.decodeIfPresent([MoodleCourseModule].self, forKey: .modules)) ?? []
    }

    var isVisible: Bool { visible == 1 && (uservisible ?? true) }
    var isEmpty: Bool { summary.isEmpty && modules.isEmpty }
}

struct MoodleSearchResult: Codable, Hashable, Identifiable {
    var id = ""
    var title = ""
    var content = ""
    var url: String?
    var contexturl: String?
    var courseid = 0
    var coursefullname = ""
    var type = ""
    var area = ""

    private enum CodingKeys: String, CodingKey {
        case id, title, content, url, contexturl, courseid, coursefullname
        case type, area
    }

    init() {}

    init(
        id: String,
        title: String,
        content: String,
        url: String? = nil,
        courseID: Int = 0,
        courseName: String = "",
        type: String = "",
        area: String = ""
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.url = url
        self.courseid = courseID
        self.coursefullname = courseName
        self.type = type
        self.area = area
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id) ?? ""
        title = container.decodeString(.title) ?? ""
        content = container.decodeString(.content) ?? ""
        url = container.decodeString(.url)
        contexturl = container.decodeString(.contexturl)
        courseid = container.decodeInt(.courseid)
        coursefullname = container.decodeString(.coursefullname) ?? ""
        type = container.decodeString(.type) ?? ""
        area = container.decodeString(.area) ?? ""
    }

    var displayTitle: String {
        let value = MoodleText.plain(title)
        return value.isEmpty ? "Moodle Result" : value
    }

    var displayContent: String { MoodleText.plain(content) }
    var sourceURL: URL? { URL(string: url ?? contexturl ?? "") }
    var courseCode: String {
        coursefullname.split(separator: " ").first.map(String.init) ?? ""
    }
}

struct MoodleTutorAttachmentCandidate: Identifiable, Hashable {
    let id: String
    let module: MoodleCourseModule
    let courseName: String
    let score: Int

    var fileName: String {
        module.fileName ?? module.fileURL?.lastPathComponent ?? "Moodle material"
    }
}

struct MoodleTutorAttachment: Identifiable, Hashable {
    let id: String
    let fileName: String
    let courseName: String
    let fileURL: URL
}

enum MoodleText {
    static func plain(_ value: String) -> String {
        guard value.contains("<") || value.contains("&") else {
            return collapseWhitespace(value)
        }

        var text = value
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|div|li|tr|h[1-6])\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
            ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&ndash;", "–"), ("&mdash;", "—"), ("&minus;", "−"),
            ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&rdquo;", "”"), ("&ldquo;", "“")
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .components(separatedBy: .newlines)
            .map(collapseWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension KeyedDecodingContainer {
    func decodeString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeInt(_ key: Key, default defaultValue: Int = 0) -> Int {
        decodeIntIfPresent(key) ?? defaultValue
    }

    func decodeIntIfPresent(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func decodeBool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        decodeBoolIfPresent(key) ?? defaultValue
    }

    func decodeBoolIfPresent(_ key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "1", "true": return true
            case "0", "false": return false
            default: return nil
            }
        }
        return nil
    }

    func decodeMoodleCell(_ key: Key) -> String? {
        if let value = decodeString(key) { return value }
        guard let object = try? decode([String: JSONValue].self, forKey: key),
              let content = object["content"] else { return nil }
        switch content {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "1" : "0"
        case .null, .object, .array: return nil
        }
    }
}

struct MoodleCourse: Codable, Hashable, Identifiable {
    var id: Int = 0
    var shortname = ""
    var fullname = ""
    var displayname = ""
    var idnumber = ""
    var visible: Int = 1
    var summary = ""
    var summaryformat: Int = 1
    var format = ""
    var showgrades = true
    var lang = ""
    var enablecompletion: Bool?
    var completionhascriteria: Bool?
    var completionusertracked: Bool?
    var category: Int?
    var progress: Double?
    var completed: Bool?
    var startdate: Double?
    var enddate: Double?
    var marker: Int?
    var lastaccess: Double?
    var isfavourite = false
    var hidden = false
    var overviewfiles: [JSONValue]?
    var showactivitydates: Bool?
    var showcompletionconditions: Bool?
    var timemodified: Double?
    var colorHex: String?
    var customFavorite: Bool?
    var cachedContents: [MoodleCourseSection]?
    var cachedTime: Double?

    var courseCode: String { fullname.split(separator: " ").first.map(String.init) ?? shortname }
    var nameWithoutCode: String {
        let parts = fullname.split(separator: " ")
        return parts.dropFirst().joined(separator: " ")
    }
    var isFavorite: Bool { customFavorite ?? isfavourite }
    var lastAccessDate: Date? { lastaccess.map(Date.fromEpoch) }
    var color: Color { Color(hex: colorHex) ?? CourseColorRegistry.color(for: id) }
}

struct MoodleCourseGrade: Codable, Hashable, Identifiable {
    var itemname = ""
    var weight: String?
    var grade = ""
    var range = ""
    var feedback: String?
    var percentage: String?
    var contributiontocoursetotal: String?

    private enum CodingKeys: String, CodingKey {
        case itemname, weight, grade, range, feedback, percentage, contributiontocoursetotal
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemname = container.decodeMoodleCell(.itemname) ?? ""
        weight = container.decodeMoodleCell(.weight)
        grade = container.decodeMoodleCell(.grade) ?? ""
        range = container.decodeMoodleCell(.range) ?? ""
        feedback = container.decodeMoodleCell(.feedback)
        percentage = container.decodeMoodleCell(.percentage)
        contributiontocoursetotal = container.decodeMoodleCell(.contributiontocoursetotal)
    }

    var id: String { itemname + grade + range }
    var title: String {
        let value = HTMLText.plain(itemname)
        return value.isEmpty ? "Grade Item" : value
    }
    var displayWeight: String { HTMLText.removingMoodleActionLabels(from: weight ?? "") }
    var displayGrade: String { HTMLText.removingMoodleActionLabels(from: grade) }
    var displayRange: String { HTMLText.removingMoodleActionLabels(from: range) }
    var displayPercentage: String { HTMLText.removingMoodleActionLabels(from: percentage ?? "") }
    var displayContribution: String {
        HTMLText.removingMoodleActionLabels(from: contributiontocoursetotal ?? "")
    }
    var displayFeedback: String? {
        guard let feedback else { return nil }
        // Moodle sometimes puts its row-action labels in the feedback cell
        // (for example, "Actions" and "Grade analysis / 0–100"). Remove
        // those labels while retaining any real instructor feedback that
        // may be in the same cell.
        let value = HTMLText.removingMoodleActionLabels(from: feedback)
        return value.isEmpty ? nil : value
    }
    var numericGrade: Double? { Double(displayGrade) }
    var isRenderable: Bool {
        !displayGrade.isEmpty ||
        !displayRange.isEmpty ||
        !displayPercentage.isEmpty ||
        !displayContribution.isEmpty ||
        displayFeedback != nil
    }
}

private enum HTMLText {
    static func removingMoodleActionLabels(from value: String) -> String {
        let text = plain(value)
        return text
            .components(separatedBy: .newlines)
            .compactMap { line in
                let normalized = line
                    .replacingOccurrences(of: "\u{00a0}", with: " ")
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")

                // The Moodle grade-table renderer can append its action links
                // to any cell, not only feedback. Remove the action suffix
                // after converting the cell to plain text so the score and
                // other useful values remain intact.
                let withoutActions = normalized.replacingOccurrences(
                    of: "(?i)\\b(actions?|grade analysis)\\b.*$",
                    with: "",
                    options: .regularExpression
                )
                let trimmed = withoutActions.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plain(_ value: String) -> String {
        guard value.contains("<") || value.contains("&") else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Grade cells are small snippets such as `<span>85.00</span>`, but
        // Moodle plugins occasionally return incomplete or unusual markup.
        // Avoid NSAttributedString's HTML importer here: it is unnecessary
        // for grade labels and can be fragile with malformed HTML.
        var text = value
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|div|li|tr|h[1-6])\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
            ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&ndash;", "–"), ("&mdash;", "—"), ("&minus;", "−"),
            ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&rdquo;", "”"), ("&ldquo;", "“")
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct MoodleEvent: Codable, Hashable, Identifiable {
    var id: Int = 0
    var name = ""
    var description = ""
    var format: Int?
    var courseid: Int?
    var categoryid: String?
    var groupid: String?
    var userid: Int?
    var repeatid: String?
    var modulename: String?
    var instance: Int?
    var eventtype = ""
    var timestart: Double = 0
    var timeduration: Double?
    var visible: Int?
    var sequence: Int?
    var timemodified: Double?
    var subscriptionid: String?
    var completed: Bool?
    var cmid: Int?
    var hascompletion: Bool?
    var state: Int?
    var url: String?
    var archived: Bool?

    var time: Date { Date.fromEpoch(timestart) }
    var isCustom: Bool { eventtype == MoodleEventType.custom.rawValue }
    var isCompleted: Bool { completed ?? ((state ?? 0) >= 1) }
    var isArchived: Bool { archived ?? false }
    var expired: Bool { time < Date() }
    var remainingTime: TimeInterval { time.timeIntervalSinceNow }
}

struct EventReminderRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var subject: ReminderRuleSubject = .eventTitle
    var action: ReminderRuleAction = .contains
    var pattern = ""
    var relationWithNext: ReminderRuleRelation?
}

struct EventReminder: Codable, Hashable, Identifiable {
    var id: Int = Int(Date().timeIntervalSince1970)
    var title: String?
    var rules: [EventReminderRule] = []
    var scheduledNotifications: [Int] = []
    var amount: Int = 30
    var unit: ReminderUnit = .minutes
    var hour: Int?
    var min: Int?
    var disabled: Bool?

    var timingDescription: String {
        let suffix = amount == 1 ? String(unit.title.dropLast()) : unit.title
        var result = "\(amount) \(suffix) before due"
        if let hour, let min { result += String(format: " at %d:%02d", hour, min) }
        return result
    }
}

extension Date {
    static func fromEpoch(_ value: Double) -> Date { Date(timeIntervalSince1970: value) }
    var epoch: Double { timeIntervalSince1970 }
}

extension Color {
    init?(hex: String?) {
        guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let divisor = Double(255)
        if value.count == 8 {
            self.init(red: Double((number >> 24) & 0xff) / divisor,
                      green: Double((number >> 16) & 0xff) / divisor,
                      blue: Double((number >> 8) & 0xff) / divisor,
                      opacity: Double(number & 0xff) / divisor)
        } else {
            self.init(red: Double((number >> 16) & 0xff) / divisor,
                      green: Double((number >> 8) & 0xff) / divisor,
                      blue: Double(number & 0xff) / divisor)
        }
    }

    var hexString: String {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        #else
        return "#4F46E5"
        #endif
    }
}

enum CourseColorRegistry {
    static let palette: [Color] = [
        Color(red: 88 / 255, green: 108 / 255, blue: 245 / 255),
        Color(red: 21 / 255, green: 166 / 255, blue: 218 / 255),
        Color(red: 67 / 255, green: 145 / 255, blue: 255 / 255),
        Color(red: 16 / 255, green: 131 / 255, blue: 218 / 255),
        Color(red: 92 / 255, green: 136 / 255, blue: 255 / 255),
        Color(red: 44 / 255, green: 72 / 255, blue: 255 / 255),
        Color(red: 103 / 255, green: 120 / 255, blue: 228 / 255),
        Color(red: 127 / 255, green: 115 / 255, blue: 252 / 255),
        Color(red: 105 / 255, green: 88 / 255, blue: 255 / 255),
        Color(red: 153 / 255, green: 90 / 255, blue: 255 / 255),
        Color(red: 179 / 255, green: 132 / 255, blue: 255 / 255),
        Color(red: 210 / 255, green: 131 / 255, blue: 255 / 255),
        Color(red: 164 / 255, green: 68 / 255, blue: 220 / 255),
        Color(red: 180 / 255, green: 49 / 255, blue: 255 / 255),
        Color(red: 202 / 255, green: 46 / 255, blue: 210 / 255),
        Color(red: 238 / 255, green: 73 / 255, blue: 247 / 255),
        Color(red: 226 / 255, green: 9 / 255, blue: 194 / 255)
    ]

    static var mapping: [String: Int] = [:]
    static func color(for id: Int) -> Color {
        palette[mapping[String(id), default: id % palette.count] % palette.count]
    }
}

extension MoodleEvent {
    func matches(_ reminder: EventReminder, course: MoodleCourse?) -> Bool {
        guard !expired else { return false }
        var result: Bool?
        var relation: ReminderRuleRelation = .and
        for rule in reminder.rules where !rule.pattern.isEmpty {
            let subject: String? = {
                switch rule.subject {
                case .courseCode: return course?.courseCode
                case .courseName: return course?.fullname
                case .eventTitle: return name
                }
            }()
            let value = subject?.lowercased() ?? ""
            let pattern = rule.pattern.lowercased()
            let passed: Bool
            switch rule.action {
            case .contains: passed = value.contains(pattern)
            case .doesNotContain: passed = !value.contains(pattern)
            case .matches:
                passed = (try? NSRegularExpression(pattern: rule.pattern))?.firstMatch(in: subject ?? "", range: NSRange(location: 0, length: (subject ?? "").utf16.count)) != nil
            }
            if let current = result {
                result = relation == .and ? current && passed : current || passed
            } else {
                result = passed
            }
            relation = rule.relationWithNext ?? .and
        }
        return result ?? true
    }

    static func custom() -> MoodleEvent {
        MoodleEvent(id: Int(Date().timeIntervalSince1970), name: "", description: "", eventtype: MoodleEventType.custom.rawValue, timestart: Date().addingTimeInterval(3600).epoch)
    }

    init(id: Int = 0, name: String = "", description: String = "", eventtype: String = "", timestart: Double = 0) {
        self.id = id
        self.name = name
        self.description = description
        self.eventtype = eventtype
        self.timestart = timestart
    }
}
