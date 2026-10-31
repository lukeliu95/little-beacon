import SwiftUI
import LittleBeaconCore

/// The parent's two buttons, with the confirmation and what came of the last press. It lives
/// inline, not in a sheet, because the menu bar panel closes when a sheet takes the focus.
struct RemoteControlBand: View {
    @ObservedObject var model: AppModel
    @State private var confirming: RemoteTarget?
    @State private var lock: RemoteLockOption = .thirtyMinutes

    /// How long the result of a close stays beside the buttons; the records page keeps it for good.
    private static let resultShownSeconds: TimeInterval = 10 * 60

    var body: some View {
        let now = Date()
        let isOnline = model.currentStatus.isOnline
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(RemoteTarget.allCases) { target in
                    let isBusy = latestClose(of: target)?.isInFlight(at: now) == true
                    Button("关闭\(target.displayName)") {
                        confirming = confirming == target ? nil : target
                    }
                    .buttonStyle(BeaconButtonStyle(kind: confirming == target ? .selected : .quiet))
                    .disabled(!isOnline || isBusy || model.isBusy)
                }
            }
            if !isOnline {
                Text("孩子的 Mac 离线，现在关不了")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let confirming, isOnline {
                confirmation(for: confirming)
            }
            ForEach(RemoteTarget.allCases) { target in
                lockLine(for: target, now: now)
                resultLine(for: target, now: now)
            }
        }
    }

    private func latestClose(of target: RemoteTarget) -> RemoteCommand? {
        model.remoteCommands.first { $0.kind == .close && $0.target == target }
    }

    private func confirmation(for target: RemoteTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("孩子会先看到提醒，1 分钟后关闭\(target.displayName)。没保存的内容可能会丢。")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("之后锁定").font(.system(size: 13)).foregroundStyle(.secondary)
                Picker("之后锁定", selection: $lock) {
                    ForEach(RemoteLockOption.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Spacer()
                Button("取消") { confirming = nil }
                    .buttonStyle(BeaconButtonStyle())
                Button("确认关闭") {
                    confirming = nil
                    let chosen = lock
                    Task { await model.sendRemoteClose(target, lock: chosen) }
                }
                .buttonStyle(BeaconButtonStyle(kind: .primary))
            }
        }
        .padding(12)
        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func lockLine(for target: RemoteTarget, now: Date) -> some View {
        if let endsAt = remoteLockEnd(for: target, in: model.remoteCommands, at: now) {
            HStack(spacing: 8) {
                Text("\(target.displayName)锁\(remoteLockEndText(endsAt, timeZoneIdentifier: model.rules.timeZoneIdentifier))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("解除") {
                    Task { await model.sendRemoteUnlock(target) }
                }
                .buttonStyle(BeaconButtonStyle())
                .disabled(model.isBusy)
            }
        }
    }

    @ViewBuilder
    private func resultLine(for target: RemoteTarget, now: Date) -> some View {
        if let command = latestClose(of: target),
           command.isInFlight(at: now)
            || now.timeIntervalSince(command.finishedAt ?? command.createdAt) < Self.resultShownSeconds {
            HStack(spacing: 8) {
                Text("\(target.displayName)：\(command.parentOutcome(at: now))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let app = command.unrecognizedApp {
                    Button("设为游戏并关闭") {
                        Task { await model.closeAsGame(app, lock: command.lock) }
                    }
                    .buttonStyle(BeaconButtonStyle())
                    .disabled(model.isBusy)
                }
            }
        }
    }
}

/// What parents asked of the child Mac, newest first.
struct RemoteRecordList: View {
    let commands: [RemoteCommand]

    var body: some View {
        let now = Date()
        VStack(spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                HStack(spacing: 16) {
                    Text(eventTimeText(command.createdAt))
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .leading)
                    Text(command.parentTitle)
                    Spacer(minLength: 16)
                    Text(command.parentOutcome(at: now))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 14).monospacedDigit())
                .padding(.vertical, 10)
                if index < commands.count - 1 {
                    Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
                }
            }
        }
    }
}
