import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.needsOnboarding {
                OnboardingView()
            } else {
                ContentView()
            }
        }
        .preferredColorScheme(.dark)
        .background(CodexTheme.canvas)
        .overlay(alignment: .top) {
            if let err = appState.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
                    .onTapGesture { appState.errorMessage = nil }
            }
        }
        .task {
            await appState.bootstrap()
        }
        .onDisappear {
            appState.shutdown()
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var canContinue: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                modalCard
                statusBadge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
        .onAppear {
            draft = appState.userId
            fieldFocused = true
        }
    }

    private var modalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Seyeon")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.93, green: 0.93, blue: 0.93))
                .padding(.bottom, 8)

            Text("시작하려면 User ID를 입력하세요.")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.61, green: 0.61, blue: 0.61))
                .padding(.bottom, 16)

            TextField("예: user01", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.93, green: 0.93, blue: 0.93))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.13, green: 0.13, blue: 0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            fieldFocused
                                ? Color.white.opacity(0.22)
                                : Color(red: 0.20, green: 0.20, blue: 0.20),
                            lineWidth: 1
                        )
                )
                .focused($fieldFocused)
                .focusEffectDisabled()
                .onSubmit { submit() }
                .padding(.bottom, 16)

            HStack {
                Spacer(minLength: 0)
                Button(action: submit) {
                    Text("시작")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    canContinue
                                        ? Color(red: 0.063, green: 0.639, blue: 0.498) // #10a37f
                                        : Color(red: 0.063, green: 0.639, blue: 0.498).opacity(0.45)
                                )
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.09)) // #171717
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.20, green: 0.20, blue: 0.20), lineWidth: 1)
        )
    }

    private func submit() {
        guard canContinue else { return }
        Task { await appState.completeOnboarding(userId: draft) }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: appState.serverStatus))
                .frame(width: 8, height: 8)
            Text(appState.serverStatus.label)
                .font(.caption)
                .foregroundStyle(CodexTheme.textSecondary)
        }
    }

    private func color(for status: ServerStatus) -> Color {
        switch status {
        case .ready: return CodexTheme.accent
        case .starting: return .orange
        case .offline: return .gray
        case .error: return .red
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var configPanel: SidebarConfigPanel?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(configPanel: $configPanel)
                .frame(width: 268)

            Rectangle()
                .fill(CodexTheme.border)
                .frame(width: 1)

            ZStack {
                ChatView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 메인(채팅) 영역을 누르면 선택 패널을 Done처럼 닫고 적용
                if configPanel != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { configPanel = nil }
                }
            }
        }
        .background(CodexTheme.canvas)
    }
}
