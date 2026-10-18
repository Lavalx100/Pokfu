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
