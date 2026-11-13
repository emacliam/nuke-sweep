import Foundation

/// Chunk-based transport: rejects oversized bodies while receiving them, rather
/// than buffering an entire response and applying a limit after completion.
final class BoundedAITransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximum: Int
    private var continuation: CheckedContinuation<Data, Error>?
    private var client: URLSession?
    private var task: URLSessionDataTask?
    private var body = Data()
    private var cancelled = false

    init(maximum: Int) { self.maximum = maximum }

    static func receive(_ request: URLRequest, configuration: URLSessionConfiguration, maximum: Int = 1_000_000) async throws -> Data {
        let transfer = BoundedAITransfer(maximum: maximum)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(request, configuration: configuration, continuation: continuation)
            }
        } onCancel: { transfer.cancel() }
    }

    private func start(_ request: URLRequest, configuration: URLSessionConfiguration, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let client = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.client = client
        let task = client.dataTask(with: request); self.task = task
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        let client = self.client; self.client = nil; task = nil; body = Data()
        lock.unlock()
        client?.invalidateAndCancel()
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.failure(AIProviderError.invalidResponse)); return
        }
        guard (200...299).contains(http.statusCode) else {
            completionHandler(.cancel); finish(.failure(AIProviderError.http(http.statusCode))); return
        }
        guard response.expectedContentLength <= Int64(maximum) else {
            completionHandler(.cancel); finish(.failure(AIProviderError.responseTooLarge)); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        guard data.count <= maximum - body.count else {
            lock.unlock(); finish(.failure(AIProviderError.responseTooLarge)); return
        }
        body.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(AIProviderError.network(error.localizedDescription))); return }
        lock.lock(); let data = body; lock.unlock()
        finish(.success(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
