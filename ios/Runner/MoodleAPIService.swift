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
