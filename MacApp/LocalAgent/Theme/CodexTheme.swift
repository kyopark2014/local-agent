import SwiftUI

/// agent-skills `agent.css` :root 토큰과 동일한 다크 서페이스.
enum CodexTheme {
    // --bg-primary: #0d0d0d
    static let canvas = Color(red: 0x0d / 255, green: 0x0d / 255, blue: 0x0d / 255)
    // --bg-secondary: #171717
    static let sidebar = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)
    // --bg-tertiary: #212121
    static let elevated = Color(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255)
    // --bg-hover: #2a2a2a
    static let elevated2 = Color(red: 0x2a / 255, green: 0x2a / 255, blue: 0x2a / 255)
    // --border: #333333
    static let border = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    // --text-primary: #ececec
    static let textPrimary = Color(red: 0xec / 255, green: 0xec / 255, blue: 0xec / 255)
    // --text-secondary: #9b9b9b
    static let textSecondary = Color(red: 0x9b / 255, green: 0x9b / 255, blue: 0x9b / 255)
    // --text-muted: #6b6b6b
    static let textMuted = Color(red: 0x6b / 255, green: 0x6b / 255, blue: 0x6b / 255)
    // --accent: #10a37f
    static let accent = Color(red: 0x10 / 255, green: 0xa3 / 255, blue: 0x7f / 255)
    // --user-bubble: #2f2f2f
    static let userTint = Color(red: 0x2f / 255, green: 0x2f / 255, blue: 0x2f / 255)
    static let codeBg = Color(red: 0x0d / 255, green: 0x0d / 255, blue: 0x0d / 255)
    static let selection = Color.white.opacity(0.08)
    static let contentMaxWidth: CGFloat = 760
    static let chatHorizontalPadding: CGFloat = 32
}

extension View {
    /// 메시지·입력창을 채팅 영역 가로 중앙에 맞춤 (ScrollView는 전체 폭 유지 → 스크롤바는 창 오른쪽).
    func chatContentColumn() -> some View {
        self
            .frame(maxWidth: CodexTheme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, CodexTheme.chatHorizontalPadding)
    }
}
