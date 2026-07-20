import AppKit
import Combine
import Foundation
import LittleBeaconCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: LocalSnapshot
    @Published private(set) var currentActivity = ClassifiedActivity(observation: .idle, category: .idle)
    @Published var warningMessage: String?
    @Published var connectionMessage = "本地模式"
    @Published var pairingCode: String?
    @Published var pairingCodeExpiresAt: Date?
    @Published var isBusy = false
    @Published var lastError: String?
    @Published var autoStartMessage = ""

    private let store = LocalStore()
    private let classifier = ActivityClassifier()
    private let evaluator = RuleEvaluator()
    private let activityMonitor = ActivityMonitor()
    private var violationMachine = ViolationMachine()
    private var monitorTimer: Timer?
    private var syncTimer: Timer?
    private var activeEventID: UUID?
    private var lastTick = Date()

    init() {
        snapshot = store.load()
        NotificationService.requestAuthorization()
        autoStartMessage = AutoStartManager.registerIfPossible()
        startServices()
    }

    var role: DeviceRole { snapshot.role }
    var rules: RuleSet { snapshot.rules }
    var events: [ViolationEvent] { snapshot.events.sorted { $0.startedAt > $1.startedAt } }
    var requests: [TemporaryRequest] { snapshot.requests.sorted { $0.createdAt > $1.createdAt } }
    var currentStatus: DeviceStatus {
        var status = snapshot.currentStatus
        if Date().timeIntervalSince(status.lastSeenAt) > 90 { status.isOnline = false }
        return status
    }
    var hasRemoteConfiguration: Bool {
        !snapshot.apiBaseURL.isEmpty && KeychainStore.read(role: snapshot.role) != nil
    }

    func configure(role: DeviceRole) {
        snapshot.role = role
        persist()
        startServices()
    }

    func resetConfiguration() {
        monitorTimer?.invalidate()
        syncTimer?.invalidate()
        KeychainStore.delete(role: snapshot.role)
        snapshot = LocalSnapshot()
        violationMachine = ViolationMachine()
        warningMessage = nil
        connectionMessage = "本地模式"
        pairingCode = nil
        persist()
    }

    func updateAPIBaseURL(_ value: String) {
        snapshot.apiBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func bootstrapParent(baseURL: String, setupKey: String) async {
        await performRemoteAction {
            let client = try APIClient(baseURL: baseURL)
            let response = try await client.bootstrap(setupKey: setupKey, deviceName: self.snapshot.deviceName)
            try KeychainStore.save(token: response.token, role: .parent)
            self.snapshot.apiBaseURL = baseURL
            self.snapshot.householdID = response.householdID
            self.persist()
            self.connectionMessage = "家长端已连接"
            await self.syncNow()
        }
    }

    func pairChild(baseURL: String, code: String) async {
        await performRemoteAction {
            let client = try APIClient(baseURL: baseURL)
            let response = try await client.pair(code: code, deviceName: self.snapshot.deviceName)
            try KeychainStore.save(token: response.token, role: .child)
            self.snapshot.apiBaseURL = baseURL
            self.snapshot.householdID = response.householdID
            self.snapshot.deviceID = response.deviceID
            self.persist()
            self.connectionMessage = "孩子端已配对"
            await self.syncNow()
        }
    }

    func generatePairingCode() async {
        await performRemoteAction {
            let client = try self.authenticatedClient()
            let response = try await client.createPairingCode()
            self.pairingCode = response.code
            self.pairingCodeExpiresAt = response.expiresAt
        }
    }

    func syncNow() async {
        guard hasRemoteConfiguration else {
            connectionMessage = "本地模式（尚未连接服务器）"
            return
        }
        do {
            let client = try authenticatedClient()
            switch snapshot.role {
            case .parent:
                let oldEventIDs = Set(snapshot.events.map(\.id))
                let oldRequestIDs = Set(snapshot.requests.map(\.id))
                let response = try await client.fetchParentSync()
                snapshot.rules = response.rules
                snapshot.events = response.events
                snapshot.requests = response.requests
                if let status = response.status { snapshot.currentStatus = status }
                for event in response.events where !oldEventIDs.contains(event.id) {
                    NotificationService.post(
                        title: "小灯塔发现违规活动",
                        body: "\(event.category.displayName) · \(event.appName)"
                    )
                }
                for request in response.requests
                    where request.status == .pending && !oldRequestIDs.contains(request.id) {
                    NotificationService.post(
                        title: "新的临时使用申请",
                        body: "申请 \(request.category.displayName) \(request.durationMinutes) 分钟"
                    )
                }
            case .child:
                let response = try await client.fetchChildSync()
                snapshot.rules = response.rules
                snapshot.temporaryGrants = response.grants
                snapshot.requests = response.requests
                try await client.updateStatus(snapshot.currentStatus)
                try await flushPendingEvents(client: client)
            case .unconfigured:
                break
            }
            snapshot.prune()
            persist()
            connectionMessage = "已同步 · \(Date().formatted(date: .omitted, time: .shortened))"
            lastError = nil
        } catch {
            connectionMessage = "离线，稍后重试"
            lastError = error.localizedDescription
        }
    }

    func addOrUpdateWindow(
        category: ActivityCategory,
        weekday: Int,
        enabled: Bool,
        startMinute: Int,
        endMinute: Int
    ) {
        guard let index = snapshot.rules.activityRules.firstIndex(where: { $0.category == category }) else {
            return
        }
        snapshot.rules.activityRules[index].windows.removeAll { $0.weekday == weekday }
        if enabled {
            snapshot.rules.activityRules[index].windows.append(
                ScheduleWindow(weekday: weekday, startMinute: startMinute, endMinute: endMinute)
            )
        }
        snapshot.rules.revision += 1
        persist()
        Task { await uploadRulesIfPossible() }
    }

    func addOverride(target: OverrideTarget, value: String, category: ActivityCategory) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        snapshot.rules.overrides.removeAll { $0.target == target && $0.value == normalized }
        snapshot.rules.overrides.append(
            ClassificationOverride(target: target, value: normalized, category: category)
        )
        snapshot.rules.revision += 1
        persist()
        Task { await uploadRulesIfPossible() }
    }

    func removeOverride(id: UUID) {
        snapshot.rules.overrides.removeAll { $0.id == id }
        snapshot.rules.revision += 1
        persist()
        Task { await uploadRulesIfPossible() }
    }

    func requestTemporaryUse(category: ActivityCategory, durationMinutes: Int) {
        guard [15, 30, 60].contains(durationMinutes) else { return }
        let request = TemporaryRequest(category: category, durationMinutes: durationMinutes)
        snapshot.requests.append(request)
        persist()
        Task {
            guard hasRemoteConfiguration else { return }
            do {
                try await authenticatedClient().createRequest(request)
                await syncNow()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func resolveRequest(_ request: TemporaryRequest, approved: Bool) {
        guard let index = snapshot.requests.firstIndex(where: { $0.id == request.id }) else { return }
        snapshot.requests[index].status = approved ? .approved : .denied
        snapshot.requests[index].resolvedAt = Date()
        if approved && !hasRemoteConfiguration {
            snapshot.temporaryGrants.append(
                TemporaryGrant(
                    category: request.category,
                    startsAt: Date(),
                    endsAt: Date().addingTimeInterval(TimeInterval(request.durationMinutes * 60))
                )
            )
        }
        persist()
        Task {
            guard hasRemoteConfiguration else { return }
            do {
                if let grant = try await authenticatedClient().resolveRequest(id: request.id, approved: approved) {
                    snapshot.temporaryGrants.append(grant)
                }
                await syncNow()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func addDemoEvent() {
        let now = Date()
        snapshot.events.append(
            ViolationEvent(
                category: .video,
                appName: "Safari",
                normalizedDomain: "youtube.com",
                startedAt: now.addingTimeInterval(-180),
                durationSeconds: 180,
                warningCount: 3,
                wasEnforced: true
            )
        )
        persist()
    }

    private func startServices() {
        monitorTimer?.invalidate()
        syncTimer?.invalidate()
        guard snapshot.role != .unconfigured else { return }

        if snapshot.role == .child && snapshot.monitoringEnabled {
            lastTick = Date()
            monitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.monitorTick() }
            }
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        Task { await syncNow() }
    }

    private func monitorTick() {
        let now = Date()
        let delta = min(5, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        let observation = activityMonitor.observeFrontmostActivity()
        let activity = classifier.classify(observation, overrides: snapshot.rules.overrides)
        currentActivity = activity
        snapshot.currentStatus = DeviceStatus(category: activity.category, lastSeenAt: now, isOnline: true)
        let allowed = evaluator.isAllowed(
            category: activity.category,
            at: now,
            rules: snapshot.rules,
            temporaryGrants: snapshot.temporaryGrants
        )
        let actions = violationMachine.advance(
            activity: activity,
            isAllowed: allowed,
            elapsedSeconds: delta,
            at: now
        )
        process(actions: actions, now: now)
        updateActiveEvent()
        snapshot.prune(now: now)
        persist()
    }

    private func process(actions: [ViolationAction], now: Date) {
        for action in actions {
            switch action {
            case let .warning(level, activity):
                let message: String
                switch level {
                case 1: message = "现在不是\(activity.category.displayName)时间，请在 60 秒内离开。"
                case 2: message = "第二次提醒：请停止\(activity.category.displayName)，家长端将收到通知。"
                default: message = "最后提醒：60 秒后将结束当前\(activity.category.displayName)活动。"
                }
                warningMessage = message
                NotificationService.post(title: "小灯塔提醒", body: message, identifier: "warning-\(level)")
            case let .beginEvent(activity, startedAt):
                let event = ViolationEvent(
                    category: activity.category,
                    appName: activity.observation.appName,
                    normalizedDomain: activity.observation.normalizedDomain,
                    startedAt: startedAt
                )
                activeEventID = event.id
                snapshot.events.append(event)
                snapshot.pendingEventIDs.insert(event.id)
            case let .enforce(activity):
                let succeeded = activityMonitor.enforce(activity)
                warningMessage = succeeded ? "已结束当前违规活动。" : "无法自动结束活动，请联系家长检查权限。"
                if let id = activeEventID,
                   let index = snapshot.events.firstIndex(where: { $0.id == id }) {
                    snapshot.events[index].wasEnforced = succeeded
                    snapshot.events[index].warningCount = 3
                    snapshot.pendingEventIDs.insert(id)
                }
            case .reset:
                warningMessage = nil
                activeEventID = nil
            }
        }
    }

    private func updateActiveEvent() {
        guard let id = activeEventID,
              let state = violationMachine.state,
              let index = snapshot.events.firstIndex(where: { $0.id == id }) else { return }
        snapshot.events[index].durationSeconds = Int(state.activeSeconds.rounded(.down))
        snapshot.events[index].warningCount = state.warningCount
        snapshot.events[index].category = state.latestActivity.category
        snapshot.events[index].appName = state.latestActivity.observation.appName
        snapshot.events[index].normalizedDomain = state.latestActivity.observation.normalizedDomain
        snapshot.pendingEventIDs.insert(id)
    }

    private func uploadRulesIfPossible() async {
        guard snapshot.role == .parent, hasRemoteConfiguration else { return }
        do {
            try await authenticatedClient().updateRules(snapshot.rules)
            connectionMessage = "规则已同步"
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func flushPendingEvents(client: APIClient) async throws {
        for id in Array(snapshot.pendingEventIDs) {
            guard let event = snapshot.events.first(where: { $0.id == id }) else { continue }
            try await client.uploadEvent(event)
            snapshot.pendingEventIDs.remove(id)
        }
    }

    private func authenticatedClient() throws -> APIClient {
        let token = KeychainStore.read(role: snapshot.role)
        return try APIClient(baseURL: snapshot.apiBaseURL, token: token)
    }

    private func performRemoteAction(_ action: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist() {
        store.save(snapshot)
    }
}
