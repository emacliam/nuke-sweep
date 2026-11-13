import XCTest
@testable import Nuke

private final class AuditStreamProtocol: URLProtocol, @unchecked Sendable {
    static let counterLock = NSLock()
    static var chunks = 0
    static var declaredLength: String?
    private let lock = NSLock()
    private var stopped = false
    private var sent = 0
    static func reset(length: String? = nil) { counterLock.lock(); chunks = 0; declaredLength = length; counterLock.unlock() }
    static var count: Int { counterLock.lock(); defer { counterLock.unlock() }; return chunks }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.counterLock.lock(); let length = Self.declaredLength; Self.counterLock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: length.map { ["Content-Length":$0] })!, cacheStoragePolicy: .notAllowed)
        send()
    }
    private func send() {
        lock.lock(); guard !stopped else { lock.unlock(); return }; sent += 1; let current = sent; lock.unlock()
        Self.counterLock.lock(); Self.chunks += 1; Self.counterLock.unlock()
        client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 4096))
        if current == 100 { client?.urlProtocolDidFinishLoading(self); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(4)) { [weak self] in self?.send() }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}
final class BoundedAITransferTests: XCTestCase {
    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuditStreamProtocol.self]; return config
    }
    func testUnknownLengthBodyStopsBeforeWholeTransferArrives() async {
        AuditStreamProtocol.reset()
        do {
            _ = try await BoundedAITransfer.receive(URLRequest(url: URL(string:"https://audit.invalid/stream")!), configuration: configuration(), maximum: 16_384)
            XCTFail("Expected transfer budget refusal")
        } catch let error as AIProviderError {
            guard case .responseTooLarge = error else { return XCTFail("Wrong failure: \(error)") }
        } catch { XCTFail("Wrong failure: \(error)") }
        XCTAssertLessThan(AuditStreamProtocol.count, 100)
    }
    func testDeclaredOversizeIsRejectedAtHeaders() async {
        AuditStreamProtocol.reset(length: "99999999")
        do {
            _ = try await BoundedAITransfer.receive(URLRequest(url: URL(string:"https://audit.invalid/stream")!), configuration: configuration(), maximum: 16_384)
            XCTFail("Expected header budget refusal")
        } catch let error as AIProviderError {
            guard case .responseTooLarge = error else { return XCTFail("Wrong failure: \(error)") }
        } catch { XCTFail("Wrong failure: \(error)") }
        XCTAssertLessThan(AuditStreamProtocol.count, 100)
    }
    func testTaskCancellationStopsTransfer() async throws {
        AuditStreamProtocol.reset()
        let config = configuration()
        let task = Task {
            do { _ = try await BoundedAITransfer.receive(URLRequest(url: URL(string:"https://audit.invalid/stream")!), configuration: config); return false }
            catch { return Task.isCancelled }
        }
        try await Task.sleep(for: .milliseconds(20)); task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertLessThan(AuditStreamProtocol.count, 100)
    }
}
