import XCTest
@testable import Runner

private final class AIProviderURLProtocol: URLProtocol {
  static var lastRequest: URLRequest?
  static var lastBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    if let body = request.httpBody {
      Self.lastBody = body
    } else if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      Self.lastBody = data
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"stub reply"}}]}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

class RunnerTests: XCTestCase {

  func testAIProviderDefaultsUseOpenAICompatibleEndpoints() throws {
    XCTAssertEqual(try AIProviderClient.normalizedEndpoint("https://api.deepseek.com").absoluteString, "https://api.deepseek.com/chat/completions")
    XCTAssertEqual(try AIProviderClient.normalizedEndpoint("https://openrouter.ai/api/v1/chat/completions").absoluteString, "https://openrouter.ai/api/v1/chat/completions")
    XCTAssertEqual(try AIProviderClient.normalizedEndpoint("https://dashscope-intl.aliyuncs.com/compatible-mode/v1/").path, "/compatible-mode/v1/chat/completions")
  }

  func testAIProviderRejectsNonHTTPSEndpoints() {
    XCTAssertThrowsError(try AIProviderClient.normalizedEndpoint("http://localhost:8000/v1")) { error in
      XCTAssertEqual((error as? AIProviderError)?.localizedDescription, AIProviderError.invalidEndpoint.localizedDescription)
    }
  }

  func testAIProviderParsesStandardAndMultimodalResponseContent() {
    let standard = Data(#"{"choices":[{"message":{"content":"Hello from Qwen"}}]}"#.utf8)
    let multimodal = Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"from GLM"}]}}]}"#.utf8)
    XCTAssertEqual(try? AIProviderClient.responseText(from: standard), "Hello from Qwen")
    XCTAssertEqual(try? AIProviderClient.responseText(from: multimodal), "Hello from GLM")
  }

  func testAIProviderBuildsAuthorizedChatRequest() async throws {
    AIProviderURLProtocol.lastRequest = nil
    AIProviderURLProtocol.lastBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AIProviderURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let providerConfiguration = AIProviderConfiguration(endpoint: "https://api.deepseek.com", model: "deepseek-chat")

    let result = try await AIProviderClient.complete(
      provider: .deepseek,
      configuration: providerConfiguration,
      apiKey: "test-key",
      context: "Explain this assignment.",
      session: session
    )

    XCTAssertEqual(result, "stub reply")
    XCTAssertEqual(AIProviderURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    let body = try XCTUnwrap(AIProviderURLProtocol.lastBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["model"] as? String, "deepseek-chat")
    XCTAssertEqual(object["stream"] as? Bool, false)
  }

  func testReminderRuleMatching() {
    let event = MoodleEvent(id: 1, name: "Assignment 1", description: "", eventtype: MoodleEventType.due.rawValue, timestart: Date().addingTimeInterval(3600).epoch)
    let reminder = EventReminder(title: "Assignments", rules: [EventReminderRule(subject: .eventTitle, action: .contains, pattern: "assignment")])
    XCTAssertTrue(event.matches(reminder, course: nil))
  }

  func testMoodleAuthTokenParsingPreservesLegacyFormat() throws {
    let payload = Data("site:::web-token:::private-token".utf8).base64EncodedString()
    let result = try MoodleAPIClient().handleAuthToken("token=\(payload)")
    XCTAssertEqual(result.0, "web-token")
    XCTAssertEqual(result.1, "private-token")
  }

  func testMoodleAuthTokenParsingAcceptsMoodleCallbackURL() throws {
    let payload = Data("site:::web-token:::private-token".utf8).base64EncodedString()
    let result = try MoodleAPIClient().handleAuthToken("pokfu://token=\(payload)")
    XCTAssertEqual(result.0, "web-token")
    XCTAssertEqual(result.1, "private-token")
  }

  func testNestedCourseModuleJSONIsDecodedForDownloads() throws {
    let data = Data(#"{"id": 42, "name": "Slides", "visible": 1, "uservisible": true, "downloadcontent": 1, "contents": [{"fileurl": "https://moodle.example/file", "filename": "slides.pdf"}]}"#.utf8)
    let module = try JSONDecoder().decode(MoodleCourseModule.self, from: data)
    XCTAssertEqual(module.fileURL?.absoluteString, "https://moodle.example/file")
    XCTAssertEqual(module.fileName, "slides.pdf")
    XCTAssertTrue(module.isTutorShareableFile)
  }

  func testTutorShareSkipsUnsupportedLargeBinaryTypes() throws {
    let data = Data(#"{"id": 43, "name": "Video", "visible": 1, "uservisible": true, "downloadcontent": 1, "contents": [{"fileurl": "https://moodle.example/file.zip", "filename": "course.zip"}]}"#.utf8)
    let module = try JSONDecoder().decode(MoodleCourseModule.self, from: data)
    XCTAssertFalse(module.isTutorShareableFile)
  }

  func testAuthenticatedMoodleFileURLUsesTokenPluginRoute() throws {
    let data = Data(#"{"id": 42, "name": "Slides", "downloadcontent": 1, "contents": [{"fileurl": "https://moodle.example/webservice/pluginfile.php/temp/context/course/slides.pdf", "filename": "slides.pdf"}]}"#.utf8)
    let module = try JSONDecoder().decode(MoodleCourseModule.self, from: data)
    let api = MoodleAPIClient(domain: "moodle.example")
    api.privateToken = "private-token"
    var siteInfo = MoodleSiteInfo()
    siteInfo.userprivateaccesskey = "access-key"
    api.siteInfo = siteInfo

    let url = try XCTUnwrap(api.authenticatedFileURL(for: module))
    XCTAssertEqual(url.path, "/tokenpluginfile.php/access-key/context/course/slides.pdf")
    XCTAssertEqual(url.queryItems["forcedownload"], "1")
    XCTAssertEqual(url.queryItems["offline"], "1")
    XCTAssertEqual(url.queryItems["token"], "private-token")
  }

  func testCourseContentsDecodeWhenMoodleOmitsOptionalFields() throws {
    let data = Data(#"{"id": 7, "name": "General", "visible": true, "summary": null, "section": 1}"#.utf8)
    let section = try JSONDecoder().decode(MoodleCourseSection.self, from: data)
    XCTAssertEqual(section.id, 7)
    XCTAssertEqual(section.section, 1)
    XCTAssertTrue(section.modules.isEmpty)
    XCTAssertTrue(section.isVisible)
  }

  func testBrowserOnlyModuleDoesNotFailCourseDecoding() throws {
    let data = Data(#"{"id": 8, "name": "Forum", "visible": 1, "uservisible": true, "downloadcontent": false}"#.utf8)
    let module = try JSONDecoder().decode(MoodleCourseModule.self, from: data)
    XCTAssertEqual(module.name, "Forum")
    XCTAssertFalse(module.hasDownloadableFile)
  }

  func testMoodleGradeCellsDecodeNestedContentValues() throws {
    let data = Data(#"{"itemname":{"content":"<a>Quiz 1</a>"},"weight":{"content":"20.00"},"grade":{"content":"85.00"},"range":{"content":"0-100"},"feedback":{"content":"Good work"}}"#.utf8)
    let grade = try JSONDecoder().decode(MoodleCourseGrade.self, from: data)
    XCTAssertEqual(grade.title, "Quiz 1")
    XCTAssertEqual(grade.displayGrade, "85.00")
    XCTAssertEqual(grade.displayRange, "0-100")
    XCTAssertEqual(grade.displayFeedback, "Good work")
    XCTAssertTrue(grade.isRenderable)
  }

  func testMoodleGradeDisplayHandlesMalformedHTMLAndEmptyCells() throws {
    let data = Data(#"{"itemname":{"content":"<span>"},"grade":{"content":"<b>"},"range":{"content":""}}"#.utf8)
    let grade = try JSONDecoder().decode(MoodleCourseGrade.self, from: data)
    XCTAssertEqual(grade.title, "Grade Item")
    XCTAssertEqual(grade.displayGrade, "")
    XCTAssertEqual(grade.displayRange, "")
    XCTAssertFalse(grade.isRenderable)
  }

  func testMoodleGradeHidesActionLinksFromFeedback() throws {
    let data = Data(#"{"itemname":{"content":"Assignment 1"},"grade":{"content":"98.00"},"range":{"content":"0&ndash;100"},"feedback":{"content":"Actions<br>Grade analysis / 0&ndash;100"}}"#.utf8)
    let grade = try JSONDecoder().decode(MoodleCourseGrade.self, from: data)
    XCTAssertEqual(grade.displayRange, "0–100")
    XCTAssertNil(grade.displayFeedback)
  }

  func testMoodleGradeRemovesActionLinksAppendedToTheScoreCell() throws {
    let data = Data(#"{"itemname":{"content":"Assignment 1"},"grade":{"content":"<span>99.00</span><a>Actions</a><a>Grade analysis</a>"},"percentage":{"content":"99.00 %"}}"#.utf8)
    let grade = try JSONDecoder().decode(MoodleCourseGrade.self, from: data)
    XCTAssertEqual(grade.displayGrade, "99.00")
    XCTAssertEqual(grade.displayPercentage, "99.00 %")
  }

  func testMoodleSearchResultDecodesHTMLAndNumericIdentifiers() throws {
    let data = Data(#"{"id":123,"title":"<b>Lecture 1</b>","content":"<p>Binary &amp; hexadecimal</p>","courseid":42,"coursefullname":"COMP2120"}"#.utf8)
    let result = try JSONDecoder().decode(MoodleSearchResult.self, from: data)
    XCTAssertEqual(result.id, "123")
    XCTAssertEqual(result.displayTitle, "Lecture 1")
    XCTAssertEqual(result.displayContent, "Binary & hexadecimal")
    XCTAssertEqual(result.courseCode, "COMP2120")
  }

  func testMoodleHTMLTextCollapsesLineBreaksWithoutLeakingMarkup() {
    XCTAssertEqual(MoodleText.plain("<p>One</p><p>Two &ndash; three</p>"), "One\nTwo – three")
  }

  func testMoodleGradePreservesRealFeedbackWhenActionLinksShareTheCell() throws {
    let data = Data(#"{"itemname":{"content":"Assignment 1"},"grade":{"content":"98.00"},"feedback":{"content":"Great work<br>Actions<br>GRADE ANALYSIS / 0-100"}}"#.utf8)
    let grade = try JSONDecoder().decode(MoodleCourseGrade.self, from: data)
    XCTAssertEqual(grade.displayFeedback, "Great work")
  }

  func testCompletedAndArchivedEventStateDecodes() throws {
    let data = Data(#"{"id": 12, "name": "Essay", "description": "", "eventtype": "due", "timestart": 1800000000, "completed": true, "archived": true}"#.utf8)
    let event = try JSONDecoder().decode(MoodleEvent.self, from: data)
    XCTAssertTrue(event.isCompleted)
    XCTAssertTrue(event.isArchived)
  }

  func testReminderScheduleDateSupportsRelativeTiming() {
    let eventDate = Date(timeIntervalSince1970: 1_800_000_000)
    let event = MoodleEvent(id: 2, name: "Exam", description: "", eventtype: MoodleEventType.due.rawValue, timestart: eventDate.epoch)
    let reminder = EventReminder(title: "Exam", amount: 2, unit: .hours)
    XCTAssertEqual(reminder.scheduleDate(for: event).timeIntervalSince1970, eventDate.addingTimeInterval(-7200).timeIntervalSince1970, accuracy: 0.001)
  }

  func testCustomEventIsIdentifiableAndNotExpired() {
    let event = MoodleEvent.custom()
    XCTAssertTrue(event.isCustom)
    XCTAssertFalse(event.expired)
  }

}
