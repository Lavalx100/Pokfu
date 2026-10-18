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
