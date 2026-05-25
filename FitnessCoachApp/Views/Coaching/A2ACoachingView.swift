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
    let role: String      // "user" or "assistant"
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

    // Follow-up chat state. Conversation lives in memory only — cleared on
    // navigate-away or when a fresh /run replaces the underlying report.
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

    /// Initial load: if the bundled mock exists, show it as a sample. If not,
    /// stay idle so the user sees the "ready to run" empty state instead of an
    /// error. We only surface real errors after the user has explicitly hit Run.
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

    /// Async wrapper: gathers the user's real HealthKit snapshot (or seeded mock
    /// on simulator) and POSTs it to the Flask CrewAI server.
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
                let encoder = JSONEncoder()
                request.httpBody = try encoder.encode(snap)
                print("📤 Sending HealthKit snapshot (\(snap.dataSource)) to /run.")
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
                        // Fresh report → start a new chat thread.
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

    /// Whether the chat UI should be visible. We only allow follow-ups once
    /// a live or cached report exists — there's nothing to discuss otherwise.
    var canChat: Bool {
        switch state {
        case .loadedLive, .loadedFallback: return true
        default: return false
        }
    }

    /// Builds the "original_report" string sent to /chat.
    /// Includes the raw daily data so the LLM can answer specific numeric
    /// questions (e.g. "how many calories did I burn on May 19?").
    private func originalReportText() -> String {
        var parts: [String] = []

        // 1. Raw daily data — gives the LLM concrete numbers to reference
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

        // 2. Agent coaching outputs
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
        guard !question.isEmpty else { return }
        guard !isChatSending else { return }
        guard canChat else { return }

        let userMessage = ChatMessage(role: .user, text: question)
        chatMessages.append(userMessage)
        chatError = nil
        isChatSending = true

        // Snapshot history *excluding* the just-appended user turn — the
        // server appends the new question itself.
        let historyForServer = chatMessages.dropLast().map { msg in
            ChatTurn(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.text
            )
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
            let body = ChatRequestBody(
                originalReport: originalReport,
                history: history,
                question: question
            )
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
        DispatchQueue.main.async { [weak self] in
            self?.finishChat(error: reason)
        }
    }

    private func finishChat(error: String) {
        print("⚠️ Chat failed: \(error)")
        isChatSending = false
        chatError = error
    }

    private func dispatchFallback(reason: String) {
        DispatchQueue.main.async { [weak self] in
            self?.loadFallbackAfterFailure(reason: reason)
        }
    }

    private func loadFallbackAfterFailure(reason: String) {
        print("⚠️ Live coach failed (\(reason)) — falling back to cached data.")
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

    /// Best-effort HealthKit snapshot for the AI Coach payload.
    /// Order: live HealthKit → seeded mock (so simulator demos still work).
    private static func gatherHealthSnapshot(goalActiveKcal: Int = 500) async -> HealthSnapshot? {
        if let live = await LiveHealthDataProvider().fetchWeeklySnapshot(goalActiveKcal: goalActiveKcal) {
            return live
        }
        return await MockHealthDataProvider().fetchWeeklySnapshot(goalActiveKcal: goalActiveKcal)
    }

    /// Dedicated session so CrewAI's multi-minute kickoff doesn't get killed by
    /// URLSession.shared's default 60s session timeouts. CrewAI with 3 agents on
    /// a local Ollama can take 3–5 min.
    private static let liveCoachSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
}

// MARK: - Main View

struct A2ACoachingView: View {
    @StateObject private var vm = A2ACoachingViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Color.pageBackground.ignoresSafeArea()

                if vm.isLoading {
                    LoadingView()
                } else if let message = vm.errorMessage {
                    errorView(message: message)
                } else if let payload = vm.payload {
                    coachingContent(payload)
                } else {
                    emptyView
                }
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    runButton
                }
            }
            .task {
                if case .idle = vm.state { vm.load() }
            }
        }
    }

    // MARK: Toolbar Run Button

    private var runButton: some View {
        Button(action: { vm.runLiveCoach() }) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Run")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(AppConstants.Color.onBrand)
            .clipShape(Capsule())
            .shadow(color: AppConstants.Color.brand.opacity(0.4), radius: 6, y: 2)
        }
        .disabled(vm.isLoading)
        .accessibilityLabel("Run AI Coach")
        .accessibilityHint("Triggers live AI analysis. May take a few minutes.")
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Coach Unavailable")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: { vm.runLiveCoach() }) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Empty

    private var emptyView: some View {
        ReadyToRunView { vm.runLiveCoach() }
    }

    // MARK: Coaching Content

    @ViewBuilder
    private func coachingContent(_ payload: CalorieSummaryPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                HeroBanner(
                    state: vm.state,
                    metadata: vm.runMetadata,
                    agentCount: vm.agentOutputs.count
                )

                if !vm.agentOutputs.isEmpty {
                    AgentOutputsSection(outputs: vm.agentOutputs)
                } else {
                    CoachingNoteCard(note: payload.coachingNote)
                }

                if hasCalorieData(payload) {
                    SummaryStatsSection(summary: payload.summary)
                    DailyBreakdownSection(
                        entries: payload.dailyEntries,
                        goal: payload.summary.goalActiveKcalPerDay
                    )
                }

                if vm.canChat {
                    FollowUpChatSection(vm: vm)
                }
            }
            .padding(AppConstants.Spacing.md)
        }
    }

    private func hasCalorieData(_ payload: CalorieSummaryPayload) -> Bool {
        payload.summary.totalKcal > 0 || !payload.dailyEntries.isEmpty
    }
}

// MARK: - Ready-to-Run (initial empty state)

private struct ReadyToRunView: View {
    let onStart: () -> Void

    @State private var pulse = false

    private let agentPreviews: [(emoji: String, title: String, subtitle: String, color: Color)] = [
        ("🎨", "UI Designer", "Suggests SwiftUI improvements", AppConstants.Color.brand),
        ("💪", "Health Analyst", "Reads your fitness data", .pink),
        ("🧪", "QA Engineer", "Reviews and approves output", .green),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.xl) {
                hero
                agentList
                startButton
                hint
            }
            .padding(AppConstants.Spacing.lg)
        }
    }

    private var hero: some View {
        VStack(spacing: AppConstants.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppConstants.Color.brand.opacity(0.15), AppConstants.Color.brandDark.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2).repeatForever(), value: pulse)

                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, AppConstants.Spacing.lg)

            Text("Ready When You Are")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Your personal crew of AI agents is standing by to review your fitness data and give you a tailored coaching report.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .onAppear { pulse = true }
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Text("Meet your crew")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, AppConstants.Spacing.sm)

            VStack(spacing: AppConstants.Spacing.sm) {
                ForEach(agentPreviews, id: \.title) { agent in
                    HStack(spacing: AppConstants.Spacing.md) {
                        AgentAvatar(emoji: agent.emoji, accent: agent.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.title)
                                .font(.subheadline.bold())
                            Text(agent.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(AppConstants.Spacing.md)
                    .background(AppConstants.Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
                }
            }
        }
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Start AI Coaching")
                    .fontWeight(.bold)
            }
            .font(.headline)
            .foregroundStyle(AppConstants.Color.onBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppConstants.Spacing.md)
            .background(
                LinearGradient(
                    colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: AppConstants.Color.brand.opacity(0.4), radius: 12, y: 6)
        }
        .accessibilityHint("Starts a live AI coaching session. Takes a few minutes.")
    }

    private var hint: some View {
        Label("Live runs take 2–5 minutes", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Hero Banner

private struct HeroBanner: View {
    let state: A2ACoachingViewModel.LoadState
    let metadata: RunMetadata?
    let agentCount: Int

    @State private var gradientAngle: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(AppConstants.Color.onBrand)
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(AppConstants.Color.onBrand)
                Spacer()
                statusPill
            }

            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(AppConstants.Color.onBrand.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if !metadataPills.isEmpty {
                HStack(spacing: 8) {
                    ForEach(metadataPills, id: \.self) { pill in
                        MetadataPill(text: pill)
                    }
                }
            }
        }
        .padding(AppConstants.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                AngularGradient(
                    colors: [AppConstants.Color.brand, AppConstants.Color.brandDark, AppConstants.Color.brand],
                    center: .center,
                    angle: .degrees(gradientAngle)
                )
                LinearGradient(
                    colors: [.black.opacity(0.15), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .shadow(color: AppConstants.Color.brandDark.opacity(0.3), radius: 12, y: 6)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                gradientAngle = 360
            }
        }
    }

    private var statusIcon: String {
        switch state {
        case .loadedLive: return "dot.radiowaves.left.and.right"
        case .loadedFallback: return "tray.full"
        default: return "sparkles"
        }
    }

    private var statusTitle: String {
        switch state {
        case .loadedLive: return "Live AI Result"
        case .loadedFallback: return "Cached Sample"
        default: return "AI Coach"
        }
    }

    private var statusSubtitle: String {
        switch state {
        case .loadedLive:
            return agentCount > 0
                ? "\(agentCount) AI agents collaborated to produce this report."
                : "Live analysis from the FitnessCoach agent crew."
        case .loadedFallback:
            return "Tap Run for a fresh live analysis from your AI crew."
        default:
            return ""
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch state {
        case .loadedLive:
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppConstants.Color.onBrand.opacity(0.15))
            .foregroundStyle(AppConstants.Color.onBrand)
            .clipShape(Capsule())
        case .loadedFallback:
            Text("CACHED")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppConstants.Color.onBrand.opacity(0.15))
                .foregroundStyle(AppConstants.Color.onBrand)
                .clipShape(Capsule())
        default:
            EmptyView()
        }
    }

    private var metadataPills: [String] {
        guard let meta = metadata else { return [] }
        var pills: [String] = []
        pills.append("⏱ \(formattedDuration(meta.durationSeconds))")
        pills.append("🧠 \(meta.agentCount) agents")
        if let modelName = meta.model.split(separator: "/").last {
            pills.append("✨ \(modelName)")
        }
        return pills
    }

    private func formattedDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return remaining == 0 ? "\(minutes)m" : "\(minutes)m \(remaining)s"
    }
}

private struct MetadataPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppConstants.Color.onBrand.opacity(0.15))
            .foregroundStyle(AppConstants.Color.onBrand)
            .clipShape(Capsule())
    }
}

// MARK: - Agent Outputs Section

private struct AgentOutputsSection: View {
    let outputs: [AgentOutput]
    @State private var appeared: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack {
                Text("Agent Reports")
                    .font(.title2.bold())
                Spacer()
                Text("\(outputs.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppConstants.Color.brand.opacity(0.2))
                    .foregroundStyle(AppConstants.Color.onBrand)
                    .clipShape(Capsule())
            }

            ForEach(Array(outputs.enumerated()), id: \.element.id) { index, output in
                AgentOutputCard(output: output, accent: accentColor(for: index))
                    .opacity(appeared.contains(output.id) ? 1 : 0)
                    .offset(y: appeared.contains(output.id) ? 0 : 20)
                    .onAppear {
                        withAnimation(AppConstants.Animation.spring.delay(Double(index) * 0.12)) {
                            _ = appeared.insert(output.id)
                        }
                    }
            }
        }
    }

    private func accentColor(for index: Int) -> Color {
        let palette: [Color] = [AppConstants.Color.brand, .pink, .green, .orange, AppConstants.Color.brandDark]
        return palette[index % palette.count]
    }
}

private struct AgentOutputCard: View {
    let output: AgentOutput
    let accent: Color

    @State private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(AppConstants.Animation.spring) { expanded.toggle() } }) {
                HStack(spacing: AppConstants.Spacing.md) {
                    AgentAvatar(emoji: output.agentEmoji, accent: accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(output.agentRole)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text("Step \(output.order)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(AppConstants.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Divider()

                    if !output.taskDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Task", systemImage: "list.bullet.rectangle")
                                .font(.caption2.bold())
                                .foregroundStyle(accent)
                            Text(output.taskDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, AppConstants.Spacing.sm)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Output", systemImage: "text.alignleft")
                            .font(.caption2.bold())
                            .foregroundStyle(accent)
                        MarkdownText(output.output)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, AppConstants.Spacing.xs)
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.bottom, AppConstants.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .fill(AppConstants.Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.1), radius: 6, y: 2)
    }
}

private struct AgentAvatar: View {
    let emoji: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.8), accent.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            Text(emoji)
                .font(.title3)
        }
        .shadow(color: accent.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Markdown Text (renders **bold**, lists, headers)

private struct MarkdownText: View {
    let raw: String

    init(_ raw: String) { self.raw = raw }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(raw)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Loading View (multi-stage)

private struct LoadingView: View {
    @State private var pulse = false
    @State private var rotation: Double = 0
    @State private var startedAt: Date = Date()

    private let stages = [
        ("🎨", "Designer drafting UI ideas..."),
        ("💪", "Health analyst crunching data..."),
        ("🧪", "QA reviewing the output..."),
        ("✨", "Polishing the final report..."),
    ]

    private func activeStage(now: Date) -> Int {
        let elapsed = now.timeIntervalSince(startedAt)
        return Int(elapsed / 4) % stages.count
    }

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xl) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppConstants.Color.brand, AppConstants.Color.brandDark, AppConstants.Color.brand],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 100 + CGFloat(i * 28), height: 100 + CGFloat(i * 28))
                        .scaleEffect(pulse ? 1.05 : 0.95)
                        .opacity(0.6 - Double(i) * 0.2)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever().delay(Double(i) * 0.2),
                            value: pulse
                        )
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 38))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotation))
            }

            VStack(spacing: AppConstants.Spacing.sm) {
                Text("AI Coach is thinking…")
                    .font(.title3.bold())

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let stage = activeStage(now: context.date)
                    HStack(spacing: 8) {
                        Text(stages[stage].0)
                            .font(.title3)
                        Text(stages[stage].1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .id(stage)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .animation(.easeInOut, value: stage)
                }

                Text("This can take 2–5 minutes on local hardware.")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, AppConstants.Spacing.sm)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startedAt = Date()
            pulse = true
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Coaching Note Card (fallback when no agent breakdown)

private struct CoachingNoteCard: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(AppConstants.Color.onBrand)
                    .accessibilityHidden(true)
                Text("Coach Note")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppConstants.Color.onBrand.opacity(0.75))
            }
            MarkdownText(note)
                .font(.subheadline)
                .foregroundStyle(AppConstants.Color.onBrand)
        }
        .padding(AppConstants.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach says: \(note)")
    }
}

// MARK: - Summary Stats Section

private struct SummaryStatsSection: View {
    let summary: CalorieSummary
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            Text("This Week")
                .font(.title2.bold())
            LazyVGrid(columns: columns, spacing: AppConstants.Spacing.md) {
                SummaryStatCard(title: "Active", value: summary.totalActiveKcal.formatted(), unit: "kcal", systemImage: "flame.fill", tint: .orange)
                SummaryStatCard(title: "Total", value: summary.totalKcal.formatted(), unit: "kcal", systemImage: "bolt.fill", tint: .yellow)
                SummaryStatCard(title: "Avg Active", value: summary.dailyAverageActiveKcal.formatted(.number.precision(.fractionLength(0))), unit: "kcal/day", systemImage: "chart.line.uptrend.xyaxis", tint: AppConstants.Color.brandDark)
                SummaryStatCard(title: "Daily Goal", value: summary.goalActiveKcalPerDay.formatted(), unit: "kcal", systemImage: "target", tint: .green)
            }
        }
    }
}

private struct SummaryStatCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .padding(AppConstants.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

// MARK: - Daily Breakdown Section

private struct DailyBreakdownSection: View {
    let entries: [DailyCalorieEntry]
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            Text("Daily Breakdown")
                .font(.title2.bold())
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: entry.date) else { return entry.date }
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            HStack {
                Text(formattedDate)
                    .font(.subheadline.bold())
                Spacer()
                if goalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Goal met")
                }
                Text("\(entry.activeKcal) kcal")
                    .font(.subheadline.bold())
                    .foregroundStyle(goalMet ? .green : .primary)
            }

            ProgressView(value: progress)
                .tint(goalMet ? .green : .orange)
                .accessibilityLabel("\(entry.activeKcal) of \(goal) active calorie goal")

            HStack(spacing: AppConstants.Spacing.lg) {
                Label("\(entry.steps.formatted()) steps", systemImage: "figure.walk")
                Label("\(entry.exerciseMinutes) min", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.steps.formatted()) steps, \(entry.exerciseMinutes) minutes")
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }
}

// MARK: - Follow-up Chat Section

private struct FollowUpChatSection: View {
    @ObservedObject var vm: A2ACoachingViewModel
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            header

            if vm.chatMessages.isEmpty && !vm.isChatSending {
                emptyHint
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: AppConstants.Spacing.sm) {
                        ForEach(vm.chatMessages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                        if vm.isChatSending {
                            TypingIndicator()
                                .id("typing-indicator")
                        }
                    }
                    .onChange(of: vm.chatMessages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: vm.isChatSending) { _ in
                        scrollToBottom(proxy)
                    }
                }
            }

            if let err = vm.chatError {
                ChatErrorRow(message: err)
            }

            inputBar
        }
        .padding(AppConstants.Spacing.md)
        .background(AppConstants.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .font(.title3)
            Text("Ask the Coach")
                .font(.title2.bold())
            Spacer()
        }
    }

    private var emptyHint: some View {
        HStack(spacing: AppConstants.Spacing.sm) {
            Image(systemName: "sparkle")
                .foregroundStyle(.secondary)
            Text("Have a question about your report? Ask below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, AppConstants.Spacing.xs)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: AppConstants.Spacing.sm) {
            TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.vertical, 10)
                .background(AppConstants.Color.pageBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
                .focused($inputFocused)
                .disabled(vm.isChatSending)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(canSend ? 1.0 : 0.35)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send question")
        }
    }

    private var canSend: Bool {
        !vm.isChatSending &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    proxy.scrollTo("typing-indicator", anchor: .bottom)
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
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 4) {
                if message.role == .assistant {
                    Text("💪 Coach")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                MarkdownText(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .user ? AppConstants.Color.onBrand : .primary)
            }
            .padding(.horizontal, AppConstants.Spacing.md)
            .padding(.vertical, AppConstants.Spacing.sm)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (message.role == .user ? "You said: " : "Coach replied: ") + message.text
        )
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            LinearGradient(
                colors: [AppConstants.Color.brand, AppConstants.Color.brandDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            AppConstants.Color.pageBackground
        }
    }
}

private struct TypingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                            .opacity(tick == i ? 1.0 : 0.3)
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.md)
                .padding(.vertical, AppConstants.Spacing.sm)
                .background(AppConstants.Color.pageBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))

                Spacer(minLength: 40)
            }
        }
        .accessibilityLabel("Coach is typing")
    }
}

private struct ChatErrorRow: View {
    let message: String

    var body: some View {
        HStack(spacing: AppConstants.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(AppConstants.Spacing.sm)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md))
    }
}
