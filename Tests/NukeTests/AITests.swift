import XCTest
@testable import Nuke

final class AITests: XCTestCase {
    func testContextRedactsAbsoluteHomePaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("code/example/dist")
        let item = DiskItem(url: url, size: 1_000, allocated: 1_000, directory: true, symlink: false, modified: nil, identity: nil, incomplete: false)
        let evidence = CleanupEvidence(kind: .buildOutput, detail: "Generated build output.", rebuild: "Rebuild from source.", gitIgnored: true)
        let scope = DeveloperScope(label: "Example", path: home.appendingPathComponent("code/example").path, cleanupAllowed: true, exclusions: [])
        let context = AIContext.make(item: item, evidence: evidence, scope: scope)
        XCTAssertEqual(context.relativePath, "~/code/example/dist")
        XCTAssertEqual(context.scopeLabel, "Example")
        XCTAssertEqual(context.scopePolicy, "cleanup_after_review")
        XCTAssertFalse(context.jsonString.contains(home.path))
        XCTAssertFalse(context.jsonString.contains("/Users/"))
    }

    func testContextOutsideHomeUsesTailComponents() {
        let context = AIContext.make(
            item: DiskItem(url: URL(fileURLWithPath: "/Applications/Example.app"), size: 10, allocated: 10, directory: true, symlink: false, modified: nil, identity: nil, incomplete: false),
            evidence: CleanupEvidence(kind: .unknown, detail: "Unknown.", rebuild: nil, gitIgnored: false),
            scope: nil
        )
        XCTAssertEqual(context.relativePath, "Applications/Example.app")
        XCTAssertTrue(context.scopeLabel == nil)
    }

    func testSuggestionParsesPlainAndFencedJSON() throws {
        let plain = #"{"category":"build_output","confidence":0.82,"explanation":"Compiled output.","rebuild":"next build","risks":["Rebuild needed"]}"#
        let parsed = try AISuggestion.parse(plain)
        XCTAssertEqual(parsed.category, .buildOutput)
        XCTAssertEqual(parsed.confidence, 0.82)
        XCTAssertEqual(parsed.rebuild, "next build")
        XCTAssertEqual(parsed.risks, ["Rebuild needed"])

        let fenced = """
        ```json
        {"category":"unknown","confidence":0.2,"explanation":"Not enough evidence.","rebuild":null,"risks":[]}
        ```
        """
        XCTAssertEqual(try AISuggestion.parse(fenced).category, .unknown)
    }

    func testSuggestionRejectsBadFields() {
        XCTAssertThrowsError(try AISuggestion.parse(#"{"category":"cache","confidence":2,"explanation":"x","rebuild":null,"risks":[]}"#))
        XCTAssertThrowsError(try AISuggestion.parse(#"{"category":"something","confidence":0.5,"explanation":"x","rebuild":null,"risks":[]}"#))
        XCTAssertThrowsError(try AISuggestion.parse("no json"))
        XCTAssertThrowsError(try AISuggestion.parse(#"{"category":"cache","confidence":0.5,"explanation":"","rebuild":null,"risks":[]}"#))
    }


    func testPlanDropsBlockedAndUnknownNames() throws {
        let context = AIPlanContext(instruction: "Clean build output", scopeLabel: "Example", scopePolicy: "cleanup_after_review", items: [
            AIPlanItem(name: "dist", sizeBytes: 1_000, kind: "folder", evidence: "Build output", blocked: false),
            AIPlanItem(name: "src", sizeBytes: 2_000, kind: "folder", evidence: "Source", blocked: true)
        ])
        let raw = #"{"select":["dist","src","ghost"],"keep":["ghost"],"reasoning":"Keep source.","risks":["Rebuild later."],"confidence":0.7}"#
        let resolution = try AIPlanSuggestion.parse(raw).resolved(against: context)
        XCTAssertEqual(resolution.selected, ["dist"])
        XCTAssertEqual(resolution.omitted, ["src", "ghost"])
        XCTAssertTrue(resolution.kept.isEmpty)
        XCTAssertEqual(resolution.confidence, 0.7)
        XCTAssertFalse(context.jsonString.contains("/Users/"))
    }

    func testPlanRejectsInvalidConfidence() {
        XCTAssertThrowsError(try AIPlanSuggestion.parse(#"{"select":[],"keep":[],"reasoning":"x","risks":[],"confidence":1.5}"#))
        XCTAssertThrowsError(try AIPlanSuggestion.parse(#"{"select":[],"keep":[],"reasoning":"","risks":[],"confidence":0.5}"#))
    }


    func testOpenAICompatibleBaseURLPolicy() {
        XCTAssertNoThrow(try OpenAICompatibleProvider(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", key: "k"))
        XCTAssertNoThrow(try OpenAICompatibleProvider(name: "Local", baseURL: "http://127.0.0.1:11434/v1", model: "llama3.2", key: nil))
        XCTAssertThrowsError(try OpenAICompatibleProvider(name: "Bad", baseURL: "http://example.com/v1", model: "m", key: "k"))
        XCTAssertThrowsError(try OpenAICompatibleProvider(name: "Bad", baseURL: "ftp://example.com/v1", model: "m", key: "k"))
    }

    func testProviderLocalityAndKeyRequirements() {
        let deepSeek = AIProviderConfig.make(.deepSeek)
        XCTAssertFalse(deepSeek.isLocal)
        XCTAssertTrue(deepSeek.requiresKey)
        var local = AIProviderConfig.make(.local)
        XCTAssertTrue(local.isLocal)
        XCTAssertFalse(local.requiresKey)
        local.baseURL = "https://example.com/v1"
        XCTAssertFalse(local.isLocal)
        let openAI = AIProviderConfig.make(.openAICompatible)
        XCTAssertFalse(openAI.isLocal)
        XCTAssertTrue(openAI.requiresKey)
        var loopback = AIProviderConfig.make(.openAICompatible)
        loopback.baseURL = "http://localhost:1234/v1"
        XCTAssertTrue(loopback.isLocal)
        XCTAssertFalse(loopback.requiresKey)
    }

    func testBaseURLValidation() {
        XCTAssertTrue(AISettings.isValidBaseURL("https://api.openai.com/v1"))
        XCTAssertTrue(AISettings.isValidBaseURL("http://127.0.0.1:11434/v1"))
        XCTAssertFalse(AISettings.isValidBaseURL("http://example.com/v1"))
        XCTAssertFalse(AISettings.isValidBaseURL("https://api.openai.com/v1?key=secret"))
    }


    func testOpenAICompatibleChatPaths() throws {
        let openAI = try OpenAICompatibleProvider(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "m", key: "k")
        XCTAssertEqual(openAI.chatURL.path, "/v1/chat/completions")
        let deepSeek = try OpenAICompatibleProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "m", key: "k")
        XCTAssertEqual(deepSeek.chatURL.path, "/chat/completions")
        let local = try OpenAICompatibleProvider(name: "Local", baseURL: "http://127.0.0.1:11434/v1", model: "m", key: nil)
        XCTAssertEqual(local.chatURL.path, "/v1/chat/completions")
    }

    func testProviderConfigCodableRoundTrip() throws {
        var provider = AIProviderConfig.make(.openAICompatible, name: "OpenRouter")
        provider.baseURL = "https://openrouter.ai/api/v1"
        provider.model = "openai/gpt-4o-mini"
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(AIProviderConfig.self, from: data)
        XCTAssertEqual(decoded, provider)
        XCTAssertFalse(decoded.isLocal)
        XCTAssertTrue(decoded.requiresKey)
    }


    func testPlanExclusionsWinOverSelectionAndDropUnknownNames() throws {
        let context = AIPlanContext(instruction: "Clean output and keep node_modules", scopeLabel: "Example", scopePolicy: "cleanup_after_review", items: [
            AIPlanItem(name: "dist", sizeBytes: 1_000, kind: "folder", evidence: "Build output", blocked: false),
            AIPlanItem(name: "node_modules", sizeBytes: 2_000, kind: "folder", evidence: "Dependencies", blocked: true)
        ])
        let raw = #"{"select":["dist","node_modules"],"keep":[],"exclude":["node_modules","ghost"],"reasoning":"Keep dependencies.","risks":[],"confidence":0.8}"#
        let resolution = try AIPlanSuggestion.parse(raw).resolved(against: context)
        XCTAssertEqual(resolution.selected, ["dist"])
        XCTAssertEqual(resolution.excluded, ["node_modules"])
        XCTAssertEqual(resolution.omitted, ["node_modules"])
    }

    func testOnlyLoopbackEndpointsAreAccepted() {
        XCTAssertTrue(AISettings.isLoopbackEndpoint("http://127.0.0.1:11434/v1/chat/completions"))
        XCTAssertTrue(AISettings.isLoopbackEndpoint("http://localhost:11434/v1/chat/completions"))
        XCTAssertFalse(AISettings.isLoopbackEndpoint("https://api.deepseek.com/chat/completions"))
        XCTAssertFalse(AISettings.isLoopbackEndpoint("http://192.168.1.20:11434/v1/chat/completions"))
        XCTAssertFalse(AISettings.isLoopbackEndpoint("http://127.0.0.1:11434"))
    }
}

final class AIHTTPTests: XCTestCase {
    private let endpoint = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    private var context: AIContext {
        AIContext(name: "dist", kind: "folder", relativePath: "~/code/example/dist", sizeBytes: 1_000, directory: true, symlink: false, incomplete: false, evidence: "Build output", evidenceDetail: "Generated build output.", rebuild: "Rebuild.", gitIgnored: true, scopeLabel: "Example", scopePolicy: "cleanup_after_review")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testHTTPFailureStatuses() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await AIHTTP.explain(context, endpoint: endpoint, model: "m", key: nil, session: session())
            XCTFail("Expected an HTTP error")
        } catch let error as AIProviderError {
            guard case .http(401) = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testNetworkFailureIsWrapped() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await AIHTTP.explain(context, endpoint: endpoint, model: "m", key: nil, session: session())
            XCTFail("Expected a network error")
        } catch let error as AIProviderError {
            guard case .network = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMalformedProviderResponseIsRejected() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("not json".utf8))
        }
        do {
            _ = try await AIHTTP.explain(context, endpoint: endpoint, model: "m", key: nil, session: session())
            XCTFail("Expected an empty-response error")
        } catch let error as AIProviderError {
            guard case .emptyResponse = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testValidResponseIsParsed() async throws {
        let content = #"{"category":"build_output","confidence":0.8,"explanation":"Generated output.","rebuild":"Rebuild.","risks":[]}"#
        let object: [String: Any] = ["choices": [["message": ["content": content]]]]
        let body = try! JSONSerialization.data(withJSONObject: object)
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let suggestion = try await AIHTTP.explain(context, endpoint: endpoint, model: "m", key: nil, session: session())
        XCTAssertEqual(suggestion.category, .buildOutput)
    }

    func testPlanResponseIsParsed() async throws {
        let content = #"{"select":["dist"],"keep":[],"reasoning":"Build output.","risks":[],"confidence":0.8}"#
        let object: [String: Any] = ["choices": [["message": ["content": content]]]]
        let body = try! JSONSerialization.data(withJSONObject: object)
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let planContext = AIPlanContext(instruction: "Clean output", scopeLabel: "Example", scopePolicy: "cleanup_after_review", items: [
            AIPlanItem(name: "dist", sizeBytes: 1_000, kind: "folder", evidence: "Build output", blocked: false)
        ])
        let suggestion = try await AIHTTP.plan(planContext, endpoint: endpoint, model: "m", key: nil, session: session())
        XCTAssertEqual(suggestion.select, ["dist"])
    }

    func testModelDiscoveryUsesModelsEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            let body = #"{"data":[{"id":"llama3"},{"id":"qwen2.5"}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let check = try await AIHTTP.models(endpoint: endpoint, key: nil, session: session())
        XCTAssertEqual(check.models, ["llama3", "qwen2.5"])
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AnthropicGeminiTests: XCTestCase {
    private var context: AIContext {
        AIContext(name: "dist", kind: "folder", relativePath: "~/code/example/dist", sizeBytes: 1_000, directory: true, symlink: false, incomplete: false, evidence: "Build output", evidenceDetail: "Generated build output.", rebuild: "Rebuild.", gitIgnored: true, scopeLabel: "Example", scopePolicy: "cleanup_after_review")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testAnthropicExplainUsesMessagesEndpointAndHeaders() async throws {
        let suggestion = #"{"category":"build_output","confidence":0.8,"explanation":"Generated output.","rebuild":"Rebuild.","risks":[]}"#
        let object: [String: Any] = ["content": [["type": "text", "text": suggestion]]]
        let body = try JSONSerialization.data(withJSONObject: object)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let result = try await AnthropicAPI.explain(context, key: "test-key", model: "claude-test", session: session())
        XCTAssertEqual(result.category, .buildOutput)
    }

    func testAnthropicModelDiscovery() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            let body = try! JSONSerialization.data(withJSONObject: ["data": [["id": "claude-a"], ["id": "claude-b"]]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let result = try await AnthropicAPI.check(key: "test-key", session: session())
        XCTAssertEqual(result.models, ["claude-a", "claude-b"])
    }

    func testGeminiExplainUsesGenerateContent() async throws {
        let suggestion = #"{"category":"cache","confidence":0.7,"explanation":"Cache data.","rebuild":null,"risks":[]}"#
        let object: [String: Any] = ["candidates": [["content": ["parts": [["text": suggestion]]]]]]
        let body = try JSONSerialization.data(withJSONObject: object)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1beta/models/gemini-2.5-flash:generateContent")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let result = try await GeminiAPI.explain(context, key: "test-key", model: "models/gemini-2.5-flash", session: session())
        XCTAssertEqual(result.category, .cache)
    }

    func testGeminiModelDiscoveryStripsPrefix() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1beta/models")
            let body = try! JSONSerialization.data(withJSONObject: ["models": [
                ["name": "models/gemini-2.5-flash", "supportedGenerationMethods": ["generateContent"]],
                ["name": "models/embedding-001", "supportedGenerationMethods": ["embedContent"]]
            ]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let result = try await GeminiAPI.check(key: "test-key", session: session())
        XCTAssertEqual(result.models, ["gemini-2.5-flash"])
    }

    func testNewProviderFlavorsAreCloudAndRequireKeys() {
        for flavor in [AIProviderFlavor.anthropic, .gemini] {
            let provider = AIProviderConfig.make(flavor)
            XCTAssertFalse(provider.isLocal)
            XCTAssertTrue(provider.requiresKey)
            XCTAssertTrue(provider.effectiveBaseURL.hasPrefix("https://"))
        }
    }
}

final class AIGrowthTests: XCTestCase {
    private func scan(daysAgo: Int, sizes: [String: Int64]) -> StoredScan {
        StoredScan(date: Date().addingTimeInterval(-Double(daysAgo) * 86_400), root: "/Users/example/projects/demo", sizes: sizes, categories: [:])
    }

    func testGrowthContextContainsOnlyAggregateAndNames() {
        let before = scan(daysAgo: 7, sizes: ["dist": 100, "src": 50])
        let after = scan(daysAgo: 0, sizes: ["dist": 1_000, "src": 50])
        let rows = GrowthComparison.rows(before: before.sizes, after: after.sizes)
        let context = AIGrowthContext(before: before, after: after, rows: rows, rootName: "demo")
        XCTAssertEqual(context.rootName, "demo")
        XCTAssertEqual(context.deltaBytes, 900)
        XCTAssertFalse(context.jsonString.contains("/Users/"))
        XCTAssertTrue(context.jsonString.contains("dist"))
    }

    func testGrowthSummaryParsesAndRejectsInvalid() throws {
        let valid = #"{"summary":"Generated output grew.","drivers":["dist increased"],"caveats":["Moves can appear as growth"],"confidence":0.7}"#
        let parsed = try AIGrowthSummary.parse(valid)
        XCTAssertEqual(parsed.drivers, ["dist increased"])
        XCTAssertThrowsError(try AIGrowthSummary.parse(#"{"summary":"","drivers":[],"caveats":[],"confidence":0.5}"#))
        XCTAssertThrowsError(try AIGrowthSummary.parse(#"{"summary":"x","drivers":[],"caveats":[],"confidence":1.5}"#))
    }

    func testGrowthTransportParsesProviderResponse() async throws {
        let growth = #"{"summary":"Generated output grew.","drivers":["dist increased"],"caveats":[],"confidence":0.6}"#
        let object: [String: Any] = ["choices": [["message": ["content": growth]]]]
        let body = try JSONSerialization.data(withJSONObject: object)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let context = AIGrowthContext(before: scan(daysAgo: 7, sizes: ["dist": 100]), after: scan(daysAgo: 0, sizes: ["dist": 1_000]), rows: GrowthComparison.rows(before: ["dist": 100], after: ["dist": 1_000]), rootName: "demo")
        let result = try await AIHTTP.growth(context, endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!, model: "m", key: "k", session: session)
        XCTAssertEqual(result.confidence, 0.6)
    }
}
