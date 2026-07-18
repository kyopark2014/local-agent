import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var serverStatus: ServerStatus = .offline
    @Published var userId: String = UserDefaults.standard.string(forKey: "userId") ?? ""
    @Published var needsOnboarding: Bool = false
    @Published var config: AppConfig?
    @Published var tasks: [AgentTask] = []
    @Published var activeTaskId: String?
    @Published var messages: [ChatMessage] = []
    /// taskId → in-flight stream (agent-skills `streamsByTaskId`와 동일)
    @Published private var streamsByTaskId: [String: TaskStreamState] = [:]
    @Published var errorMessage: String?
    @Published var pendingAttachments: [AttachedImage] = []
    @Published var isUploading: Bool = false
    /// Shown above the chat composer (agent-skills chat-upload-error / status)
    @Published var composerBanner: String?
    @Published var composerBannerIsError: Bool = false
    /// UI zoom factor (⌘+/⌘−). Persisted.
    @Published var uiScale: Double = UserDefaults.standard.object(forKey: "uiScale") as? Double ?? 1.0

    struct TaskStreamState {
        var text: String = ""
        var events: [ToolEvent] = []
    }

    /// 현재 선택된 task의 스트리밍 여부 (다른 task 스트림은 무시)
    var isStreaming: Bool {
        guard let id = activeTaskId else { return false }
        return streamsByTaskId[id] != nil
    }

    var streamingText: String {
        guard let id = activeTaskId else { return "" }
        return streamsByTaskId[id]?.text ?? ""
    }

    var streamingEvents: [ToolEvent] {
        guard let id = activeTaskId else { return [] }
        return streamsByTaskId[id]?.events ?? []
    }

    let processManager = PythonProcessManager()
    private let api = APIClient.shared
    private let minScale = 0.8
    private let maxScale = 1.6
    private let scaleStep = 0.1

    private func isStreaming(_ taskId: String) -> Bool {
        streamsByTaskId[taskId] != nil
    }

    private func patchStream(_ taskId: String, _ update: (inout TaskStreamState) -> Void) {
        var state = streamsByTaskId[taskId] ?? TaskStreamState()
        update(&state)
        streamsByTaskId[taskId] = state
    }

    private func clearStream(_ taskId: String) {
        streamsByTaskId.removeValue(forKey: taskId)
    }
    func zoomIn() {
        setScale(uiScale + scaleStep)
    }

    func zoomOut() {
        setScale(uiScale - scaleStep)
    }

    func resetZoom() {
        setScale(1.0)
    }

    private func setScale(_ value: Double) {
        let clamped = min(maxScale, max(minScale, (value * 10).rounded() / 10))
        uiScale = clamped
        UserDefaults.standard.set(clamped, forKey: "uiScale")
    }

    var activeTask: AgentTask? {
        tasks.first { $0.id == activeTaskId }
    }

    struct AttachedImage: Identifiable, Hashable {
        let id = UUID()
        let url: String
        let name: String
        let preview: NSImage?
        var isImage: Bool {
            let ext = (name as NSString).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "webp"].contains(ext)
        }
    }

    func bootstrap() async {
        errorMessage = nil
        await processManager.ensureServerRunning()
        serverStatus = processManager.status

        guard case .ready = serverStatus else {
            errorMessage = processManager.status.label
            return
        }

        if userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            needsOnboarding = true
            return
        }

        do {
            _ = try await api.setSession(userId: userId)
            config = try await api.getConfig()
            await refreshTasks()
            if activeTaskId == nil {
                activeTaskId = tasks.first?.id
            }
            if let id = activeTaskId {
                await loadMessages(for: id)
            }
            needsOnboarding = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboarding(userId: String) async {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.userId = trimmed
        UserDefaults.standard.set(trimmed, forKey: "userId")
        needsOnboarding = false
        await bootstrap()
    }

    func logOff() {
        userId = ""
        UserDefaults.standard.removeObject(forKey: "userId")
        needsOnboarding = true
        config = nil
        tasks = []
        activeTaskId = nil
        messages = []
        streamsByTaskId = [:]
        pendingAttachments = []
        errorMessage = nil
        api.clearCookies()
    }

    func refreshTasks() async {
        do {
            tasks = try await api.listTasks().sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                return lhs.updatedAt > rhs.updatedAt
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectTask(_ id: String) async {
        activeTaskId = id
        // 다른 task 스트림은 유지 — UI는 activeTaskId 기준 스트림만 표시
        await loadMessages(for: id)
    }

    func loadMessages(for taskId: String) async {
        do {
            messages = try await api.getMessages(taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask() async {
        guard let config else { return }
        // agent-skills: New task는 현재 task의 Skill/MCP/Model을 상속
        let source = activeTask
        do {
            let task = try await api.createTask(
                title: "New task",
                modelName: source?.modelName ?? config.defaultModel,
                skills: source?.skills ?? config.defaultSkills,
                mcpServers: source?.mcpServers ?? config.defaultMcpServers,
                guardrailEnabled: source?.guardrailEnabled ?? false,
                memoryEnabled: source?.memoryEnabled ?? false
            )
            tasks.insert(task, at: 0)
            await selectTask(task.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ id: String) async {
        do {
            try await api.deleteTask(id)
            tasks.removeAll { $0.id == id }
            clearStream(id)
            if activeTaskId == id {
                activeTaskId = tasks.first?.id
                if let next = activeTaskId {
                    await loadMessages(for: next)
                } else {
                    messages = []
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameTask(_ id: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let updated = try await api.patchTask(id, fields: ["title": trimmed])
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePinTask(_ id: String) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        do {
            let updated = try await api.patchTask(id, fields: ["pinned": !task.pinned])
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx] = updated
            }
            await refreshTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func patchActiveTask(_ fields: [String: Any]) async {
        guard let id = activeTaskId else { return }
        do {
            let updated = try await api.patchTask(id, fields: fields)
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx] = updated
            }
            // Skill/MCP/Model 변경은 config defaults에도 기억 (다음 New task·재시작용)
            await rememberConfigDefaults(from: fields)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// tasks.db PATCH와 함께 config.json defaults도 갱신
    private func rememberConfigDefaults(from fields: [String: Any]) async {
        var defaults: [String: Any] = [:]
        if let skills = fields["skills"] as? [String] {
            defaults["default_skills"] = skills
        }
        if let mcp = fields["mcp_servers"] as? [String] {
            defaults["default_mcp_servers"] = mcp
        }
        if let model = fields["model_name"] as? String {
            defaults["default_model"] = model
        }
        guard !defaults.isEmpty else { return }
        do {
            try await api.patchDefaults(defaults)
            if var cfg = config {
                if let skills = defaults["default_skills"] as? [String] {
                    cfg.defaultSkills = skills
                }
                if let mcp = defaults["default_mcp_servers"] as? [String] {
                    cfg.defaultMcpServers = mcp
                }
                if let model = defaults["default_model"] as? String {
                    cfg.defaultModel = model
                }
                config = cfg
            }
        } catch {
            // task DB 저장은 성공했으므로 defaults 실패는 UI를 막지 않음
        }
    }

    func sendMessage(text: String) async {
        guard let taskId = activeTaskId, !isStreaming(taskId) else { return }
        let files = pendingAttachments.map(\.url)
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !files.isEmpty else { return }

        let display = prompt.isEmpty ? "첨부한 파일을 분석해주세요." : prompt
        let optimistic = ChatMessage(
            id: "pending-\(UUID().uuidString)",
            taskId: taskId,
            role: "user",
            content: display,
            images: files,
            toolEvents: [],
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        messages.append(optimistic)
        pendingAttachments = []
        streamsByTaskId[taskId] = TaskStreamState()

        do {
            try await api.streamChat(taskId: taskId, prompt: prompt, files: files) { [weak self] event in
                Task { @MainActor in
                    self?.handleStreamEvent(taskId: taskId, event: event)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            clearStream(taskId)
        }
    }

    private func handleStreamEvent(taskId: String, event: StreamEvent) {
        switch event.type {
        case "token":
            if let data = event.data {
                patchStream(taskId) { state in
                    if isSegmentReset(previous: state.text, next: data) {
                        flushTextSegment(taskId: taskId, state: &state)
                    }
                    state.text = data
                }
            }
        case "text":
            if let data = event.data {
                patchStream(taskId) { state in
                    appendTextSegment(data, to: &state)
                    state.text = ""
                }
            }
        case "tool":
            patchStream(taskId) { state in
                flushTextSegment(taskId: taskId, state: &state)
                upsertTool(
                    ToolEvent(
                        type: "tool",
                        tool: event.tool,
                        input: event.input,
                        toolUseId: event.toolUseId,
                        data: nil
                    ),
                    into: &state
                )
            }
        case "tool_result":
            patchStream(taskId) { state in
                upsertTool(
                    ToolEvent(
                        type: "tool_result",
                        tool: event.tool,
                        input: nil,
                        toolUseId: event.toolUseId,
                        data: event.data
                    ),
                    into: &state
                )
            }
        case "info":
            if let data = event.data {
                if data.hasPrefix("Tool:") || data.hasPrefix("Tool Result:") { break }
                patchStream(taskId) { state in
                    state.events.append(
                        ToolEvent(
                            type: "info",
                            tool: nil,
                            input: nil,
                            toolUseId: "info-\(state.events.count)",
                            data: data
                        )
                    )
                }
            }
        case "done":
            let stream = streamsByTaskId[taskId]
            let flushedEvents: [ToolEvent] = {
                var state = stream ?? TaskStreamState()
                flushTextSegment(taskId: taskId, state: &state)
                return state.events
            }()
            let content = event.content ?? stream?.text ?? ""
            let toolEvents = event.toolEvents ?? flushedEvents

            clearStream(taskId)

            // 지금 보고 있는 task일 때만 메시지 목록에 반영 (web activeTaskIdRef 가드와 동일)
            if activeTaskId == taskId {
                let final = ChatMessage(
                    id: UUID().uuidString,
                    taskId: taskId,
                    role: "assistant",
                    content: content,
                    images: event.images ?? [],
                    toolEvents: toolEvents,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                messages.append(final)
                Task { await loadMessages(for: taskId) }
            }
            Task { await refreshTasks() }
        case "error":
            errorMessage = event.data ?? "Unknown error"
            clearStream(taskId)
        default:
            break
        }
    }

    /// Persist completed assistant text before the next tool event (timeline order).
    private func flushTextSegment(taskId: String, state: inout TaskStreamState) {
        let trimmed = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendTextSegment(trimmed, to: &state)
        state.text = ""
    }

    private func appendTextSegment(_ text: String, to state: inout TaskStreamState) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = state.events.last, last.type == "text", last.data == trimmed {
            return
        }
        state.events.append(
            ToolEvent(
                type: "text",
                tool: nil,
                input: nil,
                toolUseId: "text-\(state.events.count)-\(trimmed.hashValue)",
                data: trimmed
            )
        )
    }

    private func isSegmentReset(previous: String, next: String) -> Bool {
        let prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        if prev.isEmpty { return false }
        if next.isEmpty { return true }
        return !next.hasPrefix(previous)
    }

    private func upsertTool(_ event: ToolEvent, into state: inout TaskStreamState) {
        if let id = event.toolUseId,
           let idx = state.events.firstIndex(where: { $0.type == event.type && $0.toolUseId == id }) {
            state.events[idx] = event
            return
        }
        if event.type == "tool", let name = event.tool,
           let idx = state.events.firstIndex(where: { $0.type == "tool" && $0.tool == name }) {
            state.events[idx] = event
            return
        }
        state.events.append(event)
    }

    func attachImage(from url: URL) async {
        isUploading = true
        composerBanner = "업로드 중..."
        composerBannerIsError = false
        defer { isUploading = false }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let result = try await api.uploadImage(fileURL: url)
            let ext = url.pathExtension.lowercased()
            let preview = ["png", "jpg", "jpeg", "gif", "webp"].contains(ext)
                ? NSImage(contentsOf: url)
                : nil
            pendingAttachments.append(AttachedImage(url: result.url, name: result.fileName, preview: preview))
            clearComposerBanner()
        } catch {
            showComposerBanner(friendlyAPIError(error), isError: true)
        }
    }

    /// Paste screenshot / clipboard image → S3 (`/api/files/upload`) → chat attachment.
    func attachPastedImage(_ image: NSImage) async {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            showComposerBanner("클립보드 이미지를 읽을 수 없습니다.", isError: true)
            return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasted_screenshot.png")
        do {
            try pngData.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            isUploading = true
            composerBanner = "업로드 중..."
            composerBannerIsError = false
            defer { isUploading = false }
            let result = try await api.uploadImage(fileURL: tmp)
            pendingAttachments.append(
                AttachedImage(url: result.url, name: result.fileName, preview: image)
            )
            clearComposerBanner()
        } catch {
            showComposerBanner(friendlyAPIError(error), isError: true)
        }
    }

    /// Upload document to S3 and start Knowledge Base ingestion (agent-skills parity).
    func uploadToRag(from url: URL) async {
        isUploading = true
        composerBanner = "업로드 중..."
        composerBannerIsError = false
        defer { isUploading = false }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let result = try await api.uploadToRag(fileURL: url)
            // Prefer API message (agentic-work parity); fall back to fileName if empty
            let message: String = {
                let trimmed = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                let name = result.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return "\"\(name)\"가 S3에 업로드 되었고 Knowledge Base와 동기화를 시작합니다."
                }
                return "파일이 S3에 업로드 되었고 Knowledge Base와 동기화를 시작합니다."
            }()
            showComposerBanner(message, isError: false)
        } catch {
            showComposerBanner(friendlyAPIError(error), isError: true)
        }
    }

    private var composerBannerTask: Task<Void, Never>?

    func clearComposerBanner() {
        composerBannerTask?.cancel()
        composerBannerTask = nil
        composerBanner = nil
        composerBannerIsError = false
    }

    func showComposerBanner(_ text: String, isError: Bool) {
        composerBannerTask?.cancel()
        composerBanner = localizeComposerMessage(text)
        composerBannerIsError = isError
        // agentic-work: 에러 배너는 5초 후 자동 숨김 (성공도 동일)
        composerBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if composerBanner != nil {
                composerBanner = nil
                composerBannerIsError = false
            }
        }
    }

    private func friendlyAPIError(_ error: Error) -> String {
        if case APIError.http(_, let body) = error {
            if let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = obj["detail"] as? String {
                return localizeComposerMessage(detail)
            }
            if !body.isEmpty { return localizeComposerMessage(body) }
        }
        return localizeComposerMessage(error.localizedDescription)
    }

    /// Map common English API/UI strings to Korean (agent-skills style UX).
    private func localizeComposerMessage(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if lower.contains("rag document upload is disabled") {
            return "RAG 문서 업로드가 비활성화되어 있습니다. Knowledge Base 조회(retrieve)를 사용하세요."
        }
        if lower.contains("failed to upload file to s3") {
            return "S3에 파일 업로드에 실패했습니다."
        }
        if lower.contains("file uploaded but knowledge base sync failed")
            || lower.contains("knowledge base sync failed") {
            return "파일은 업로드되었지만 Knowledge Base 동기화에 실패했습니다."
        }
        if lower.contains("unable to check knowledge base sync") {
            return "현재 Knowledge Base 동기화 상태를 확인할 수 없습니다. 잠시 후 다시 시도해주세요."
        }
        if lower.contains("이전에 업로드된 파일을 처리") || lower.contains("조금후 다시") {
            return "현재 이전에 업로드된 파일을 처리하고 있습니다. 조금후 다시 시도해주세요."
        }
        if lower.contains("empty file") {
            return "빈 파일입니다."
        }
        if lower.contains("file name is required") {
            return "파일 이름이 필요합니다."
        }
        if lower.hasPrefix("unsupported file type") {
            let ext = text.split(separator: ":").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            return "지원하지 않는 파일 형식입니다: \(ext.isEmpty ? "(없음)" : ext)"
        }
        // Success: pass through API message (Korean, agentic-work parity)
        if text.contains("S3에 업로드") && text.contains("Knowledge Base") {
            return text
        }
        if lower.contains("was uploaded to s3 and knowledge base sync was started") {
            // legacy English API message → Korean
            let parts = text.split(separator: "\"", omittingEmptySubsequences: false)
            let name = parts.count >= 2
                ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            if !name.isEmpty {
                return "\"\(name)\"가 S3에 업로드 되었고 Knowledge Base와 동기화를 시작합니다."
            }
            return "파일이 S3에 업로드 되었고 Knowledge Base와 동기화를 시작합니다."
        }
        if text == "업로드 중..." || text.hasPrefix("\"") && text.contains("동기화") {
            return text
        }
        return text
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func shutdown() {
        processManager.stop()
    }
}
