import Foundation

/// Covers, fetched two at a time.
///
/// The cap is not a client preference: the server shares a **two-transfer**
/// budget between both of its byte routes (covers included) and answers a third
/// with `503 busy` + `Retry-After`, because the process's file I/O shares a
/// four-slot threadpool with the app's own cover loads and catalog writes. A grid
/// that fanned out 60 covers would get 58 refusals *and* freeze the Mac's library
/// view; a grid that pipelines two at a time treats the platform as it is.
/// (Measured on the Mac side: a `cover_full.jpg` is ~79 KB and reads in 0.05 s
/// when the share is healthy, so a cover grid is latency-bound, not
/// bandwidth-bound — two at a time is ~30 sequential round trips per 60-cover
/// screen, roughly 1.5 s, which is what "loads as you scroll" should feel like.)
actor CoverPipeline {
    /// Must match the server's budget. A wider window is not a speed-up; it is a
    /// queue of refusals.
    static let maxInFlight = 2

    private let session: URLSession
    private var inFlight = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches one cover, retrying a `503 busy` on the server's own `Retry-After`.
    func data(for request: URLRequest, attempts: Int = 3) async throws -> Data {
        var lastError: ClientError = .unreachable("the cover was never attempted")
        for attempt in 0..<max(1, attempts) {
            await acquire()
            do {
                let (data, response) = try await session.data(for: request)
                release()
                try MusaeumClient.check(response, body: data)
                return data
            } catch let error as ClientError {
                release()
                lastError = error
                guard error.isRetryable, attempt < attempts - 1 else { throw error }
                let delay = retryDelay(error)
                try await Task.sleep(for: .seconds(delay))
            } catch {
                release()
                if error is CancellationError { throw error }
                lastError = .unreachable((error as NSError).localizedDescription)
                guard attempt < attempts - 1 else { throw lastError }
            }
        }
        throw lastError
    }

    private func retryDelay(_ error: ClientError) -> TimeInterval {
        switch error {
        case let .busy(retryAfter), let .libraryOffline(retryAfter): retryAfter ?? 1
        case .unreachable: 1
        default: 1
        }
    }

    private func acquire() async {
        if inFlight < Self.maxInFlight {
            inFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    private func release() {
        if let next = waiting.first {
            waiting.removeFirst()
            next.resume()
        } else {
            inFlight = max(0, inFlight - 1)
        }
    }
}
