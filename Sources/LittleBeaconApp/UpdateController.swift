import Combine
import Foundation
import Sparkle

@MainActor
private final class UpdateLifecycleBridge: NSObject, SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        ApplicationTerminationGate.shared.postponeUpdateUntilBreakCompletes(installHandler)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        ApplicationTerminationGate.shared.allowUpdateRelaunch()
    }
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    let updaterController: SPUStandardUpdaterController
    private let lifecycleBridge: UpdateLifecycleBridge
    private var observation: AnyCancellable?

    init() {
        let lifecycleBridge = UpdateLifecycleBridge()
        self.lifecycleBridge = lifecycleBridge
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: lifecycleBridge,
            userDriverDelegate: nil
        )
        observation = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version)（\(build)）"
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
