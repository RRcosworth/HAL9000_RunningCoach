import Foundation

@MainActor
final class CoachViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var state: CoachState = .idle
    @Published private(set) var context: CoachContext?
    @Published var draft: String = ""

    private let api: APIClient
    private let contextCollector: CoachContextCollector
    private let storageKey = "coachMessages"

    init(api: APIClient = .shared, contextCollector: CoachContextCollector = CoachContextCollector()) {
        self.api = api
        self.contextCollector = contextCollector
        restoreMessages()
    }

    func load() async {
        context = await contextCollector.collect()
        if messages.isEmpty {
            messages = [
                ChatMessage(
                    role: .assistant,
                    content: "我在这里。你可以直接问今天该不该加量、某节训练跑得怎么样，或让我生成下周计划。"
                )
            ]
            persistMessages()
        }
    }

    func refreshContext() async {
        context = await contextCollector.collect()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, state != .loading else { return }

        draft = ""
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persistMessages()
        state = .loading

        let currentContext = await contextCollector.collect()
        context = currentContext

        do {
            await api.updateBaseURL(UserSessionStore.shared.resolvedBaseURL)
            let request = CoachChatRequest(
                context: currentContext,
                message: text,
                history: recentHistory(excluding: userMessage.id)
            )
            let endpoint = try Endpoint.coachChat(request)
            let response: CoachChatResponse = try await api.send(endpoint)
            messages.append(ChatMessage(role: .assistant, content: response.reply))
            state = .idle
        } catch {
            messages.append(ChatMessage(role: .assistant, content: fallbackReply(for: error)))
            state = .failed(error.localizedDescription)
        }

        persistMessages()
    }

    func clearHistory() {
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func recentHistory(excluding id: UUID) -> [CoachHistoryMessage] {
        messages
            .filter { $0.id != id }
            .suffix(20)
            .map { CoachHistoryMessage(role: $0.role.rawValue, content: $0.content) }
    }

    private func restoreMessages() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder.coach.decode([ChatMessage].self, from: data) else {
            return
        }
        messages = decoded
    }

    private func persistMessages() {
        guard let data = try? JSONEncoder.coach.encode(messages.suffix(100)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func fallbackReply(for error: Error) -> String {
        if case APIError.missingServerURL = error {
            return "**本地 proxy 还没有配置。**\n\n请确认 Profile 里的 Hermes Gateway 地址指向你的 Mac，例如 `http://192.168.31.175:5055`。"
        }

        return "**这次没有连上 Mac 本地 proxy。**\n\n请确认 Mac 和 iPhone 在同一个 Wi-Fi，并且 Hermes Gateway 正在 `5055` 端口运行。你的问题已经保留，可以稍后重发。"
    }
}
