import SwiftUI

struct CoachView: View {
    @StateObject private var viewModel = CoachViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CoachHeader(
                onRefresh: {
                    Task { await viewModel.refreshContext() }
                },
                onClear: {
                    viewModel.clearHistory()
                }
            )

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let context = viewModel.context {
                            CoachContextStrip(context: context)
                        }

                        ForEach(viewModel.messages) { message in
                            CoachMessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.state == .loading {
                            CoachTypingBubble()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 188)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.state) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            CoachInputBar(
                text: $viewModel.draft,
                isSending: viewModel.state == .loading,
                onSend: {
                    Task { await viewModel.send() }
                }
            )
            .focused($inputFocused)
        }
        .background(AppBackground())
        .task {
            await viewModel.load()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if viewModel.state == .loading {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            } else if let last = viewModel.messages.last {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct CoachHeader: View {
    let onRefresh: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            Text("Coach")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.pageTitle)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 10) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("刷新上下文")

                Menu {
                    Button(role: .destructive, action: onClear) {
                        Label("清空对话", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("更多")
            }
            .foregroundStyle(AppColor.textPrimary)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }
}

private struct CoachContextStrip: View {
    let context: CoachContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Training Context", systemImage: "waveform.path.ecg")
                    .font(AppTypography.headline)
                Spacer()
                Text(Self.timeString(context.generatedAt))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(context.summaryRows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.0)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(row.1)
                            .font(AppTypography.captionBold)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppColor.controlBackground, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(AppColor.contentBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct CoachMessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 34) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Group {
                    if isUser {
                        Text(message.content)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(.white)
                    } else {
                        CoachMarkdownRenderer(markdown: message.content)
                    }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 13)
                .background(isUser ? AppColor.accent : AppColor.contentBackground, in: RoundedRectangle(cornerRadius: 8))

                Text(Self.timeString(message.createdAt))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            if !isUser { Spacer(minLength: 34) }
        }
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct CoachTypingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Hermes 正在思考")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .background(AppColor.contentBackground, in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 34)
        }
    }
}

private struct CoachInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("问 Hermes 一句", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppTypography.subheadline)
                .lineLimit(1...4)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .background(AppColor.controlBackground, in: RoundedRectangle(cornerRadius: 8))

            Button(action: onSend) {
                Image(systemName: isSending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.white)
                    .background(canSend ? AppColor.accent : AppColor.textTertiary, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 118)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
