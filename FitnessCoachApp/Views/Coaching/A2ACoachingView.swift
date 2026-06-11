import SwiftUI
import FirebaseFirestore

// MARK: - Server Config
//
// The Flask server (server.py) binds to 0.0.0.0:5001 on the Mac.
// - Simulator: 127.0.0.1
// - Physical iPhone: 30s-iMac.local (Bonjour, iPhone must be on same WiFi)
//
// The iOS app only calls /chat now. The 3-agent CrewAI flow (/run) still
// exists on the server for the CrewAI assignment — its verbose terminal
// output is what the user submits — but it is no longer surfaced in the app.

private let liveCoachBaseURL: String = {
    #if targetEnvironment(simulator)
    return "http://127.0.0.1:5001"
    #else
    return "http://10.24.58.95:5001"
    #endif
}()

// MARK: - Chat models

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id: String
    let role: Role
    let text: String
    let timestamp: Date

    init(id: String = UUID().uuidString, role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

private struct ChatRequestBody: Encodable {
    let snapshot: HealthSnapshot?
    let history: [ChatTurn]
    let question: String
}

private struct ChatTurn: Encodable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let reply: String
    let durationSeconds: Double?
    let model: String?
}

// MARK: - ViewModel

@MainActor
final class A2ACoachingViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loadingSnapshot
        case ready
        case offline           // last send failed because the server is unreachable
    }

    @Published var messages: [ChatMessage] = []
    @Published var isSending: Bool = false
    @Published var state: LoadState = .loadingSnapshot
    @Published var snapshot: HealthSnapshot?
    @Published var lastError: String?

    private let userUID: String?
    private let db = Firestore.firestore()

    private var chatCollection: CollectionReference? {
        guard let uid = userUID else { return nil }
        return db.collection("users").document(uid).collection("chatHistory")
    }

    init(userUID: String?) {
        self.userUID = userUID
    }

    private static let intro =
        "Hi! I'm your fitness coach. I've pulled in your last 7 days of health data — " +
        "ask me anything about your steps, workouts, calories, sleep, recovery, or what " +
        "to focus on next."

    func bootstrap() async {
        guard snapshot == nil else { return }
        state = .loadingSnapshot

        async let historyLoad: Void = loadChatHistory()
        async let snapLoad = Self.gatherHealthSnapshot()

        await historyLoad
        let snap = await snapLoad
        self.snapshot = snap

        if messages.isEmpty {
            let intro = ChatMessage(role: .assistant, text: Self.intro)
            messages.append(intro)
            saveMessage(intro)
        }
        state = .ready
    }

    private func loadChatHistory() async {
        guard let collection = chatCollection else { return }
        do {
            let snapshot = try await collection
                .order(by: "timestamp", descending: false)
                .getDocuments()
            let loaded: [ChatMessage] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let roleStr = data["role"] as? String,
                      let text = data["text"] as? String,
                      let ts = data["timestamp"] as? Timestamp else { return nil }
                let role: ChatMessage.Role = roleStr == "user" ? .user : .assistant
                return ChatMessage(id: doc.documentID, role: role, text: text, timestamp: ts.dateValue())
            }
            self.messages = loaded
        } catch {
            print("⚠️ Failed to load chat history: \(error.localizedDescription)")
        }
    }

    private func saveMessage(_ message: ChatMessage) {
        guard let collection = chatCollection else { return }
        let data: [String: Any] = [
            "role": message.role == .user ? "user" : "assistant",
            "text": message.text,
            "timestamp": Timestamp(date: message.timestamp)
        ]
        Task {
            do {
                try await collection.document(message.id).setData(data)
            } catch {
                print("⚠️ Failed to save chat message: \(error.localizedDescription)")
            }
        }
    }

    private func deleteMessage(id: String) {
        guard let collection = chatCollection else { return }
        Task {
            do {
                try await collection.document(id).delete()
            } catch {
                print("⚠️ Failed to delete chat message: \(error.localizedDescription)")
            }
        }
    }

    func sendChatMessage(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }

        let userMsg = ChatMessage(role: .user, text: question)
        messages.append(userMsg)
        saveMessage(userMsg)
        lastError = nil
        isSending = true

        let history = messages.dropLast().map {
            ChatTurn(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
        let snap = snapshot

        Task { await self.performChat(question: question, history: Array(history), snapshot: snap) }
    }

    func retryLastMessage() {
        guard let last = messages.last(where: { $0.role == .user }) else { return }
        // Drop the failed user turn so we can re-send cleanly.
        if messages.last?.role == .user {
            messages.removeLast()
            deleteMessage(id: last.id)
        }
        lastError = nil
        state = .ready
        sendChatMessage(last.text)
    }

    private func performChat(question: String,
                             history: [ChatTurn],
                             snapshot: HealthSnapshot?) async {
        guard let url = URL(string: "\(liveCoachBaseURL)/chat") else {
            finishWithError("Bad chat URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let body = ChatRequestBody(snapshot: snapshot, history: history, question: question)
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            finishWithError("Failed to encode request: \(error.localizedDescription)")
            return
        }

        do {
            let (data, response) = try await Self.session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                finishWithError("Server returned HTTP \(http.statusCode).")
                return
            }
            let decoded = try Self.decoder.decode(ChatResponse.self, from: data)
            let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                finishWithError("Coach returned an empty reply.")
                return
            }
            let assistantMsg = ChatMessage(role: .assistant, text: reply)
            saveMessage(assistantMsg)
            withAnimation(AppConstants.Animation.spring) {
                messages.append(assistantMsg)
                isSending = false
                lastError = nil
                state = .ready
            }
        } catch let urlError as URLError where Self.isConnectionError(urlError) {
            isSending = false
            // Roll back the unanswered user message so retry feels clean
            if messages.last?.role == .user {
                let rolledBack = messages.removeLast()
                deleteMessage(id: rolledBack.id)
            }
            state = .offline
            lastError = nil
        } catch {
            finishWithError(error.localizedDescription)
        }
    }

    private func finishWithError(_ reason: String) {
        print("⚠️ Chat failed: \(reason)")
        isSending = false
        lastError = reason
    }

    private static func isConnectionError(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .notConnectedToInternet, .timedOut, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    private static func gatherHealthSnapshot(goalActiveKcal: Int = 500) async -> HealthSnapshot? {
        if let live = await LiveHealthDataProvider().fetchWeeklySnapshot(goalActiveKcal: goalActiveKcal) {
            return live
        }
        return await MockHealthDataProvider().fetchWeeklySnapshot(goalActiveKcal: goalActiveKcal)
    }
}

// MARK: - Main View

struct A2ACoachingView: View {
    @StateObject private var vm: A2ACoachingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    init(userUID: String?) {
        _vm = StateObject(wrappedValue: A2ACoachingViewModel(userUID: userUID))
    }

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(bloom: vm.isSending)

            VStack(spacing: 0) {
                Spacer().frame(height: 56) // room for custom top bar

                if vm.state == .offline {
                    OfflineCard(onRetry: { vm.retryLastMessage() })
                        .padding(.horizontal, AppConstants.Spacing.md)
                        .padding(.top, 8)
                        .transition(.opacity)
                } else {
                    chatScroll
                }

                inputBar
                    .padding(.horizontal, AppConstants.Spacing.md)
                    .padding(.bottom, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { topBar }
        .task { await vm.bootstrap() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Health")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            VStack(spacing: 1) {
                Text("AI Coach")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let chip = headerStatChip {
                    Text(chip)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            // Symmetric spacer so the title stays centered
            Color.clear.frame(width: 56, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var headerStatChip: String? {
        guard let s = vm.snapshot else { return nil }
        let steps = s.weeklyTotals.totalSteps
        let kcal = s.weeklyTotals.totalActiveKcal
        return "\(steps.formatted()) steps · \(kcal) kcal this week"
    }

    // MARK: Chat list

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.state == .loadingSnapshot {
                        LoadingSnapshotRow()
                    }

                    ForEach(vm.messages) { msg in
                        ChatBubble(message: msg).id(msg.id)
                    }

                    if vm.isSending {
                        TypingIndicator().id("typing")
                    }

                    if let err = vm.lastError {
                        InlineErrorRow(text: err)
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: vm.isSending) { _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                if vm.isSending {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholderForState, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(AppConstants.Color.accent)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .clipShape(Capsule())
                .focused($inputFocused)
                .disabled(vm.isSending || vm.state != .ready)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: vm.isSending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(AppConstants.Color.accent)
                    .clipShape(Circle())
                    .shadow(color: AppConstants.Color.accent.opacity(0.4), radius: 8)
                    .opacity(canSend ? 1 : 0.4)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send question")
        }
    }

    private var canSend: Bool {
        vm.state == .ready
            && !vm.isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholderForState: String {
        switch vm.state {
        case .loadingSnapshot: return "Loading your data…"
        case .offline:         return "Coach offline"
        case .ready:           return "Ask your coach anything…"
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        vm.sendChatMessage(text)
        draft = ""
    }
}

// MARK: - Subviews

private struct LoadingSnapshotRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(AppConstants.Color.accent)
            Text("Loading your weekly health data…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.vertical, 14)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    Text("💪 COACH")
                        .font(FCFont.label(10))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.45))
                }

                CoachMarkdownText(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(message.role == .user ? .white : AppConstants.Color.textOnCard)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Color.black.opacity(0.45))
                            : AnyShapeStyle(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                message.role == .user
                                    ? Color.white.opacity(0.1)
                                    : Color.white.opacity(0.0),
                                lineWidth: 0.5
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (message.role == .user ? "You: " : "Coach: ") + message.text
        )
    }
}

private struct TypingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(AppConstants.Color.mutedOnCard)
                            .frame(width: 7, height: 7)
                            .opacity(tick == i ? 1 : 0.3)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer(minLength: 40)
            }
        }
        .accessibilityLabel("Coach is typing")
    }
}

private struct InlineErrorRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppConstants.Color.warn)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
            Spacer()
        }
        .padding(10)
        .background(AppConstants.Color.warn.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct OfflineCard: View {
    let onRetry: () -> Void

    var body: some View {
        FCCard(padding: 22) {
            VStack(spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.danger)
                    .frame(width: 72, height: 72)
                    .background(AppConstants.Color.danger.opacity(0.12))
                    .clipShape(Circle())

                Text("COACH SERVER OFFLINE")
                    .font(FCFont.hero(24))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .multilineTextAlignment(.center)

                Text("The coach can't reach your Mac. Start the server before chatting.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    StepRow(number: "1", text: "Open Terminal on your Mac")
                    StepRow(number: "2", text: "cd into the CrewAI folder")
                    StepRow(number: "3", text: "Run: python server.py")
                    StepRow(number: "4", text: "Wait for 🚀, then Try Again")
                }
                .padding(14)
                .background(AppConstants.Color.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(FCPrimaryButtonStyle())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(AppConstants.Color.accent)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppConstants.Color.textOnCard)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Markdown helper

private struct CoachMarkdownText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed).fixedSize(horizontal: false, vertical: true)
        } else {
            Text(raw).fixedSize(horizontal: false, vertical: true)
        }
    }
}
