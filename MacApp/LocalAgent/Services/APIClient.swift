import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding(let err): return "Decode error: \(err.localizedDescription)"
        case .emptyResponse: return "Empty response"
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    var baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = URL(string: "http://127.0.0.1:8501")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func health() async throws -> Bool {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("api/health"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String == "ok"
    }

    func setSession(userId: String) async throws -> SessionResponse {
        try await post("/api/session", body: ["user_id": userId])
    }

    func clearCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        let cookies = storage.cookies(for: baseURL) ?? storage.cookies ?? []
        for cookie in cookies {
            storage.deleteCookie(cookie)
        }
    }

    func getSession() async throws -> SessionResponse? {
        let url = baseURL.appendingPathComponent("api/session")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        if http.statusCode == 204 || data.isEmpty { return nil }
        if http.statusCode == 200 {
            if String(data: data, encoding: .utf8) == "null" { return nil }
            return try decoder.decode(SessionResponse.self, from: data)
        }
        throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    func getConfig() async throws -> AppConfig {
        try await get("/api/config")
    }

    func patchDefaults(_ fields: [String: Any]) async throws {
        let _: [String: Bool] = try await patch("/api/config/defaults", body: fields)
    }

    func listTasks() async throws -> [AgentTask] {
        let res: TasksResponse = try await get("/api/tasks")
        return res.tasks
    }

    func createTask(
        title: String = "New task",
        modelName: String? = nil,
        skills: [String]? = nil,
        mcpServers: [String]? = nil,
        guardrailEnabled: Bool = false,
        memoryEnabled: Bool = false
    ) async throws -> AgentTask {
        var body: [String: Any] = [
            "title": title,
            "guardrail_enabled": guardrailEnabled,
            "memory_enabled": memoryEnabled,
        ]
        if let modelName { body["model_name"] = modelName }
        if let skills { body["skills"] = skills }
        if let mcpServers { body["mcp_servers"] = mcpServers }
        return try await post("/api/tasks", body: body)
    }

    func patchTask(_ id: String, fields: [String: Any]) async throws -> AgentTask {
        try await patch("/api/tasks/\(id)", body: fields)
    }

    func deleteTask(_ id: String) async throws {
        let _: [String: Bool] = try await delete("/api/tasks/\(id)")
    }

    func getMessages(_ taskId: String) async throws -> [ChatMessage] {
        let res: MessagesResponse = try await get("/api/tasks/\(taskId)/messages")
        return res.messages
    }

    func uploadImage(fileURL: URL) async throws -> FileUploadResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("api/files/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let filename = fileURL.lastPathComponent
        let data = try Data(contentsOf: fileURL)
        let mime = mimeType(for: fileURL)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (respData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: respData, encoding: .utf8) ?? "")
        }
        return try decoder.decode(FileUploadResult.self, from: respData)
    }

    /// Stream chat SSE events. Calls `onEvent` on the cooperative context for each parsed event.
    func streamChat(
        taskId: String,
        prompt: String,
        files: [String],
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        let url = baseURL.appendingPathComponent("api/tasks/\(taskId)/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 600
        let payload: [String: Any] = ["prompt": prompt, "files": files]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, "SSE failed")
        }

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            if line.hasPrefix(":") { continue } // keepalive
            if line.hasPrefix("data:") {
                let jsonPart = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if jsonPart.isEmpty { continue }
                if let data = jsonPart.data(using: .utf8),
                   let event = try? decoder.decode(StreamEvent.self, from: data) {
                    onEvent(event)
                    if event.type == "done" || event.type == "error" {
                        return
                    }
                }
            }
        }
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = try url(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = try url(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = try url(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = try url(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func url(_ path: String) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        return url
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}
