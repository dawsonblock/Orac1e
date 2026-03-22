import Foundation

public protocol LLMProvider: Sendable {
    /// Complete a prompt using the LLM with default request parameters.
    func complete(prompt: String) async throws -> String

    /// Complete a full `LLMRequest`, allowing providers to respect
    /// model tier, max token count and temperature.
    func complete(request: LLMRequest) async throws -> String
}

/// Centralized model definitions to replace hardcoded strings
public enum LLMModel: String, Sendable {
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4Turbo = "gpt-4-turbo"
    case gpt35Turbo = "gpt-3.5-turbo"
    case claude3Opus = "claude-3-opus"
    case claude3Sonnet = "claude-3-sonnet"
    case claude3Haiku = "claude-3-haiku"
    case o1 = "o1"
    case o1Mini = "o1-mini"
    case o3Mini = "o3-mini"

    /// Default model for planning tier
    public static let defaultPlanning = LLMModel.gpt4o
    /// Default model for code repair tier
    public static let defaultCodeRepair = LLMModel.gpt4o
    /// Default model for browser reasoning
    public static let defaultBrowser = LLMModel.gpt4o
    /// Default model for recovery
    public static let defaultRecovery = LLMModel.gpt4oMini
    /// Default fallback model
    public static let defaultFallback = LLMModel.gpt4o
}

public extension LLMProvider {
    func complete(request: LLMRequest) async throws -> String {
        try await complete(prompt: request.prompt)
    }
}

public enum LLMModelTier: String, Sendable {
    case planning
    case codeRepair = "code_repair"
    case browserReasoning = "browser_reasoning"
    case recovery
    case memorySummarization = "memory_summarization"
    case metaReasoning = "meta_reasoning"
}

public struct LLMRequest: Sendable {
    public let prompt: String
    public let modelTier: LLMModelTier
    public let maxTokens: Int
    public let temperature: Double

    public init(
        prompt: String,
        modelTier: LLMModelTier = .planning,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) {
        self.prompt = prompt
        self.modelTier = modelTier
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public struct LLMResponse: Sendable {
    public let text: String
    public let modelTier: LLMModelTier
    public let tokenCount: Int
    public let latencyMs: Double

    public init(
        text: String,
        modelTier: LLMModelTier,
        tokenCount: Int = 0,
        latencyMs: Double = 0
    ) {
        self.text = text
        self.modelTier = modelTier
        self.tokenCount = tokenCount
        self.latencyMs = latencyMs
    }
}

public final class LLMClient: @unchecked Sendable {
    private let providers: [LLMModelTier: any LLMProvider]
    private let defaultProvider: (any LLMProvider)?
    private let maxRetries: Int
    private let lockQueue = DispatchQueue(label: "org.oracleos.llmclient.lock")
    private var requestCount: Int = 0
    private var totalTokens: Int = 0

    /// Minimum delay on rate limit (1 second)
    private let rateLimitMinDelay: TimeInterval = 1.0
    /// Maximum delay on rate limit (32 seconds)
    private let rateLimitMaxDelay: TimeInterval = 32.0

    public init(
        providers: [LLMModelTier: any LLMProvider] = [:],
        defaultProvider: (any LLMProvider)? = nil,
        maxRetries: Int = 2
    ) {
        self.providers = providers
        // Fall back to OpenAIProvider when no explicit provider is given.
        // OpenAIProvider reads API key and endpoint from environment variables
        // and supports any OpenAI-compatible endpoint (Ollama, LM Studio, etc.).
        let resolved = defaultProvider ?? {
            let openAI = OpenAIProvider()
            return openAI.isConfigured ? openAI : nil
        }()
        self.defaultProvider = resolved
        self.maxRetries = maxRetries
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let provider = providers[request.modelTier] ?? defaultProvider
        guard let provider else {
            throw LLMClientError.noProvider
        }

        var lastError: (any Error)?
        for attempt in 0...maxRetries {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let text = try await provider.complete(prompt: request.prompt)
                let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                // Use more accurate token estimation: ~3.5 chars per token for English
                let estimatedTokens = max(1, text.count / 3)

                lockQueue.sync {
                    requestCount += 1
                    totalTokens += estimatedTokens
                }

                return LLMResponse(
                    text: text,
                    modelTier: request.modelTier,
                    tokenCount: estimatedTokens,
                    latencyMs: latencyMs
                )
            } catch let error as LLMClientError {
                lastError = error
                // Exponential backoff with jitter on rate limit errors
                if case .rateLimited = error, attempt < maxRetries {
                    let delay = calculateBackoff(attempt: attempt)
                    Log.warn("Rate limited, retrying after \(delay)s (attempt \(attempt + 1)/\(maxRetries + 1))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? LLMClientError.noProvider
    }

    /// Calculate exponential backoff with jitter for rate limiting
    private func calculateBackoff(attempt: Int) -> TimeInterval {
        // Exponential: 1s, 2s, 4s, 8s... up to max
        let exponentialDelay = rateLimitMinDelay * pow(2.0, Double(attempt))
        let cappedDelay = min(exponentialDelay, rateLimitMaxDelay)
        // Add jitter (±25%)
        let jitter = cappedDelay * 0.25 * (Double.random(in: -1...1))
        return cappedDelay + jitter
    }

    public var diagnostics: LLMClientDiagnostics {
        lockQueue.sync {
            return LLMClientDiagnostics(
                requestCount: requestCount,
                totalTokens: totalTokens
            )
        }
    }
}

public struct LLMClientDiagnostics: Sendable {
    public let requestCount: Int
    public let totalTokens: Int
}

public enum LLMClientError: Error, Sendable {
    case noProvider
    case rateLimited
    case timeout
    case transportError(String)
}
