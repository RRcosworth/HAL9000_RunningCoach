import SwiftUI

struct CoachMarkdownRenderer: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.parse(markdown)) { block in
                switch block.kind {
                case .paragraph(let text):
                    markdownText(text)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•")
                                markdownText(item)
                            }
                        }
                    }
                case .code(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .padding(10)
                            .background(AppColor.controlBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                case .table(let rows):
                    CoachMarkdownTable(rows: rows)
                }
            }
        }
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func parse(_ markdown: String) -> [CoachMarkdownBlock] {
        var blocks: [CoachMarkdownBlock] = []
        var paragraph: [String] = []
        var list: [String] = []
        var table: [[String]] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(CoachMarkdownBlock(kind: .paragraph(paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }

        func flushList() {
            guard !list.isEmpty else { return }
            blocks.append(CoachMarkdownBlock(kind: .list(list)))
            list.removeAll()
        }

        func flushTable() {
            guard !table.isEmpty else { return }
            blocks.append(CoachMarkdownBlock(kind: .table(table)))
            table.removeAll()
        }

        func flushCode() {
            guard !code.isEmpty else { return }
            blocks.append(CoachMarkdownBlock(kind: .code(code.joined(separator: "\n"))))
            code.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushParagraph()
                    flushList()
                    flushTable()
                    inCode = true
                }
                continue
            }

            if inCode {
                code.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                flushList()
                flushTable()
                continue
            }

            if let row = tableRow(from: line) {
                flushParagraph()
                flushList()
                if !isSeparatorRow(row) {
                    table.append(row)
                }
                continue
            }

            flushTable()

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                list.append(String(line.dropFirst(2)))
            } else {
                flushList()
                paragraph.append(rawLine)
            }
        }

        flushCode()
        flushParagraph()
        flushList()
        flushTable()
        return blocks
    }

    private static func tableRow(from line: String) -> [String]? {
        guard line.hasPrefix("|"), line.hasSuffix("|") else { return nil }
        let cells = line
            .dropFirst()
            .dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isSeparatorRow(_ row: [String]) -> Bool {
        row.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
}

struct CoachMarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph(String)
        case list([String])
        case code(String)
        case table([[String]])
    }

    let id = UUID()
    let kind: Kind
}

private struct CoachMarkdownTable: View {
    let rows: [[String]]

    var body: some View {
        let columnCount = rows.map(\.count).max() ?? 1
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .leading), count: columnCount)

        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    Text(row.indices.contains(columnIndex) ? row[columnIndex] : "")
                        .font(rowIndex == 0 ? AppTypography.captionBold : AppTypography.caption)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 8)
                        .background(rowIndex == 0 ? AppColor.accentLight : AppColor.controlBackground.opacity(0.6))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
