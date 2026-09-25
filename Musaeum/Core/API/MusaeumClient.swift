import Foundation

/// Every ordinary outcome the contract describes, as a case rather than a string.
/// `docs/rest-api.md`'s failure table is written for a client that is *not* a
/// dependency of the server, so none of these are exceptional: the app renders
/// them (invariant 5).
enum ClientError: Error, Equatable, CustomStringConvertible {
    /// Nothing answered — the Mac is asleep, off the tailnet, or the app is closed.
    case unreachable(String)
    /// The base URL the user typed is not a URL this client can build requests from.
    case badBaseURL(String)
    /// 401 — a wrong or rotated credential. Carries `WWW-Authenticate: Bearer`.
    case unauthorized
    /// 400 — the request this client composed is malformed. A bug here, not a state.
    case badRequest(String?)
    /// 404 — an unknown book, an unknown path, a format the book does not hold,
    /// a file that is gone. Uniformly reason-free, so the client cannot map what
    /// the Mac holds.
    case notFound
    /// 416 — a Range the file cannot satisfy (slice 2's resumption).
    case rangeNotSatisfiable
    /// 413 `content too large` — an upload's body past what the route will carry.
    ///
    /// **Not retryable, and that is the whole reason the case exists.** The same
    /// bytes cannot fit on the next attempt either, so a retry sends the entire
    /// file again to hear the same refusal. Before this case existed the status
    /// fell to `mapStatus`'s `default`, which is `unreachable` — so a server that
    /// had answered correctly and deliberately was reported to the reader as *the
    /// Mac is not answering*, and the request was then retried on a file that can
    /// never fit. Two repos' vocabularies have to move together (`musaeum`'s
    /// slice 2 added the status; this is the client's half), and no case in either
    /// suite could see the gap until the client existed.
    case tooLarge
    /// 503 `busy` — too many byte transfers in flight. **Retryable.**
    case busy(retryAfter: TimeInterval?)
    /// 503 `library offline` — the share is not mounted, so there are no bytes.
    case libraryOffline(retryAfter: TimeInterval?)
    /// 500 — a handler failed; the server keeps serving.
    case server
    /// The server speaks a contract version this app does not.
    case unsupportedAPIVersion(Int)
    /// The payload did not match the contract.
    case decoding(ContractError)

    var description: String {
        switch self {
        case let .unreachable(detail): "the Mac is not answering — \(detail)"
        case let .badBaseURL(text): "“\(text)” is not a URL this app can use"
        case .unauthorized: "the Mac refused the token — check it against the one in Musaeum's Settings"
        case let .badRequest(detail): detail.map { "the request was refused: \($0)" } ?? "the request was refused"
        case .notFound: "the Mac does not have that"
        case .rangeNotSatisfiable: "the download could not resume — the file changed"
        case .tooLarge: "the Mac refused the upload — content too large for it to take"
        case .busy: "the Mac is busy transferring; retrying"
        case .libraryOffline: "the library share is not mounted on the Mac"
        case .server: "the Mac hit an error serving that"
        case let .unsupportedAPIVersion(v): "the Mac speaks contract version \(v); this app speaks \(supportedAPIVersion)"
        case let .decoding(err): err.description
        }
    }

    /// Whether the same request is worth sending again unchanged.
    var isRetryable: Bool {
        switch self {
        case .busy, .libraryOffline, .unreachable: true
        default: false
        }
    }

    var isCredentialProblem: Bool { self == .unauthorized }
}

/// The HTTP client for one configured server. It composes requests, maps statuses
/// to `ClientError`, and decodes strictly (invariant 4). It holds no state and
/// nothing about a view.
struct MusaeumClient: Sendable {
    let base: URL
    let token: String
    let session: URLSession

    init(base: URL, token: String, session: URLSession = .shared) {
        self.base = base
        self.token = token
        self.session = session
    }

    // MARK: Request composition — pure, so a test decides it (AC5)

    static func request(
        base: URL,
        token: String,
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil
    ) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components?.url ?? base)
        request.httpMethod = method
        // The one place the credential appears (invariant 10).
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func request(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil
    ) -> URLRequest {
        Self.request(base: base, token: token, path: path, query: query, method: method, body: body)
    }

    /// The one write's body: `{ "percent": 0.42, "at": "…" }`.
    ///
    /// `at` is **absent**, not `null`, when it is not sent — the contract draws
    /// exactly that distinction ("send it for a report that was queued; omit it for
    /// a live read, when the server's clock is the truth"), so the encoder writes
    /// the key only when there is a value. The fraction is clamped: the contract
    /// refuses `60` rather than reading it as `0.6`.
    static func readingBody(percent: Double, at: Date?) throws -> Data {
        try JSONEncoder().encode(ReadingRequestBody(
            percent: percent.clampedToUnit(),
            at: at.map(ISO8601.string)
        ))
    }

    // MARK: Routes

    /// How long the connect check waits. **A tailnet that is down does not refuse,
    /// it is silent**, so on the session's default 60 s the library sat on a
    /// spinner for a minute before saying anything — with the downloaded shelf,
    /// which needs no Mac, out of reach. The health payload is a few hundred bytes
    /// over the tailnet; a Mac that cannot send it in this long is not answering.
    static let healthTimeout: TimeInterval = 5

    /// The connect check. Refuses a contract version this app does not speak —
    /// half-decoding a payload whose version moved is how a client lies.
    func health() async throws -> Health {
        var check = request(path: "api/health")
        check.timeoutInterval = Self.healthTimeout
        let health: Health = try await sendJSON(check)
        guard health.apiVersion == supportedAPIVersion else {
            throw ClientError.unsupportedAPIVersion(health.apiVersion)
        }
        return health
    }

    /// One page of the library, or of a search when `q` is present. The defaults
    /// are the contract's own (`limit` 100, `offset` 0, `sort` title).
    ///
    /// `filters` arrives **already composed** — by `LibraryFilters`, which owns
    /// the rule that an axis with nothing in it is not a parameter at all. The
    /// client appends items it did not build: what a filter *is* belongs to the
    /// file that knows the contract's vocabulary, and a second place that chose
    /// parameter names is a second place a typo can become a 400.
    func library(
        limit: Int = 100,
        offset: Int = 0,
        sort: String? = nil,
        direction: String? = nil,
        query: String? = nil,
        filters: [URLQueryItem] = []
    ) async throws -> LibraryPage {
        var items: [URLQueryItem] = []
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        if let direction { items.append(URLQueryItem(name: "dir", value: direction)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        items.append(contentsOf: filters)
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        items.append(URLQueryItem(name: "offset", value: String(offset)))
        return try await sendJSON(request(path: "api/library", query: items))
    }

    func facets() async throws -> Facets {
        try await sendJSON(request(path: "api/library/facets"))
    }

    func book(id: String) async throws -> ContractBook {
        try await sendJSON(request(path: "api/books/\(id)"))
    }

    /// The book's payload **as the server sent it**. A download keeps these exact
    /// bytes rather than a re-encoded struct, so reading a downloaded book goes
    /// through the same strict decoder as a live response.
    func bookData(id: String) async throws -> Data {
        try await sendBytes(request(path: "api/books/\(id)"))
    }

    /// The cover's bytes. `version` is the book's `cover.version`: the route
    /// ignores the parameter, and it is what stops a replaced cover being
    /// answered from a cache.
    func coverRequest(id: String, size: String = "full", version: String? = nil) -> URLRequest {
        var items = [URLQueryItem(name: "size", value: size)]
        if let version { items.append(URLQueryItem(name: "v", value: version)) }
        return request(path: "api/books/\(id)/cover", query: items)
    }

    func cover(id: String, size: String = "full", version: String? = nil) async throws -> Data {
        try await sendBytes(coverRequest(id: id, size: size, version: version))
    }

    /// The book's bytes, by id and **format** — never by path, which the wire
    /// deliberately does not carry (invariant 2).
    func fileRequest(id: String, format: String) -> URLRequest {
        request(path: "api/books/\(id)/file", query: [URLQueryItem(name: "format", value: format)])
    }

    /// Downloads a book to a temporary file the caller owns, and reports the bytes.
    /// Whole-file only: resumption is deferred (spec CD6), and the contract's
    /// `Range` support is slice 2's.
    func download(id: String, format: String) async throws -> (file: URL, bytes: Int) {
        for attempt in 0...2 {
            let request = fileRequest(id: id, format: format)
            do {
                let (temporary, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClientError.unreachable("no HTTP response") }
                switch http.statusCode {
                case 200:
                    let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? Int) ?? nil
                    return (temporary, size ?? 0)
                case 206:
                    return (temporary, 0)
                default:
                    if (200..<300).contains(http.statusCode) { return (temporary, 0) }
                    var failure: ClientError = .server
                    do {
                        try Self.mapStatus(http, body: try? Data(contentsOf: temporary))
                    } catch let error as ClientError {
                        failure = error
                    }
                    if failure.isRetryable, attempt < 2 {
                        try await Task.sleep(for: .seconds(retryDelay(failure) ?? 1))
                        continue
                    }
                    throw failure
                }
            } catch let error as ClientError {
                if error.isRetryable, attempt < 2 {
                    try await Task.sleep(for: .seconds(retryDelay(error) ?? 1))
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ClientError.unreachable(error.localizedDescription)
            }
        }
        throw ClientError.unreachable("the transfer never settled")
    }

    // MARK: The one write

    /// `PUT /api/books/{id}/reading` — the report that makes a position travel.
    ///
    /// `at` is the phone's own clock, and it belongs on the wire **only for a
    /// report that was queued**: the contract says so, and the Mac's D6 compares it
    /// against the row's `reading_updated_at`. A live read passes `nil` so the
    /// server's clock is the truth — which is what stops a phone whose clock is
    /// behind from having its own report refused as stale.
    ///
    /// The reply is `200` whether or not the report was applied: `applied: false`
    /// is the stale refusal, and it is an answer rather than a failure.
    func reportReading(id: String, percent: Double, at: Date? = nil) async throws -> ReadingResult {
        let request = request(
            path: "api/books/\(id)/reading",
            method: "PUT",
            body: try Self.readingBody(percent: percent, at: at)
        )
        return try await sendJSON(request)
    }

    // MARK: The second write — a book the phone sends

    /// `POST /api/books?format=&filename=` — the book's **bytes as the body**,
    /// which is the shape the contract asks for ("not JSON, and not
    /// `multipart/form-data`"): the client already holds the file, and the body is
    /// the file.
    ///
    /// **The body is a file the session reads (`upload(for:fromFile:)`), never
    /// `httpBody`.** A `Data` body is an in-memory upload: it reads correctly, and
    /// it dies on the phone with the library's own worst case — the Mac's census
    /// measured a 528 MiB EPUB — while a simulator run on a seed book shows
    /// nothing. R1 measured the two against each other.
    ///
    /// `Content-Type` is deliberately **absent**. The contract says it is not read
    /// ("the bytes are the body, and `Content-Type` is not read"), and the answer
    /// to "what is this?" is already the `format` parameter, which the route
    /// trusts, plus the `filename` it names the row by.
    func uploadBook(file: URL, format: String, filename: String) async throws -> ImportResult {
        let request = Self.uploadRequest(base: base, token: token, format: format, filename: filename)
        do {
            let (data, response) = try await session.upload(for: request, fromFile: file)
            try Self.check(response, body: data)
            do {
                return try JSONDecoder().decode(ImportResult.self, from: data)
            } catch let error as ContractError {
                throw ClientError.decoding(error)
            } catch let error as DecodingError {
                throw ClientError.decoding(Self.contractError(from: error))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.unreachable((error as NSError).localizedDescription)
        }
    }

    /// The upload's request, composed where a case can read it: the two parameters
    /// the contract requires, the bearer header, and **nothing else** — no body
    /// (the bytes travel as the session's file), no `Content-Type`, and no
    /// invented header. `filename` is the wire's parameter name and is the name
    /// the Mac titles the row by when the import finds no metadata of its own, so
    /// it travels exactly as the file is named on the phone.
    static func uploadRequest(base: URL, token: String, format: String, filename: String) -> URLRequest {
        request(
            base: base,
            token: token,
            path: "api/books",
            query: [
                URLQueryItem(name: "format", value: format),
                URLQueryItem(name: "filename", value: filename),
            ],
            method: "POST"
        )
    }

    // MARK: Plumbing

    private func sendJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await perform(request)
        try Self.check(response, body: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as ContractError {
            throw ClientError.decoding(error)
        } catch let error as DecodingError {
            throw ClientError.decoding(Self.contractError(from: error))
        }
    }

    private func sendBytes(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await perform(request)
        try Self.check(response, body: data)
        return data
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ClientError.unreachable((error as NSError).localizedDescription)
        }
    }

    static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.unreachable("no HTTP response") }
        try mapStatus(http, body: body)
    }

    static func mapStatus(_ http: HTTPURLResponse, body: Data?) throws {
        guard !(200..<300).contains(http.statusCode) else { return }
        let payload = body.flatMap { try? JSONDecoder().decode(APIErrorPayload.self, from: $0) }
        switch http.statusCode {
        case 400: throw ClientError.badRequest(payload?.error)
        case 401: throw ClientError.unauthorized
        case 404: throw ClientError.notFound
        case 413: throw ClientError.tooLarge
        case 416: throw ClientError.rangeNotSatisfiable
        case 500: throw ClientError.server
        case 503:
            let retry = retryAfter(http)
            if payload?.error == "library offline" { throw ClientError.libraryOffline(retryAfter: retry) }
            throw ClientError.busy(retryAfter: retry)
        default:
            throw ClientError.unreachable("unexpected status \(http.statusCode)")
        }
    }

    static func retryAfter(_ http: HTTPURLResponse) -> TimeInterval? {
        (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
    }

    private func retryDelay(_ error: ClientError) -> TimeInterval? {
        switch error {
        case let .busy(retryAfter), let .libraryOffline(retryAfter): retryAfter
        default: nil
        }
    }

    /// A `DecodingError` from a payload that never reached our `StrictObject`
    /// (a wrong type at the root, a truncated body) said in the contract's terms.
    static func contractError(from error: DecodingError) -> ContractError {
        switch error {
        case let .keyNotFound(key, context):
            .missingField(key.stringValue, at: context.codingPath.map(\.stringValue).joined(separator: "."))
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            .malformedField(
                context.codingPath.last?.stringValue ?? "payload",
                at: context.codingPath.map(\.stringValue).joined(separator: "."),
                value: context.debugDescription
            )
        case let .dataCorrupted(context):
            .malformedField("payload", at: context.codingPath.map(\.stringValue).joined(separator: "."), value: context.debugDescription)
        @unknown default:
            .malformedField("payload", at: "", value: String(describing: error))
        }
    }
}

/// The body of the one write, spelled by hand so that **absence is real
/// absence**: synthesized `Codable` would leave this to `encodeIfPresent`'s own
/// behaviour, and the contract's distinction between "no `at`" (a live read) and
/// "`at` present" (a queued report) is the whole of D6's client half.
private struct ReadingRequestBody: Encodable {
    let percent: Double
    let at: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(percent, forKey: AnyCodingKey("percent"))
        try container.encodeIfPresent(at, forKey: AnyCodingKey("at"))
    }
}
