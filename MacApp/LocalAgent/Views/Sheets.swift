import SwiftUI

enum SidebarConfigPanel: Equatable {
    case skills
    case mcp
    case model
}

struct SidebarMultiSelectPanel: View {
    let title: String
    let options: [String]
    @State private var selected: [String]
    /// agent-skills ConfigDrawer처럼 토글 즉시 반영
    let onChange: ([String]) -> Void
    let onClose: () -> Void

    init(
        title: String,
        options: [String],
        selected: [String],
        onChange: @escaping ([String]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.options = options
        self._selected = State(initialValue: selected)
        self.onChange = onChange
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer(minLength: 0)
                Button("Done") {
                    onClose()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Rectangle()
                .fill(CodexTheme.border)
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { selected.contains(option) },
                            set: { on in
                                if on {
                                    if !selected.contains(option) { selected.append(option) }
                                } else {
                                    selected.removeAll { $0 == option }
                                }
                                onChange(selected)
                            }
                        )) {
                            Text(option)
                                .font(.system(size: 12))
                                .foregroundStyle(CodexTheme.textPrimary)
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.elevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CodexTheme.border))
    }
}

struct SidebarModelPanel: View {
    let models: [String]
    @State private var selectedModel: String
    let onChange: (String) -> Void
    let onClose: () -> Void

    init(
        models: [String],
        selected: String,
        onChange: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.models = models
        self._selectedModel = State(initialValue: selected)
        self.onChange = onChange
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer(minLength: 0)
                Button("Done") {
                    onClose()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Rectangle()
                .fill(CodexTheme.border)
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(models, id: \.self) { model in
                        Button {
                            selectedModel = model
                            onChange(model)
                            onClose()
                        } label: {
                            HStack(spacing: 8) {
                                Text(model)
                                    .font(.system(size: 12))
                                    .foregroundStyle(CodexTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if model == selectedModel {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CodexTheme.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(model == selectedModel ? CodexTheme.selection : Color.clear)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.elevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CodexTheme.border))
    }
}

struct AppSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("repoRoot") private var repoRoot = ""
    @AppStorage("pythonPath") private var pythonPath = ""
    @AppStorage("userId") private var userId = ""

    var body: some View {
        Form {
            Section("Session") {
                TextField("User ID", text: $userId)
                Button("Apply User ID") {
                    Task { await appState.completeOnboarding(userId: userId) }
                }
            }
            Section("Backend") {
                TextField("Repo root (local-agent)", text: $repoRoot)
                TextField("Python path (optional)", text: $pythonPath)
                LabeledContent("Detected root") {
                    Text(appState.processManager.repoRoot.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                LabeledContent("Status") {
                    Text(appState.serverStatus.label)
                }
                Button("Restart Server") {
                    appState.processManager.stop()
                    Task { await appState.bootstrap() }
                }
            }
        }
        .padding()
        .formStyle(.grouped)
    }
}
