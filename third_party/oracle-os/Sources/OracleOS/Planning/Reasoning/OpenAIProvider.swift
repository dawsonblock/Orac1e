// OpenAIProvider.swift — Concrete LLMProvider using the OpenAI-compatible API.
//
// This is the default provider for Oracle OS reasoning. It supports any
// OpenAI-compatible endpoint (OpenAI, Azure OpenAI, Anthropic via proxy,
// Ollama, LM Studio, etc.) via environment variables:
//
//   ORACLE_LLM_API_KEY        — API key (required for cloud providers)
//   ORACLE_LLM_BASE_URL       — Base URL (default: https://api.openai.com/v1)
//   ORACLE_LLM_MODEL          — Model name (default: gpt-4o)
//   ORACLE_LLM_PLANNING_MODEL — Override model for planning tier
//   ORACLE_LLM_REPAIR_MODEL   — Override model for code repair tier
//
// Usage:
//   let provider = OpenAIProvider()
//   let client = LLMClient(defaultProvider: provider)

import Foundation

/// A concrete ``LLMProvider`` that speaks the OpenAI chat completions API.
///
/// Supports any endpoint that implements the `/v1/chat/completions` contract
/// (OpenAI, Azure, Ollama, LM Studio, vLLM, etc.).
public final class OpenAIProvider: LLMProvider, @unchecked Sendable {
    private let apiKey: String?
    private let baseURL: String
    private let defaultModel: String
    private let modelOverrides: [LLMModelTier: String]
    private let session: URLSession
    private let timeout: TimeInterval

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        defaultModel: String? = nil,
        modelOverrides: [LLMModelTier: String] = [:],
        timeout: TimeInterval = 60
    ) {
        let env = ProcessInfo.processInfo.environment
        self.apiKey = apiKey ?? env["ORACLE_LLM_API_KEY"]
        self.baseURL = (baseURL ?? env["ORACLE_LLM_BASE_URL"] ?? "https://api.openai.com/v1")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.defaultModel = defaultModel ?? env["ORACLE_LLM_MODEL"] ?? "gpt-4o"

        // Allow per-tier model overrides from environment.
        var overrides = modelOverrides
        if overrides[.planning] == nil, let m = env["ORACLE_LLM_PLANNING_MODEL"] { overrides[.planning] = m }
        if overrides[.codeRepair] == nil, let m = env["ORACLE_LLM_REPAIR_MODEL"] { overrides[.codeRepair] = m }
        if overrides[.browserReasoning] == nil, let m = env["ORACLE_LLM_BROWSER_MODEL"] { overrides[.browserReasoning] = m }
        if overrides[.recovery] == nil, let m = env["ORACLE_LLM_RECOVERY_MODEL"] { overrides[.recovery] = m }
        self.modelOverrides = overrides

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
        self.timeout = timeout
    }

    /// Whether this provider has enough configuration to make real API calls.
    public var isConfigured: Bool {
        // Local endpoints (Ollama, LM Studio) don't need an API key.
        let isLocal = baseURL.contains("127.0.0.1") || baseURL.contains("localhost")
        return isLocal || (apiKey != nil && !apiKey!.isEmpty)
    }

    // MARK: - LLMProvider conformance

    public func complete(prompt: String) async throws -> String {
        try await complete(request: LLMRequest(prompt: prompt))
    }

    public func complete(request: LLMRequest) async throws -> String {
        let model = modelOverrides[request.modelTier] ?? defaultModel
        let body = buildRequestBody(prompt: request.prompt, model: model, request: request)
        let data = try await post(path: "/chat/completions", body: body)
        return try extractContent(from: data)
    }

    // MARK: - HTTP

    private func post(path: String, body: [String: Any]) async throws -> Data {
        let urlString = baseURL + path
        guard let url = URL(string: urlString) else {
            throw LLMClientError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:
                break
            case 429:
                throw LLMClientError.rateLimited
            case 401, 403:
                throw LLMClientError.authenticationFailed
            case 408, 504:
                throw LLMClientError.timeout
            default:
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                throw LLMClientError.httpError(statusCode: httpResponse.statusCode, body: body)
            }
        }

        return data
    }

    // MARK: - Request / Response

    private func buildRequestBody(
        prompt: String,
        model: String,
        request: LLMRequest
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt(for: request.modelTier)],
                ["role": "user", "content": prompt],
            ],
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
        ]
        // Disable streaming — we want the full response in one shot.
        body["stream"] = false
        return body
    }

    private func extractContent(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMClientError.malformedResponse(raw)
        }
        return content
    }

    private func systemPrompt(for tier: LLMModelTier) -> String {
        switch tier {
        case .planning:
            return """
            You are a planning engine for an autonomous macOS agent. Given the current UI state \
            and goal, emit the next action as a structured step. Be precise about element labels, \
            roles, and expected postconditions. Prefer the simplest action that advances the goal.
            """
        case .codeRepair:
            return """
            You are a code repair engine. Given a failing test, build error, or bug description \
            plus the relevant source code, emit a minimal targeted patch. Prefer the smallest \
            change that fixes the issue without introducing regressions.
            """
        case .browserReasoning:
            return """
            You are a browser interaction planner. Given a web page's visible elements, form \
            fields, and navigation state, choose the correct element to interact with and the \
            correct input to provide. Be precise about CSS selectors and element labels.
            """
        case .recovery:
            return """
            You are a recovery advisor for an autonomous agent. Given a failed action, the \
            pre/post UI state, and the failure classification, suggest the best recovery strategy. \
            Prefer strategies that have succeeded before in similar states.
            """
        case .memorySummarization:
            return """
            You are a memory summarization engine. Compress execution traces and episode data \
            into concise, reusable knowledge entries. Focus on what worked, what failed, and \
            what patterns are worth remembering.
            """
        case .metaReasoning:
            return """
            You are a meta-reasoning engine that evaluates and improves the agent's own planning \
            and execution strategies. Identify systematic failures and suggest adjustments.
            """
        }
    }
}

// MARK: - Extended LLMClientError cases

public extension LLMClientError {
    /// URL could not be constructed.
    static func invalidURL(_ url: String) -> LLMClientError { .transportError("Invalid URL: \(url)") }
    /// Authentication failed (401/403).
    static let authenticationFailed: LLMClientError = .transportError("Authentication failed")
    /// HTTP error with status code.
    static func httpError(statusCode: Int, body: String) -> LLMClientError {
        .transportError("HTTP \(statusCode): \(body.prefix(500))")
    }
    /// Response could not be parsed.
    static func malformedResponse(_ raw: String) -> LLMClientError {
        .transportError("Malformed response: \(raw.prefix(500))")
    }
}
