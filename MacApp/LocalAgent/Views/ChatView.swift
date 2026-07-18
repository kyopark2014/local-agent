import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @State private var isDropTargeted = false
    @State private var pasteMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            taskHeader
            messageList
            inputBar
        }
        .background(CodexTheme.canvas)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            guard !appState.isStreaming && !appState.isUploading else { return false }
            return handleDrop(providers)
        }
        .onAppear { installPasteMonitor() }
        .onDisappear { removePasteMonitor() }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CodexTheme.accent, lineWidth: 2)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Clipboard paste (screenshot → S3 → agent)

    private var taskHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)
            Text(taskTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CodexTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CodexTheme.border)
                .frame(height: 1)
        }
    }

    private var taskTitle: String {
        let title = appState.activeTask?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "New task" : title
    }

    private var messageList: some View {
        Group {
            if appState.messages.isEmpty && !appState.isStreaming {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(appState.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if appState.isStreaming {
                                StreamingBubble(
                                    text: appState.streamingText,
                                    events: appState.streamingEvents
                                )
                                .id("streaming")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .chatContentColumn()
                    }
                    // 스크롤바는 창 오른쪽(채팅 영역 우측). 손잡이는 투명·두께 1/2.
                    .scrollIndicators(.hidden)
                    .thinTransparentScrollbar()
                    .background(CodexTheme.canvas)
                    .onChange(of: appState.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: appState.activeTaskId) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: appState.streamingText) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: appState.streamingEvents.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Amazon Bedrock 기반 에이전트입니다.")
                .font(.system(size: 14))
            Text("메뉴에서 Skill, MCP, Model을 설정하고 대화를 시작하세요.")
                .font(.system(size: 13))
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodexTheme.canvas)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if appState.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = appState.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        // Banner↔composer gap ≈ tool↔AI mid spacing (14)
        VStack(spacing: appState.composerBanner != nil ? 14 : 0) {
            if let banner = appState.composerBanner {
                Text(banner)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        appState.composerBannerIsError
                            ? Color(red: 0.98, green: 0.55, blue: 0.55)
                            : CodexTheme.textSecondary
                    )
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        appState.composerBannerIsError
                            ? Color(red: 0.35, green: 0.12, blue: 0.12).opacity(0.95)
                            : CodexTheme.elevated
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .chatContentColumn()
                    .onTapGesture { appState.clearComposerBanner() }
            }

            if !appState.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.pendingAttachments) { item in
                            ZStack(alignment: .topTrailing) {
                                if let img = item.preview {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    VStack(spacing: 4) {
                                        Image(systemName: "doc.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(CodexTheme.textSecondary)
                                        Text(item.name)
                                            .font(.system(size: 9))
                                            .foregroundStyle(CodexTheme.textMuted)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: 64)
                                    }
                                    .frame(width: 72, height: 56)
                                    .background(CodexTheme.elevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button {
                                    appState.removeAttachment(item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.isStreaming)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .chatContentColumn()
                .padding(.bottom, 8)
            }

            // Codex-style composer: text on top, tools row (+ … send) below
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    appState.isStreaming
                        ? "응답 생성 중…"
                        : "메시지를 입력하거나 이미지를 붙여넣으세요…",
                    text: $draft,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1...8)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .disabled(!inputEnabled)
                    .onSubmit {
                        guard inputEnabled else { return }
                        if NSEvent.modifierFlags.contains(.shift) { return }
                        send()
                    }

                HStack(spacing: 10) {
                    Button {
                        pickRagFiles()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(CodexTheme.elevated2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Upload to RAG (PDF, docs → S3 + Knowledge Base)")
                    .disabled(!inputEnabled)

                    Spacer(minLength: 0)

                    Button {
                        guard canSend else { return }
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(canSend ? CodexTheme.accent : CodexTheme.accent.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Send")
                    .disabled(!canSend)
                    .allowsHitTesting(canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CodexTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(CodexTheme.border))
            .opacity(appState.isStreaming ? 0.55 : 1)
            .chatContentColumn()
            .padding(.top, appState.composerBanner != nil ? 0 : 16)
            .padding(.bottom, 16)
            .background(CodexTheme.canvas)
        }
    }

    /// 스트리밍·업로드 중에는 새 입력을 받지 않음
    private var inputEnabled: Bool {
        appState.activeTask != nil
            && !appState.isStreaming
            && !appState.isUploading
    }

    private var canSend: Bool {
        inputEnabled
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !appState.pendingAttachments.isEmpty)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await appState.sendMessage(text: text) }
    }

    private func pickRagFiles() {
        let panel = NSOpenPanel()
        // agent-skills / agentic-work RAG_ACCEPT
        panel.allowedContentTypes = [
            .pdf,
            .plainText, .utf8PlainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText,
            .commaSeparatedText,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            .html,
            .json,
            UTType(filenameExtension: "py") ?? .sourceCode,
            UTType(filenameExtension: "js") ?? .sourceCode,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            Task {
                for url in panel.urls {
                    await appState.uploadToRag(from: url)
                }
            }
        }
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp",
    ]

    private func installPasteMonitor() {
        removePasteMonitor()
        let state = appState
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isPaste =
                event.modifierFlags.contains(.command)
                && (event.charactersIgnoringModifiers == "v" || event.charactersIgnoringModifiers == "V")
            guard isPaste else { return event }
            guard !state.isStreaming, !state.isUploading else { return event }
            guard let image = Self.imageFromPasteboard() else { return event }
            Task { @MainActor in
                await state.attachPastedImage(image)
            }
            return nil // consume Cmd+V when clipboard holds an image
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    private static func imageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png), let image = NSImage(data: png) {
            return image
        }
        if let tiff = pb.data(forType: .tiff), let image = NSImage(data: tiff) {
            return image
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }
        return nil
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in
                        await appState.attachPastedImage(image)
                    }
                }
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    Task { @MainActor in
                        if Self.imageExtensions.contains(ext) {
                            await appState.attachImage(from: url)
                        } else {
                            await appState.uploadToRag(from: url)
                        }
                    }
                }
            }
        }
        return handled
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    if !message.images.isEmpty {
                        Text(message.images.map { URL(string: $0)?.lastPathComponent ?? ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(CodexTheme.textMuted)
                    }
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(CodexTheme.elevated2.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                AssistantTimelineView(
                    content: message.content,
                    events: message.toolEvents,
                    liveText: ""
                )
                if !message.images.isEmpty {
                    Text(message.images.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(CodexTheme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StreamingBubble: View {
    let text: String
    let events: [ToolEvent]

    var body: some View {
        if events.isEmpty && text.isEmpty {
            ThinkingIndicator()
        } else {
            AssistantTimelineView(content: text, events: events, liveText: text)
        }
    }
}

/// Renders assistant output in chronological timeline order: text → tool → tool_result → …
struct AssistantTimelineView: View {
    let content: String
    let events: [ToolEvent]
    /// In-progress token buffer (streaming only). Shown after flushed timeline events.
    let liveText: String

    private var timeline: [ToolEvent] {
        filterSupersededTextEvents(events, content: content)
    }

    private var hasTimelineText: Bool {
        timeline.contains { $0.type == "text" }
    }

    /// Live buffer with already-flushed text prefixes removed (keeps AI text above tools).
    private var displayLiveText: String? {
        var live = liveText
        for event in timeline where event.type == "text" {
            guard let data = event.data, !data.isEmpty else { continue }
            if live.hasPrefix(data) {
                live = String(live.dropFirst(data.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if normalizeText(live) == normalizeText(data) {
                return nil
            }
        }
        let trimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var showTrailingContent: Bool {
        guard liveText.isEmpty else { return false }
        let normalized = normalizeText(content)
        guard !normalized.isEmpty else { return false }
        let covered = timeline.contains {
            $0.type == "text" && normalizeText($0.data ?? "") == normalized
        }
        return !covered
    }

    private var timelineHasTools: Bool {
        timeline.contains { $0.type == "tool" || $0.type == "tool_result" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasTimelineText || timelineHasTools {
                ForEach(Array(timeline.enumerated()), id: \.offset) { index, event in
                    let previousType = index > 0 ? timeline[index - 1].type : nil
                    timelineRow(event, after: previousType)
                }
            } else {
                ForEach(events.filter { $0.type == "tool" || $0.type == "tool_result" }) { event in
                    ToolEventCard(event: event)
                }
            }

            if let live = displayLiveText {
                MarkdownText(content: live)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, timelineHasTools ? 14 : 8)
                    .padding(.bottom, 4)
            } else if showTrailingContent {
                MarkdownText(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, timelineHasTools ? 14 : 8)
                    .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ event: ToolEvent, after previousType: String?) -> some View {
        let afterTool = previousType == "tool" || previousType == "tool_result"
        switch event.type {
        case "text":
            if let data = event.data, !data.isEmpty {
                MarkdownText(content: data)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, afterTool ? 14 : 0)
                    .padding(.bottom, 6)
            }
        case "tool", "tool_result":
            ToolEventCard(event: event)
        case "info":
            if let data = event.data, !data.isEmpty {
                Text(data)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textMuted)
            }
        default:
            EmptyView()
        }
    }
}

private func normalizeText(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private func isStreamingPrefixOfFinal(_ partial: String, _ finalText: String) -> Bool {
    if partial.isEmpty || finalText.isEmpty { return false }
    if finalText.hasPrefix(partial) || partial.hasPrefix(finalText) { return true }
    let headLen = min(partial.count, finalText.count, 80)
    return partial.prefix(headLen) == finalText.prefix(headLen)
}

private func filterSupersededTextEvents(_ events: [ToolEvent], content: String) -> [ToolEvent] {
    let normalizedContent = normalizeText(content)
    let textIndexes = events.indices.filter { events[$0].type == "text" }
    var hidden = Set<Int>()

    for (i, index) in textIndexes.enumerated() {
        let text = normalizeText(events[index].data ?? "")
        for laterIndex in textIndexes.dropFirst(i + 1) {
            let later = normalizeText(events[laterIndex].data ?? "")
            if isStreamingPrefixOfFinal(text, later) && text.count < later.count {
                hidden.insert(index)
                break
            }
        }
        if !hidden.contains(index),
           !normalizedContent.isEmpty,
           isStreamingPrefixOfFinal(text, normalizedContent),
           text.count < normalizedContent.count {
            hidden.insert(index)
        }
    }

    return events.enumerated().compactMap { offset, event in
        hidden.contains(offset) ? nil : event
    }
}

struct ThinkingIndicator: View {
    @State private var dotCount = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Thinking")
            Text(String(repeating: ".", count: dotCount))
                .frame(width: 18, alignment: .leading)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(CodexTheme.textSecondary)
        .opacity(0.55 + Double(dotCount) * 0.12)
        .animation(.easeInOut(duration: 0.28), value: dotCount)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(380))
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

struct ToolEventCard: View {
    let event: ToolEvent
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                guard hasDetail else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.textMuted)
                        .frame(width: 12, alignment: .center)
                        .opacity(hasDetail ? 1 : 0)

                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDetail)

            if expanded, hasDetail {
                Group {
                    if looksLikeMarkdown(detail) {
                        MarkdownText(content: detail)
                    } else {
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CodexTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CodexTheme.border))
    }

    private func looksLikeMarkdown(_ s: String) -> Bool {
        s.contains("```") || s.contains("\n#") || s.contains("| ") || s.contains("- ") || s.contains("**")
    }

    private var toolName: String {
        let name = event.tool?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "tool" : name
    }

    private var title: String {
        switch event.type {
        case "tool":
            return "Tool: \(toolName)"
        case "tool_result":
            return "Tool result: \(toolName)"
        default:
            return event.type
        }
    }

    private var hasDetail: Bool { !detail.isEmpty }

    private var detail: String {
        if let input = event.input { return input.displayString }
        return event.data ?? ""
    }
}
