import SwiftUI

// MARK: - Server Config

/// The Flask CrewAI server (server.py) binds to 0.0.0.0:5001 on the Mac.
/// - Simulator: 127.0.0.1 (loopback — never changes, ignores VPN/WiFi state).
/// - Physical iPhone: 30s-iMac.local (Bonjour follows the Mac across IP changes;
///   iPhone must be on the same WiFi as the Mac).
private let liveCoachBaseURL: String = {
    #if targetEnvironment(simulator)
    return "http://127.0.0.1:5001"
    #else
    return "http://30s-iMac.local:5001"
    #endif
}()

// MARK: - A2A Response Models

struct A2AResponse: Decodable {
    let result: A2AResult
}

struct A2AResult: Decodable {
    let id: String
    let status: A2AStatus
    let artifacts: [A2AArtifact]
    let runMetadata: RunMetadata?
    let agentOutputs: [AgentOutput]?
}

struct A2AStatus: Decodable {
    let state: String
    let timestamp: String
}

struct A2AArtifact: Decodable {
    let artifactId: String
    let name: String
    let description: String
    let parts: [A2APart]
}

struct A2APart: Decodable {
    let kind: String
    let data: CalorieSummaryPayload
}

struct CalorieSummaryPayload: Decodable {
    let period: CaloriePeriod
    let summary: CalorieSummary
    let dailyEntries: [DailyCalorieEntry]
    let coachingNote: String
}

struct CaloriePeriod: Decodable {
    let startDate: String
    let endDate: String
}

struct CalorieSummary: Decodable {
    let totalActiveKcal: Int
    let totalRestingKcal: Int
    let totalKcal: Int
    let dailyAverageActiveKcal: Double
    let goalActiveKcalPerDay: Int
}

struct DailyCalorieEntry: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let activeKcal: Int
    let restingKcal: Int
    let steps: Int
    let exerciseMinutes: Int
}

struct RunMetadata: Decodable {
    let durationSeconds: Double
    let agentCount: Int
    let model: String
    let completedAt: String
}

struct AgentOutput: Decodable, Identifiable {
    let order: Int
    let agentRole: String
    let agentEmoji: String
    let taskDescription: String
    let output: String

    var id: Int { order }
}

// MARK: - Follow-up Chat Models

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date = Date()
}

private struct ChatRequestBody: Encodable {
    let originalReport: String
    let history: [ChatTurn]
    let question: String

    enum CodingKeys: String, CodingKey {
        case originalReport = "original_report"
        case history
        case question
    }
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

final class A2ACoachingViewModel: ObservableObject {

    enum LoadState {
        case idle
        case loading
        case loadedLive
        case loadedFallback
        case error(String)
    }

    @Published var payload: CalorieSummaryPayload?
    @Published var agentOutputs: [AgentOutput] = []
    @Published var runMetadata: RunMetadata?
    @Published var state: LoadState = .idle

    @Published var chatMessages: [ChatMessage] = []
    @Published var isChatSending: Bool = false
    @Published var chatError: String?

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }

    func load() {
        guard let url = Bundle.main.url(forResource: "mock_response", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? Self.decoder.decode(A2AResponse.self, from: data),
              let preview = response.result.artifacts.first?.parts.first?.data else {
            state = .idle
            return
        }
        payload = preview
        agentOutputs = response.result.agentOutputs ?? []
        runMetadata = response.result.runMetadata
        state = .loadedFallback
    }

    func runLiveCoach() {
        state = .loading
        Task { await self.performRun() }
    }

    @MainActor
    private func performRun() async {
        guard let url = URL(string: "\(liveCoachBaseURL)/run") else {
            loadFallbackAfterFailure(reason: "Bad URL.")
            return
        }

        let snapshot = await Self.gatherHealthSnapshot()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let snap = snapshot {
            do {
                request.httpBody = try JSONEncoder().encode(snap)
            } catch {
                print("⚠️ Failed to encode HealthSnapshot: \(error)")
            }
        }

        Self.liveCoachSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.dispatchFallback(reason: error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                self.dispatchFallback(reason: "HTTP \(http.statusCode)")
                return
            }
            guard let data = data else {
                self.dispatchFallback(reason: "Empty response.")
                return
            }
            do {
                let decoded = try Self.decoder.decode(A2AResponse.self, from: data)
                guard let live = decoded.result.artifacts.first?.parts.first?.data else {
                    self.dispatchFallback(reason: "No artifact in response.")
                    return
                }
                DispatchQueue.main.async {
                    withAnimation(AppConstants.Animation.spring) {
                        self.payload = live
                        self.agentOutputs = decoded.result.agentOutputs ?? []
                        self.runMetadata = decoded.result.runMetadata
                        self.state = .loadedLive
                        self.chatMessages = []
                        self.chatError = nil
                    }
                }
            } catch {
                self.dispatchFallback(reason: "Decode failed: \(error.localizedDescription)")
            }
        }.resume()
    }

    // MARK: Follow-up Chat

    var canChat: Bool {
        switch state {
        case .loadedLive, .loadedFallback: return true
        default: return false
        }
    }

    private func originalReportText() -> String {
        var parts: [String] = []

        if let p = payload {
            var dataBlock = "=== USER'S HEALTH DATA ===\n"
            dataBlock += "Period: \(p.period.startDate) to \(p.period.endDate)\n"
            dataBlock += "Total active kcal: \(p.summary.totalActiveKcal)\n"
            dataBlock += "Total resting kcal: \(p.summary.totalRestingKcal)\n"
            dataBlock += "Daily average active kcal: \(Int(p.summary.dailyAverageActiveKcal))\n"
            dataBlock += "Goal: \(p.summary.goalActiveKcalPerDay) active kcal/day\n"
            if !p.dailyEntries.isEmpty {
                dataBlock += "\nDaily breakdown:\n"
                for entry in p.dailyEntries {
                    dataBlock += "  \(entry.date): \(entry.activeKcal) active kcal, \(entry.restingKcal) resting kcal, \(entry.steps) steps, \(entry.exerciseMinutes) exercise min\n"
                }
            }
            parts.append(dataBlock)
        }

        if !agentOutputs.isEmpty {
            let agentBlock = "=== COACHING REPORT ===\n" + agentOutputs
                .map { "[\($0.agentRole)]\n\($0.output)" }
                .joined(separator: "\n\n")
            parts.append(agentBlock)
        } else if let note = payload?.coachingNote, !note.isEmpty {
            parts.append("=== COACHING REPORT ===\n" + note)
        }

        return parts.joined(separator: "\n\n")
    }

    func sendChatMessage(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isChatSending, canChat else { return }

        chatMessages.append(ChatMessage(role: .user, text: question))
        chatError = nil
        isChatSending = true

        let historyForServer = chatMessages.dropLast().map { msg in
            ChatTurn(role: msg.role == .user ? "user" : "assistant", content: msg.text)
        }
        let reportText = originalReportText()

        Task { await self.performChat(question: question,
                                      history: historyForServer,
                                      originalReport: reportText) }
    }

    @MainActor
    private func performChat(question: String,
                             history: [ChatTurn],
                             originalReport: String) async {
        guard let url = URL(string: "\(liveCoachBaseURL)/chat") else {
            self.finishChat(error: "Bad chat URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let body = ChatRequestBody(originalReport: originalReport,
                                       history: history,
                                       question: question)
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            self.finishChat(error: "Failed to encode chat request: \(error.localizedDescription)")
            return
        }

        Self.liveCoachSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.dispatchChatError(error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                self.dispatchChatError("HTTP \(http.statusCode)")
                return
            }
            guard let data = data else {
                self.dispatchChatError("Empty response.")
                return
            }
            do {
                let decoded = try Self.decoder.decode(ChatResponse.self, from: data)
                let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reply.isEmpty else {
                    self.dispatchChatError("Coach returned an empty reply.")
                    return
                }
                DispatchQueue.main.async {
                    withAnimation(AppConstants.Animation.spring) {
                        self.chatMessages.append(ChatMessage(role: .assistant, text: reply))
                        self.isChatSending = false
                        self.chatError = nil
                    }
                }
            } catch {
                self.dispatchChatError("Decode failed: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func dispatchChatError(_ reason: String) {
        DispatchQueue.main.async { [weak self] in self?.finishChat(error: reason) }
    }

    private func finishChat(error: String) {
        print("⚠️ Chat failed: \(error)")
        isChatSending = false
        chatError = error
    }

    private func dispatchFallback(reason: String) {
        DispatchQueue.main.async { [weak self] in self?.loadFallbackAfterFailure(reason: reason) }
    }

    private func loadFallbackAfterFailure(reason: String) {
        print("⚠️ Live coach failed (\(reason))")
        // User tapped Cancel — don't show any error, just go back to idle
        if reason.localizedCaseInsensitiveContains("cancelled") ||
           reason.localizedCaseInsensitiveContains("canceled") {
            state = .idle
            return
        }
        let isConnectionError = reason.localizedCaseInsensitiveContains("connect") ||
                                reason.localizedCaseInsensitiveContains("refused") ||
                                reason.localizedCaseInsensitiveContains("timed out") ||
                                reason.localizedCaseInsensitiveContains("offline") ||
                                reason.localizedCaseInsensitiveContains("network")
        if isConnectionError {
            state = .error("server_offline")
            return
        }
        // Non-connection error — fall back to cached demo data if available
        guard let url = Bundle.main.url(forResource: "mock_response", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? Self.decoder.decode(A2AResponse.self, from: data),
              let cached = response.result.artifacts.first?.parts.first?.data else {
            state = .error("Live coach unavailable and no cached data found.")
            return
        }
        payload = cached
        agentOutputs = response.result.agentOutputs ?? []
        runMetadata = response.result.runMetadata
        state = .loadedFallback
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func gatherHealthSnapshot(goalActiveKcal: Int = 500) async -> HealthSnapshot? {
        if let live = await LiveHealthDataProvider().fetchWeeklySnapshot(goalActiveKcal: goalActiveKcal) {
            return live
        }
        return await MockHealthDataProvider().fetchWeeklySnapshot(goalActiveKcal: goalActiveKcal)
    }

    func cancelRun() {
        Self.liveCoachSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        DispatchQueue.main.async { self.state = .idle }
    }

    private static let liveCoachSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10   // fail fast if server is unreachable
        config.timeoutIntervalForResource = 600 // allow full crew run once connected
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}

// MARK: - Agent palette

private enum AgentPalette {
    static func avatarColor(for index: Int) -> Color {
        let palette: [Color] = [
            AppConstants.Color.accent,
            Color(hex: "F2A1B5"),   // pink
            Color(hex: "8FD675"),   // green
            AppConstants.Color.warn
        ]
        return palette[index % palette.count]
    }

    static let readyPreviews: [(emoji: String, title: String, subtitle: String)] = [
        ("🎨", "UI Designer", "Drafts layouts and visual ideas"),
        ("💪", "HealthKit Analyst", "Reads your activity + sleep data"),
        ("🧪", "QA Engineer", "Validates final recommendation")
    ]
}

// MARK: - Main View

struct A2ACoachingView: View {
    @StateObject private var vm = A2ACoachingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(bloom: vm.isLoading)

            // Hero word per state (Loading hides it; Offline uses OFFLINE).
            heroWordForState

            ScrollView {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                    if vm.isLoading {
                        LoadingStateView(onCancel: { vm.cancelRun() })
                    } else if let msg = vm.errorMessage {
                        OfflineStateView(
                            isServerOffline: msg == "server_offline",
                            onRetry: { vm.runLiveCoach() }
                        )
                    } else if let payload = vm.payload {
                        ResultStateView(vm: vm, payload: payload)
                    } else {
                        ReadyStateView(onStart: { vm.runLiveCoach() })
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.top, 70)
                .padding(.bottom, 48)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { customTopBar }
        .task {
            if case .idle = vm.state { vm.load() }
        }
    }

    // MARK: Custom top bar (Health < · AI Coach · Run)

    private var customTopBar: some View {
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

            Text("AI Coach")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Spacer()

            runOrRerunPill
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var runOrRerunPill: some View {
        let isInitial: Bool = {
            switch vm.state { case .idle: return true; default: return false }
        }()

        if isInitial {
            Button(action: { vm.runLiveCoach() }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                    Text("Run").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppConstants.Color.accent)
                .clipShape(Capsule())
                .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 10)
            }
            .disabled(vm.isLoading)
        } else if !vm.isLoading {
            Button(action: { vm.runLiveCoach() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    Text("Rerun").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .clipShape(Capsule())
            }
        } else {
            Color.clear.frame(width: 78, height: 32)
        }
    }

    @ViewBuilder
    private var heroWordForState: some View {
        switch vm.state {
        case .idle:
            HeroWord(text: "AI COACH", size: 88, side: .trailing, top: 50)
        case .error:
            HeroWord(text: "OFFLINE", size: 140, side: .leading, top: 50)
        case .loading, .loadedLive, .loadedFallback:
            EmptyView()
        }
    }
}

// MARK: - State 1: Ready

private struct ReadyStateView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("READY TO RUN")
                    .font(FCFont.hero(44))
                    .foregroundStyle(.white)
                Text("Three agents will collaborate to design your next workout.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(Array(AgentPalette.readyPreviews.enumerated()), id: \.offset) { idx, agent in
                    AgentCard(
                        emoji: agent.emoji,
                        title: agent.title,
                        subtitle: agent.subtitle,
                        stepLabel: "STEP \(idx + 1)",
                        accent: AgentPalette.avatarColor(for: idx)
                    )
                }
            }

            Button(action: onStart) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 16, weight: .bold))
                    Text("Start AI Coaching")
                }
            }
            .buttonStyle(FCPrimaryButtonStyle())
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text("Live runs take 2 – 5 minutes")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AgentCard: View {
    let emoji: String
    let title: String
    let subtitle: String
    let stepLabel: String
    let accent: Color

    var body: some View {
        FCCard(padding: 14) {
            HStack(spacing: 14) {
                AgentAvatar(emoji: emoji, accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
                Spacer()
                Text(stepLabel)
                    .font(FCFont.label(11))
                    .tracking(1.2)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
    }
}

private struct AgentAvatar: View {
    let emoji: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.85))
            Text(emoji).font(.system(size: 20))
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - State 2: Loading (the orb)

private struct LoadingStateView: View {
    let onCancel: () -> Void
    @State private var animate = false
    @State private var startedAt: Date = Date()
    @State private var elapsedText: String = "0:00"

    private let stages = [
        ("🎨", "UI Designer working…"),
        ("💪", "HealthKit Analyst working…"),
        ("🧪", "QA Engineer working…"),
    ]

    private func currentStage(now: Date) -> Int {
        let elapsed = now.timeIntervalSince(startedAt)
        return min(stages.count - 1, Int(elapsed / 8))
    }

    var body: some View {
        VStack(spacing: 28) {
            Text("THINKING…")
                .font(FCFont.hero(64))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            orb
                .frame(width: 260, height: 260)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                stageCard(now: ctx.date)
            }

            Text("Running on local hardware · llama3.2:3b")
                .font(FCFont.mono(11))
                .foregroundStyle(.white.opacity(0.45))

            Button("Cancel", action: onCancel)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .onAppear {
            startedAt = Date()
            animate = true
        }
    }

    private var orb: some View {
        ZStack {
            // Ambient bloom behind everything
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppConstants.Color.accent.opacity(0.32),
                            AppConstants.Color.accent.opacity(0.12),
                            .clear
                        ],
                        center: .center, startRadius: 0, endRadius: 130
                    )
                )
                .blur(radius: 6)

            // Three pulsing rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(AppConstants.Color.accent, lineWidth: 1.5)
                    .opacity(0.7 - Double(i) * 0.2)
                    .shadow(color: AppConstants.Color.accent.opacity(0.45), radius: 12)
                    .scaleEffect(animate ? 1.0 : 0.4)
                    .animation(
                        .easeOut(duration: 2.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.8),
                        value: animate
                    )
            }

            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppConstants.Color.accentLight,
                            AppConstants.Color.accent,
                            AppConstants.Color.accentDark
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 4, endRadius: 60
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(color: AppConstants.Color.accent.opacity(0.7), radius: 40)
                .shadow(color: AppConstants.Color.accent.opacity(0.5), radius: 15)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                )
        }
    }

    @ViewBuilder
    private func stageCard(now: Date) -> some View {
        let stage = currentStage(now: now)
        let elapsed = now.timeIntervalSince(startedAt)
        let mm = Int(elapsed) / 60
        let ss = Int(elapsed) % 60
        let elapsedStr = String(format: "%d:%02d", mm, ss)

        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(stages[stage].0).font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stages[stage].1)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppConstants.Color.textOnCard)
                        Text("\(elapsedStr) elapsed · step \(stage + 1) of \(stages.count)")
                            .font(FCFont.mono(11))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                    }
                    Spacer()
                }
                ShimmerBar()
                    .frame(height: 3)
            }
        }
    }
}

private struct ShimmerBar: View {
    @State private var offset: CGFloat = -0.4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppConstants.Color.divider)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, AppConstants.Color.accent, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.4)
                    .offset(x: offset * proxy.size.width)
            }
        }
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                offset = 1.0
            }
        }
    }
}

// MARK: - State 3 / 4: Live or Cached result

private struct ResultStateView: View {
    @ObservedObject var vm: A2ACoachingViewModel
    let payload: CalorieSummaryPayload

    private var isLive: Bool {
        if case .loadedLive = vm.state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ResultHeroBanner(
                isLive: isLive,
                metadata: vm.runMetadata,
                agentCount: vm.agentOutputs.count
            )

            if !vm.agentOutputs.isEmpty {
                ForEach(Array(vm.agentOutputs.enumerated()), id: \.element.id) { idx, output in
                    ExpandableAgentCard(
                        output: output,
                        accent: AgentPalette.avatarColor(for: idx),
                        defaultExpanded: idx == 0
                    )
                }
            } else if !payload.coachingNote.isEmpty {
                CoachingNoteCard(note: payload.coachingNote)
            }

            if hasCalorieData {
                StatsBento(summary: payload.summary)
                DailyBreakdownSection(entries: payload.dailyEntries, goal: payload.summary.goalActiveKcalPerDay)
            }

            if vm.canChat {
                AskTheCoachCard(vm: vm)
            }
        }
    }

    private var hasCalorieData: Bool {
        payload.summary.totalKcal > 0 || !payload.dailyEntries.isEmpty
    }
}

private struct ResultHeroBanner: View {
    let isLive: Bool
    let metadata: RunMetadata?
    let agentCount: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            background

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(isLive ? "LIVE RESULT" : "CACHED PLAN")
                        .font(FCFont.hero(36))
                        .foregroundStyle(textColor)
                    Spacer()
                    statusPill
                }

                HStack(spacing: 8) {
                    if let m = metadata {
                        DarkChip(icon: "stopwatch", text: formattedDuration(m.durationSeconds))
                        DarkChip(emoji: "🧠", text: "\(m.agentCount) agents")
                        DarkChip(emoji: "✨", text: shortModelName(m.model))
                    } else {
                        DarkChip(emoji: "🧠", text: "\(agentCount) agents")
                    }
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
        .shadow(color: (isLive ? AppConstants.Color.accent : .black).opacity(0.25), radius: 14, y: 6)
    }

    private var background: some View {
        Group {
            if isLive {
                LinearGradient(
                    colors: [AppConstants.Color.accent, AppConstants.Color.accentDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(hex: "1A1A1A")
            }
        }
    }

    private var textColor: Color { isLive ? .black : .white }

    @ViewBuilder
    private var statusPill: some View {
        if isLive {
            HStack(spacing: 6) {
                Circle().fill(AppConstants.Color.success).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(FCFont.label(11))
                    .tracking(1.0)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white)
            .clipShape(Capsule())
        } else {
            HStack(spacing: 6) {
                Circle().fill(AppConstants.Color.warn).frame(width: 6, height: 6)
                Text("CACHED")
                    .font(FCFont.label(11))
                    .tracking(1.0)
            }
            .foregroundStyle(AppConstants.Color.warn)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private func shortModelName(_ s: String) -> String {
        s.split(separator: "/").last.map(String.init) ?? s
    }

    private func formattedDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return s == 0 ? "\(m)m" : "\(m)m \(String(format: "%02d", s))s"
    }
}

private struct DarkChip: View {
    var icon: String? = nil
    var emoji: String? = nil
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            if let emoji = emoji {
                Text(emoji).font(.system(size: 11))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.30))
        .clipShape(Capsule())
    }
}

// MARK: - Expandable agent card (with colored left stripe)

private struct ExpandableAgentCard: View {
    let output: AgentOutput
    let accent: Color
    let defaultExpanded: Bool

    @State private var expanded: Bool

    init(output: AgentOutput, accent: Color, defaultExpanded: Bool) {
        self.output = output
        self.accent = accent
        self.defaultExpanded = defaultExpanded
        _expanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        FCCard(padding: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if expanded { expandedBody }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(AppConstants.Animation.spring, value: expanded)
    }

    private var header: some View {
        Button(action: { expanded.toggle() }) {
            HStack(spacing: 12) {
                AgentAvatar(emoji: output.agentEmoji, accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(output.agentRole)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Text("Step \(output.order)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().background(AppConstants.Color.divider)

            if !output.taskDescription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TASK")
                        .font(FCFont.label(11))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.accent)
                    Text(output.taskDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("OUTPUT")
                    .font(FCFont.label(11))
                    .tracking(1.0)
                    .foregroundStyle(AppConstants.Color.accent)
                CoachMarkdownText(output.output)
                    .font(.system(size: 14))
                    .foregroundStyle(AppConstants.Color.textOnCard)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 6)
        .transition(.opacity)
    }
}

private struct CoachingNoteCard: View {
    let note: String

    var body: some View {
        FCCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("COACH NOTE")
                    .font(FCFont.label(11))
                    .tracking(1.0)
                    .foregroundStyle(AppConstants.Color.accent)
                CoachMarkdownText(note)
                    .font(.system(size: 14))
                    .foregroundStyle(AppConstants.Color.textOnCard)
            }
        }
    }
}

// MARK: - 2×2 stats bento

private struct StatsBento: View {
    let summary: CalorieSummary

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BentoStat(value: summary.totalActiveKcal.formatted(), label: "KCAL ACTIVE TODAY")
                BentoStat(value: summary.totalKcal.formatted(), label: "KCAL THIS WEEK")
            }
            HStack(spacing: 10) {
                BentoStat(value: Int(summary.dailyAverageActiveKcal).formatted(), label: "KCAL DAILY AVG")
                BentoStat(value: summary.goalActiveKcalPerDay.formatted(), label: "KCAL DAILY GOAL")
            }
        }
    }
}

private struct BentoStat: View {
    let value: String
    let label: String

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(FCFont.stat(32))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(FCFont.label(10))
                    .tracking(1.0)
                    .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Daily breakdown

private struct DailyBreakdownSection: View {
    let entries: [DailyCalorieEntry]
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FCSectionLabel(text: "Daily Breakdown", color: .white.opacity(0.5))
            ForEach(entries) { entry in
                DailyEntryRow(entry: entry, goal: goal)
            }
        }
    }
}

private struct DailyEntryRow: View {
    let entry: DailyCalorieEntry
    let goal: Int

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(entry.activeKcal) / Double(goal), 1.0)
    }
    private var goalMet: Bool { entry.activeKcal >= goal }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: entry.date) else { return entry.date }
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(formattedDate)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppConstants.Color.textOnCard)
                    Spacer()
                    if goalMet {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppConstants.Color.accentDark)
                            .accessibilityLabel("Goal met")
                    }
                    Text("\(entry.activeKcal) kcal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(goalMet ? AppConstants.Color.accentDark : AppConstants.Color.textOnCard)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppConstants.Color.divider)
                        Capsule()
                            .fill(goalMet ? AppConstants.Color.accent : AppConstants.Color.warn)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)

                HStack(spacing: 14) {
                    Label("\(entry.steps.formatted()) steps", systemImage: "figure.walk")
                    Label("\(entry.exerciseMinutes) min", systemImage: "clock")
                }
                .font(.system(size: 11))
                .foregroundStyle(AppConstants.Color.mutedOnCard)
            }
        }
    }
}

// MARK: - Ask the Coach card

private struct AskTheCoachCard: View {
    @ObservedObject var vm: A2ACoachingViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        FCCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ASK THE COACH")
                    .font(FCFont.label(11))
                    .tracking(1.0)
                    .foregroundStyle(AppConstants.Color.accent)

                if vm.chatMessages.isEmpty && !vm.isChatSending {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                        Text("Have a question about your report? Ask below.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                        Spacer()
                    }
                } else {
                    ScrollViewReader { proxy in
                        VStack(spacing: 8) {
                            ForEach(vm.chatMessages) { msg in
                                ChatBubble(message: msg).id(msg.id)
                            }
                            if vm.isChatSending {
                                TypingIndicator().id("typing")
                            }
                        }
                        .onChange(of: vm.chatMessages.count) { _ in scrollToBottom(proxy) }
                        .onChange(of: vm.isChatSending) { _ in scrollToBottom(proxy) }
                    }
                }

                if let err = vm.chatError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppConstants.Color.warn)
                        Text(err).font(.system(size: 11))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding(8)
                    .background(AppConstants.Color.warn.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                inputBar
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(AppConstants.Color.textOnCard)
                .tint(AppConstants.Color.accent)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppConstants.Color.cardSecondary)
                .clipShape(Capsule())
                .focused($focused)
                .disabled(vm.isChatSending)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
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
        !vm.isChatSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !vm.isChatSending else { return }
        vm.sendChatMessage(text)
        draft = ""
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                if vm.isChatSending {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let last = vm.chatMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 32) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    Text("💪 COACH")
                        .font(FCFont.label(10))
                        .tracking(1.0)
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                }

                CoachMarkdownText(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(message.role == .user ? .white : AppConstants.Color.textOnCard)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(message.role == .user ? Color.black : AppConstants.Color.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if message.role == .assistant { Spacer(minLength: 32) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (message.role == .user ? "You said: " : "Coach replied: ") + message.text
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
                .padding(.vertical, 9)
                .background(AppConstants.Color.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer(minLength: 32)
            }
        }
        .accessibilityLabel("Coach is typing")
    }
}

// MARK: - State 5: Offline

private struct OfflineStateView: View {
    let isServerOffline: Bool
    let onRetry: () -> Void

    var body: some View {
        FCCard(padding: 28) {
            VStack(spacing: 16) {
                Image(systemName: isServerOffline ? "server.rack" : "wifi.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppConstants.Color.danger)
                    .frame(width: 88, height: 88)
                    .background(AppConstants.Color.danger.opacity(0.12))
                    .clipShape(Circle())

                Text(isServerOffline ? "SERVER NOT RUNNING" : "COACH UNAVAILABLE")
                    .font(FCFont.hero(28))
                    .foregroundStyle(AppConstants.Color.textOnCard)
                    .multilineTextAlignment(.center)

                if isServerOffline {
                    VStack(spacing: 10) {
                        Text("The AI Coach server isn't running. Start it on your Mac before using this feature.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppConstants.Color.mutedOnCard)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        // Step-by-step instructions
                        VStack(alignment: .leading, spacing: 8) {
                            StepRow(number: "1", text: "Open Terminal on your Mac")
                            StepRow(number: "2", text: "cd into the CrewAI folder")
                            StepRow(number: "3", text: "Run: python server.py")
                            StepRow(number: "4", text: "Wait for 🚀 then tap Try Again")
                        }
                        .padding(14)
                        .background(AppConstants.Color.cardSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    Text("We couldn't reach the local model. Make sure Ollama is running and try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppConstants.Color.mutedOnCard)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(FCPrimaryButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 80)
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
