import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var configPanel: SidebarConfigPanel?

    private var header: some View {
        HStack(spacing: 8) {
            Text(displayUserId)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appState.logOff()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("나가기")
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var displayUserId: String {
        let id = appState.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "User" : id
    }

    private var newTaskButton: some View {
        Button {
            Task { await appState.createTask() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 16, alignment: .center)
                Text("New task")
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.bottom, 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                newTaskButton
                taskList
                    .frame(minHeight: 72)
                    .frame(maxHeight: .infinity)
            }
            // 패널이 열린 동안 위쪽(태스크 목록 등)을 누르면 Done과 같이 닫힘·적용
            .overlay {
                if configPanel != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { configPanel = nil }
                }
            }

            // 선택 패널은 위쪽 여유 공간에만 펼치고, 아래 Skill/MCP/Model 은 하단 고정
            if let configPanel {
                configPanelView(configPanel)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .frame(maxHeight: 280)
            } else {
                Spacer(minLength: 0)
            }

            sectionLabel("CONFIGURATION")
            configRows
            sectionLabel("SETTINGS")
            settingsRows
        }
        .padding(.bottom, 12)
        .background(CodexTheme.sidebar)
        .foregroundStyle(CodexTheme.textPrimary)
    }

    @ViewBuilder
    private func configPanelView(_ panel: SidebarConfigPanel) -> some View {
        switch panel {
        case .skills:
            SidebarMultiSelectPanel(
                title: "Skills",
                options: appState.config?.skills ?? [],
                selected: appState.activeTask?.skills ?? [],
                onChange: { next in
                    Task { await appState.patchActiveTask(["skills": next]) }
                },
                onClose: { configPanel = nil }
            )
        case .mcp:
            SidebarMultiSelectPanel(
                title: "MCP Servers",
                options: appState.config?.mcpServers ?? [],
                selected: appState.activeTask?.mcpServers ?? [],
                onChange: { next in
                    Task { await appState.patchActiveTask(["mcp_servers": next]) }
                },
                onClose: { configPanel = nil }
            )
        case .model:
            SidebarModelPanel(
                models: appState.config?.models ?? [],
                selected: appState.activeTask?.modelName ?? "",
                onChange: { name in
                    Task { await appState.patchActiveTask(["model_name": name]) }
                },
                onClose: { configPanel = nil }
            )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CodexTheme.textMuted)
            .tracking(0.6)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var pinnedTasks: [AgentTask] {
        appState.tasks.filter(\.pinned)
    }

    private var unpinnedTasks: [AgentTask] {
        appState.tasks.filter { !$0.pinned }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !pinnedTasks.isEmpty {
                    sectionLabel("PINNED")
                    taskRows(pinnedTasks)
                        .padding(.horizontal, 8)
                }

                sectionLabel("TASKS")
                if unpinnedTasks.isEmpty && pinnedTasks.isEmpty {
                    Text("No tasks yet")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textMuted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                } else {
                    taskRows(unpinnedTasks)
                        .padding(.horizontal, 8)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func taskRows(_ tasks: [AgentTask]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(tasks) { task in
                TaskRow(task: task, selected: task.id == appState.activeTaskId)
            }
        }
    }

    private var configRows: some View {
        VStack(spacing: 2) {
            configButton(
                icon: "diamond.fill",
                title: "Skill",
                value: "\(appState.activeTask?.skills.count ?? 0)",
                active: configPanel == .skills
            ) { togglePanel(.skills) }
            configButton(
                icon: "cloud.fill",
                title: "MCP",
                value: "\(appState.activeTask?.mcpServers.count ?? 0)",
                active: configPanel == .mcp
            ) { togglePanel(.mcp) }
            configButton(
                icon: "square.grid.2x2.fill",
                title: "Model",
                value: shortModel(appState.activeTask?.modelName ?? "—"),
                active: configPanel == .model
            ) { togglePanel(.model) }
        }
        .padding(.horizontal, 8)
        .disabled(appState.activeTask == nil)
    }

    private func togglePanel(_ panel: SidebarConfigPanel) {
        configPanel = configPanel == panel ? nil : panel
    }

    private var settingsRows: some View {
        VStack(spacing: 2) {
            toggleRow(
                icon: "shield",
                title: "Guardrail",
                isOn: Binding(
                    get: { appState.activeTask?.guardrailEnabled ?? false },
                    set: { v in Task { await appState.patchActiveTask(["guardrail_enabled": v]) } }
                )
            )
            toggleRow(
                icon: "doc.text",
                title: "Memory",
                isOn: Binding(
                    get: { appState.activeTask?.memoryEnabled ?? false },
                    set: { v in Task { await appState.patchActiveTask(["memory_enabled": v]) } }
                )
            )
        }
        .padding(.horizontal, 8)
        .disabled(appState.activeTask == nil)
    }

    private func configButton(
        icon: String,
        title: String,
        value: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(active ? CodexTheme.selection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func shortModel(_ name: String) -> String {
        name.replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: "OpenAI ", with: "")
    }
}

struct TaskRow: View {
    @EnvironmentObject private var appState: AppState
    let task: AgentTask
    var selected: Bool = false

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    private var showActions: Bool { !isRenaming && (isHovered || selected) }

    var body: some View {
        HStack(spacing: 4) {
            if isRenaming {
                TextField("Task title", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(CodexTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .focused($renameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(task.title.isEmpty ? "New task" : task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await appState.selectTask(task.id) }
                    }
            }

            if showActions {
                Button {
                    Task { await appState.deleteTask(task.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(CodexTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")

                Menu {
                    Button {
                        beginRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        Task { await appState.togglePinTask(task.id) }
                    } label: {
                        Label(task.pinned ? "Unpin" : "Pin", systemImage: "pin")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("More")
            }
        }
        // 아이콘(20) + 여유 — hover 전후에도 행 높이·세로 정렬 유지
        .frame(minHeight: 32, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected || isHovered || isRenaming ? CodexTheme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: renameFocused) { _, focused in
            if isRenaming && !focused {
                commitRename()
            }
        }
    }

    private func beginRename() {
        renameDraft = task.title
        isRenaming = true
        DispatchQueue.main.async {
            renameFocused = true
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        renameFocused = false
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        Task { await appState.renameTask(task.id, title: trimmed) }
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
        renameDraft = task.title
    }
}
