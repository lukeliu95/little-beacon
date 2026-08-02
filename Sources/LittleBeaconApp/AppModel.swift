import AppKit
import Combine
import Foundation
import LittleBeaconCore

/// A dismissible, on-screen alert shown to the child — for rule warnings/enforcement, the
/// 25-minute break reminder, and the soft daily-usage nudge. Distinct from `warningMessage`,
/// which stays as a small inline banner that other code (the menu bar) already reads.
struct ChildAlert: Identifiable, Equatable {
    enum Tone: Equatable {
        /// Rule violation warnings and enforcement — the child is doing something not allowed.
        case warning
        /// Break reminders and usage nudges — informational, not scary.
        case gentle
    }

    let id = UUID()
    let title: String
    let message: String
    let tone: Tone
}

/// "7月22日 16:00" — when a scheduled temporary window begins. Shared by the child
/// request form/list, the parent request list, and the new-request notification.
func temporaryStartText(_ startsAt: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: startsAt)
}

/// "7月22日 16:00–16:30" — the full requested window (start + duration).
func temporaryWindowText(startsAt: Date, durationMinutes: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    let endsAt = startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    return "\(temporaryStartText(startsAt))–\(formatter.string(from: endsAt))"
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: LocalSnapshot
    @Published private(set) var currentActivity = ClassifiedActivity(observation: .idle, category: .idle)
    @Published var warningMessage: String?
    @Published var activeAlert: ChildAlert?
    @Published var connectionMessage = "本地模式"
    @Published var pairingCode: String?
    @Published var pairingCodeExpiresAt: Date?
    @Published var isBusy = false
    @Published var lastError: String?
    @Published var autoStartMessage = ""
    @Published private(set) var viewingDistanceStatusMessage = "坐姿距离提醒未开启"
    @Published private(set) var isViewingDistanceBusy = false
    @Published private(set) var pomodoroBreakPhase: PomodoroBreakPhase = .counting(activeSeconds: 0, idleSeconds: 0)

    private let store = LocalStore()
    private let classifier = ActivityClassifier()
    private let evaluator = RuleEvaluator()
    private let activityMonitor = ActivityMonitor()
    private let viewingDistanceMonitor = ViewingDistanceMonitor()
    private var violationMachine = ViolationMachine()
    private var pomodoroTimer = PomodoroTimer()
    private var pomodoroBreakCoordinator: PomodoroBreakCoordinator?
    private var pomodoroModeAtLastTick: PomodoroMode = .gentle
    private var monitorTimer: Timer?
    private var syncTimer: Timer?
    private var activeEventID: UUID?
    private var lastTick = Date()
    private var nextViewingDistanceCheckAt = Date.distantPast
    private var viewingDistanceWarningStage = 0

    init() {
        snapshot = store.load()
        pomodoroModeAtLastTick = snapshot.rules.pomodoroMode
        configurePomodoroCoordinator()
        NotificationService.requestAuthorization()
        autoStartMessage = AutoStartManager.registerIfPossible()
        refreshViewingDistanceStatus()
        startServices()
    }

    var role: DeviceRole { snapshot.role }
    var rules: RuleSet { snapshot.rules }
    var hasViewingDistanceCalibration: Bool { snapshot.viewingDistanceCalibration != nil }
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
        configurePomodoroCoordinator()
        startServices()
    }

    func resetConfiguration() {
        guard pomodoroBreakCoordinator?.isActiveBreak != true else {
            lastError = "强制休息进行中，完成休息并关闭提示后才能重新设置这台 Mac。"
            return
        }
        monitorTimer?.invalidate()
        syncTimer?.invalidate()
        KeychainStore.delete(role: snapshot.role)
        snapshot = LocalSnapshot()
        violationMachine = ViolationMachine()
        pomodoroTimer = PomodoroTimer()
        try? pomodoroBreakCoordinator?.resetCounting()
        ApplicationTerminationGate.shared.blocksTermination = false
        nextViewingDistanceCheckAt = .distantPast
        viewingDistanceWarningStage = 0
        warningMessage = nil
        activeAlert = nil
        connectionMessage = "本地模式"
        pairingCode = nil
        refreshViewingDistanceStatus()
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
                snapshot.rules = snapshot.rules.acceptingRemote(response.rules)
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
                    var body = "申请 \(request.category.displayName) \(request.durationMinutes) 分钟"
                    if let startsAt = request.startsAt {
                        body += " · \(temporaryWindowText(startsAt: startsAt, durationMinutes: request.durationMinutes))"
                    }
                    NotificationService.post(title: "新的临时使用申请", body: body)
                }
            case .child:
                let response = try await client.fetchChildSync()
                snapshot.rules = snapshot.rules.acceptingRemote(response.rules)
                snapshot.temporaryGrants = response.grants
                snapshot.requests = response.requests
                snapshot.lastRulesSyncAt = Date()
                refreshViewingDistanceStatus()
                snapshot.prune()
                persist()
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
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
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
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func removeOverride(id: UUID) {
        snapshot.rules.overrides.removeAll { $0.id == id }
        snapshot.rules.revision += 1
        persist()
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func setPomodoroMode(_ mode: PomodoroMode) {
        snapshot.rules.pomodoroMode = mode
        snapshot.rules.revision += 1
        persist()
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func setDailyUsageThresholdSeconds(_ seconds: Int?) {
        snapshot.rules.dailyUsageThresholdSeconds = seconds
        snapshot.rules.revision += 1
        persist()
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func setViewingDistanceEnabled(_ enabled: Bool) {
        snapshot.rules.viewingDistancePolicy.enabled = enabled
        snapshot.rules.revision += 1
        refreshViewingDistanceStatus()
        persist()
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func setViewingDistanceCheckIntervalMinutes(_ minutes: Int) {
        snapshot.rules.viewingDistancePolicy.checkIntervalMinutes = min(60, max(5, minutes))
        snapshot.rules.revision += 1
        persist()
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func setViewingDistanceMinimumCentimeters(_ centimeters: Int) {
        snapshot.rules.viewingDistancePolicy.minimumDistanceCentimeters = min(80, max(30, centimeters))
        snapshot.rules.revision += 1
        persist()
        let rulesToUpload = snapshot.rules
        Task { await uploadRulesIfPossible(rulesToUpload) }
    }

    func calibrateViewingDistance() async {
        guard role == .child, snapshot.rules.viewingDistancePolicy.enabled else { return }
        guard !isViewingDistanceBusy else { return }
        isViewingDistanceBusy = true
        viewingDistanceStatusMessage = "正在申请摄像头权限…"
        defer { isViewingDistanceBusy = false }

        let permission = await ViewingDistanceMonitor.requestPermission()
        guard permission == .authorized else {
            refreshViewingDistanceStatus()
            return
        }

        viewingDistanceStatusMessage = "正在校准，请坐在设定距离并正对屏幕…"
        do {
            let policy = snapshot.rules.viewingDistancePolicy
            snapshot.viewingDistanceCalibration = try await viewingDistanceMonitor.calibrate(
                referenceDistanceCentimeters: policy.minimumDistanceCentimeters
            )
            viewingDistanceWarningStage = 0
            nextViewingDistanceCheckAt = Date().addingTimeInterval(
                TimeInterval(policy.checkIntervalMinutes * 60)
            )
            persist()
            viewingDistanceStatusMessage = "校准完成；之后只会短暂检查，不保存画面。"
            lastError = nil
        } catch {
            viewingDistanceStatusMessage = "校准没有完成"
            lastError = error.localizedDescription
        }
    }

    func requestTemporaryUse(category: ActivityCategory, durationMinutes: Int, startsAt: Date? = nil) {
        guard [15, 30, 60].contains(durationMinutes) else { return }
        // A scheduled time that has already passed degrades to an immediate request.
        let effectiveStartsAt = startsAt.flatMap { $0 > Date() ? $0 : nil }
        let request = TemporaryRequest(
            category: category,
            durationMinutes: durationMinutes,
            startsAt: effectiveStartsAt
        )
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
            // A scheduled request grants its requested window; an immediate one starts now.
            let grantStart = request.startsAt ?? Date()
            snapshot.temporaryGrants.append(
                TemporaryGrant(
                    category: request.category,
                    startsAt: grantStart,
                    endsAt: grantStart.addingTimeInterval(TimeInterval(request.durationMinutes * 60))
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
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.monitorTick() }
            }
            monitorTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        syncTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        Task { await syncNow() }
    }

    private func monitorTick() {
        let now = Date()
        let delta = min(5, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        let observation = activityMonitor.observeFrontmostActivity()
        let activity = classifier.classify(observation, overrides: snapshot.rules.overrides)
        currentActivity = activity
        let isIdle = activity.category == .idle
        let breakWasActive = pomodoroBreakCoordinator?.isActiveBreak == true
        advancePomodoro(isIdle: isIdle, elapsedSeconds: delta, at: now)
        let breakIsActive = pomodoroBreakCoordinator?.isActiveBreak == true
        if !breakWasActive && breakIsActive {
            warningMessage = nil
            activeAlert = nil
            activeEventID = nil
            violationMachine = ViolationMachine()
        }
        let isEffectivelyIdle = isIdle || breakIsActive

        let previousDayKey = snapshot.dailyUsage.dayKey
        snapshot.dailyUsage.advance(isIdle: isEffectivelyIdle, elapsedSeconds: delta, at: now)
        if snapshot.dailyUsage.dayKey != previousDayKey {
            snapshot.dailyUsageNudgeShown = false
        }

        snapshot.currentStatus = DeviceStatus(
            category: breakIsActive ? .idle : activity.category,
            lastSeenAt: now,
            isOnline: true,
            dailyUsageSeconds: snapshot.dailyUsage.activeSeconds
        )

        if !breakIsActive {
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
        }

        if !snapshot.dailyUsageNudgeShown,
           let threshold = snapshot.rules.dailyUsageThresholdSeconds,
           snapshot.dailyUsage.activeSeconds >= threshold,
           !breakIsActive {
            snapshot.dailyUsageNudgeShown = true
            presentAlert(
                title: "今日用机提醒",
                message: "今天已经用了很久电脑了，家长已经看到了。",
                tone: .gentle
            )
        }

        maybeCheckViewingDistance(isIdle: isEffectivelyIdle, now: now)
        updateActiveEvent()
        snapshot.prune(now: now)
        persist()
    }

    private func advancePomodoro(isIdle: Bool, elapsedSeconds: TimeInterval, at date: Date) {
        guard let coordinator = pomodoroBreakCoordinator else { return }

        do {
            if coordinator.isActiveBreak {
                try coordinator.advance(isIdle: true, elapsedSeconds: elapsedSeconds, at: date)
                return
            }

            let mode = snapshot.rules.pomodoroMode
            if mode != pomodoroModeAtLastTick {
                pomodoroTimer = PomodoroTimer()
                try coordinator.resetCounting()
                pomodoroModeAtLastTick = mode
            }

            switch mode {
            case .off:
                break
            case .gentle:
                if pomodoroTimer.advance(isIdle: isIdle, elapsedSeconds: elapsedSeconds) == .breakSuggested {
                    presentAlert(
                        title: "休息一下",
                        message: "已经连续用了 25 分钟，起来看看远处，休息一下眼睛吧。",
                        tone: .gentle
                    )
                }
            case .enforced:
                try coordinator.advance(isIdle: isIdle, elapsedSeconds: elapsedSeconds, at: date)
            }
        } catch {
            lastError = "番茄钟状态没有保存成功：\(error.localizedDescription)"
        }
    }

    private func configurePomodoroCoordinator() {
        let sessionStore = PomodoroSessionStore()
        let initialMachine: PomodoroBreakMachine? = snapshot.role == .child ? nil : PomodoroBreakMachine()
        let shield = BreakShieldWindowController()
        let alarm = BreakAlarmController()

        do {
            pomodoroBreakCoordinator = try PomodoroBreakCoordinator(
                store: sessionStore,
                shield: shield,
                alarm: alarm,
                initialMachine: initialMachine
            )
        } catch {
            lastError = "番茄钟记录损坏，已从安全的空白状态恢复：\(error.localizedDescription)"
            pomodoroBreakCoordinator = try? PomodoroBreakCoordinator(
                store: sessionStore,
                shield: shield,
                alarm: alarm,
                initialMachine: PomodoroBreakMachine()
            )
        }

        guard let coordinator = pomodoroBreakCoordinator else {
            ApplicationTerminationGate.shared.blocksTermination = false
            return
        }
        pomodoroBreakPhase = coordinator.phase
        ApplicationTerminationGate.shared.blocksTermination = snapshot.role == .child && coordinator.isActiveBreak
        coordinator.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            self.pomodoroBreakPhase = phase
            ApplicationTerminationGate.shared.blocksTermination = self.snapshot.role == .child && phase.isActiveBreak
        }
        coordinator.onError = { [weak self] error in
            self?.lastError = "番茄钟状态没有保存成功：\(error.localizedDescription)"
        }
    }

    private func presentAlert(
        title: String,
        message: String,
        tone: ChildAlert.Tone,
        useDistanceAlarm: Bool = false
    ) {
        activeAlert = ChildAlert(title: title, message: message, tone: tone)
        if useDistanceAlarm {
            SoundService.playDistanceAlarm()
        } else {
            SoundService.playAlert()
        }
    }

    private func maybeCheckViewingDistance(isIdle: Bool, now: Date) {
        let policy = snapshot.rules.viewingDistancePolicy
        guard role == .child,
              policy.enabled,
              pomodoroBreakCoordinator?.isActiveBreak != true,
              !isIdle,
              !isViewingDistanceBusy,
              (activeAlert == nil || viewingDistanceWarningStage > 0),
              now >= nextViewingDistanceCheckAt else {
            return
        }
        guard ViewingDistanceMonitor.permissionState == .authorized else {
            refreshViewingDistanceStatus()
            nextViewingDistanceCheckAt = now.addingTimeInterval(5 * 60)
            return
        }
        guard let calibration = snapshot.viewingDistanceCalibration else {
            viewingDistanceStatusMessage = "等待在孩子端完成一次安全距离校准"
            nextViewingDistanceCheckAt = now.addingTimeInterval(5 * 60)
            return
        }

        isViewingDistanceBusy = true
        viewingDistanceStatusMessage = "正在短暂检查坐姿距离…"
        nextViewingDistanceCheckAt = now.addingTimeInterval(
            TimeInterval(policy.checkIntervalMinutes * 60)
        )
        let wasTooClose = viewingDistanceWarningStage > 0

        Task {
            defer { isViewingDistanceBusy = false }
            do {
                let assessment = try await viewingDistanceMonitor.check(
                    calibration: calibration,
                    policy: policy,
                    wasTooClose: wasTooClose
                )
                guard snapshot.rules.viewingDistancePolicy.enabled else {
                    refreshViewingDistanceStatus()
                    return
                }
                handleViewingDistanceAssessment(assessment, policy: policy)
                lastError = nil
            } catch let error as ViewingDistanceMonitorError {
                viewingDistanceStatusMessage = error.localizedDescription
                if case .cameraChanged = error {
                    snapshot.viewingDistanceCalibration = nil
                    persist()
                }
            } catch {
                viewingDistanceStatusMessage = "这次距离检查没有完成，稍后会再试。"
            }
        }
    }

    private func handleViewingDistanceAssessment(
        _ assessment: ViewingDistanceAssessment,
        policy: ViewingDistancePolicy
    ) {
        switch assessment {
        case let .safe(estimatedCentimeters):
            viewingDistanceWarningStage = 0
            viewingDistanceStatusMessage = "最近检查：距离合适（约 \(estimatedCentimeters) 厘米）"
            nextViewingDistanceCheckAt = Date().addingTimeInterval(
                TimeInterval(policy.checkIntervalMinutes * 60)
            )
        case let .tooClose(estimatedCentimeters):
            if viewingDistanceWarningStage == 0 {
                viewingDistanceWarningStage = 1
                viewingDistanceStatusMessage = "检测到距离过近"
                nextViewingDistanceCheckAt = Date().addingTimeInterval(10)
                presentAlert(
                    title: "往后坐一点吧",
                    message: "你离屏幕有点近了（大约 \(estimatedCentimeters) 厘米），眼睛也想喘口气。",
                    tone: .gentle
                )
            } else {
                viewingDistanceWarningStage = 2
                viewingDistanceStatusMessage = "距离仍然过近，已发出提醒"
                nextViewingDistanceCheckAt = Date().addingTimeInterval(2 * 60)
                presentAlert(
                    title: "距离屏幕太近了",
                    message: "请先往后坐到至少 \(policy.minimumDistanceCentimeters) 厘米，再继续使用电脑。",
                    tone: .warning,
                    useDistanceAlarm: true
                )
            }
        case .inconclusive:
            viewingDistanceStatusMessage = "这次没有稳定识别人脸，未作判断。"
            nextViewingDistanceCheckAt = Date().addingTimeInterval(2 * 60)
        }
    }

    private func refreshViewingDistanceStatus() {
        guard snapshot.rules.viewingDistancePolicy.enabled else {
            viewingDistanceStatusMessage = "坐姿距离提醒未开启"
            viewingDistanceWarningStage = 0
            return
        }
        switch ViewingDistanceMonitor.permissionState {
        case .notDetermined:
            viewingDistanceStatusMessage = "等待孩子端授权摄像头并完成校准"
        case .denied, .restricted:
            viewingDistanceStatusMessage = "摄像头权限未开启，无法检查距离"
        case .authorized:
            viewingDistanceStatusMessage = snapshot.viewingDistanceCalibration == nil
                ? "摄像头已授权，等待安全距离校准"
                : "坐姿距离提醒已准备好"
        }
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
                presentAlert(title: "小灯塔提醒", message: message, tone: .warning)
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
                let message = succeeded ? "已结束当前违规活动。" : "无法自动结束活动，请联系家长检查权限。"
                warningMessage = message
                presentAlert(title: succeeded ? "已结束当前活动" : "需要家长帮助", message: message, tone: .warning)
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

    private func uploadRulesIfPossible(_ rules: RuleSet) async {
        guard snapshot.role == .parent, hasRemoteConfiguration else { return }
        do {
            try await authenticatedClient().updateRules(rules)
            if snapshot.rules.revision == rules.revision {
                connectionMessage = "规则版本 \(rules.revision) 已同步"
            }
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
