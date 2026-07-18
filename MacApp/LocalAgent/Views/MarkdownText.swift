import SwiftUI
import MarkdownUI

/// react-markdown + remark-gfm 수준의 Markdown 렌더러 (MarkdownUI).
struct MarkdownText: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(codexTheme)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var codexTheme: Theme {
        Theme()
            .text {
                ForegroundColor(CodexTheme.textPrimary)
                FontSize(13)
            }
            .strong {
                FontWeight(.semibold)
                ForegroundColor(CodexTheme.textPrimary)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(12)
                ForegroundColor(CodexTheme.textPrimary.opacity(0.92))
                BackgroundColor(CodexTheme.elevated2)
            }
            .link {
                ForegroundColor(CodexTheme.accent)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(18)
                        ForegroundColor(CodexTheme.textPrimary)
                    }
                    .markdownMargin(top: 16, bottom: 8)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(15)
                        ForegroundColor(CodexTheme.textPrimary)
                    }
                    .markdownMargin(top: 14, bottom: 6)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(13)
                        ForegroundColor(CodexTheme.textPrimary)
                    }
                    .markdownMargin(top: 12, bottom: 4)
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.22))
                    .markdownMargin(top: 2, bottom: 12)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 2, bottom: 2)
            }
            .codeBlock { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    if let language = configuration.language, !language.isEmpty {
                        Text(language)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexTheme.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        configuration.label
                            .relativeLineSpacing(.em(0.15))
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(12.5)
                                ForegroundColor(CodexTheme.textPrimary.opacity(0.92))
                            }
                            .padding(12)
                    }
                }
                .background(CodexTheme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CodexTheme.border))
                .markdownMargin(top: 8, bottom: 12)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(CodexTheme.accent.opacity(0.7))
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(CodexTheme.textSecondary)
                        }
                        .padding(.leading, 10)
                }
                .markdownMargin(top: 6, bottom: 10)
            }
            .table { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: false)
                        .markdownTableBorderStyle(.init(color: CodexTheme.border))
                        .markdownTableBackgroundStyle(
                            .alternatingRows(CodexTheme.canvas, CodexTheme.elevated)
                        )
                }
                .markdownMargin(top: 8, bottom: 12)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(13)
                        ForegroundColor(CodexTheme.textPrimary)
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
            .thematicBreak {
                Divider()
                    .overlay(CodexTheme.border)
                    .markdownMargin(top: 12, bottom: 12)
            }
    }
}
