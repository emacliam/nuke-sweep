import XCTest
@testable import Nuke

/// These tests are skipped unless the matching live-test environment variables are set.
/// They only request provider model lists, never scan data or file paths.
final class LiveProviderTests: XCTestCase {
    private func value(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    func testOpenAICompatibleModelListIfConfigured() async throws {
        guard let key = value("NUKE_LIVE_OPENAI_KEY") else {
            throw XCTSkip("Set NUKE_LIVE_OPENAI_KEY to run the OpenAI-compatible live check.")
        }
        let base = value("NUKE_LIVE_OPENAI_BASE") ?? "https://api.openai.com/v1"
        let model = value("NUKE_LIVE_OPENAI_MODEL") ?? "gpt-4o-mini"
        let provider = try OpenAICompatibleProvider(name: "Live OpenAI-compatible", baseURL: base, model: model, key: key)
        let check = try await provider.check()
        XCTAssertFalse(check.models.isEmpty, "Provider returned no models")
    }

    func testAnthropicModelListIfConfigured() async throws {
        guard let key = value("NUKE_LIVE_ANTHROPIC_KEY") else {
            throw XCTSkip("Set NUKE_LIVE_ANTHROPIC_KEY to run the Anthropic live check.")
        }
        let check = try await AnthropicAPI.check(key: key)
        XCTAssertFalse(check.models.isEmpty, "Provider returned no models")
    }

    func testGeminiModelListIfConfigured() async throws {
        guard let key = value("NUKE_LIVE_GEMINI_KEY") else {
            throw XCTSkip("Set NUKE_LIVE_GEMINI_KEY to run the Gemini live check.")
        }
        let check = try await GeminiAPI.check(key: key)
        XCTAssertFalse(check.models.isEmpty, "Provider returned no models")
    }

    func testDeepSeekModelListIfConfigured() async throws {
        guard let key = value("NUKE_LIVE_DEEPSEEK_KEY") else {
            throw XCTSkip("Set NUKE_LIVE_DEEPSEEK_KEY to run the DeepSeek live check.")
        }
        let provider = try OpenAICompatibleProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-chat", key: key)
        let check = try await provider.check()
        XCTAssertFalse(check.models.isEmpty, "Provider returned no models")
    }

    func testLocalModelListIfConfigured() async throws {
        guard let base = value("NUKE_LIVE_LOCAL_BASE") else {
            throw XCTSkip("Set NUKE_LIVE_LOCAL_BASE (for example http://127.0.0.1:11434/v1) to run the local live check.")
        }
        let model = value("NUKE_LIVE_LOCAL_MODEL") ?? "llama3.2"
        let provider = try OpenAICompatibleProvider(name: "Live local", baseURL: base, model: model, key: nil)
        let check = try await provider.check()
        XCTAssertFalse(check.models.isEmpty, "Provider returned no models")
    }
}
