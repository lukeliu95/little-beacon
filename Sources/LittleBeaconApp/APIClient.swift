import Foundation
import LittleBeaconCore

struct BootstrapResponse: Codable {
    let householdID: String
    let token: String
}

struct PairingCodeResponse: Codable {
    let code: String
    let expiresAt: Date
}

struct PairResponse: Codable {
    let householdID: String
    let deviceID: String
    let token: String
}

/// Commands decode one by one: a server that predates them, or a command kind this version does
/// not know yet, must never take the rest of the sync, or the commands beside it, down too.
private struct DecodedCommand: Decodable {
    let command: RemoteCommand?

    init(from decoder: Decoder) {
        command = try? RemoteCommand(from: decoder)
    }
}

private func decodedCommands<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) -> [RemoteCommand] {
    ((try? container.decodeIfPresent([DecodedCommand].self, forKey: key)) ?? []).compactMap(\.command)
}

struct ParentSyncResponse: Decodable {
    let status: DeviceStatus?
    let events: [ViolationEvent]
    let requests: [TemporaryRequest]
    let rules: RuleSet
    let commands: [RemoteCommand]

    private enum CodingKeys: String, CodingKey {
        case status, events, requests, rules, commands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(DeviceStatus.self, forKey: .status)
        events = try container.decode([ViolationEvent].self, forKey: .events)
        requests = try container.decode([TemporaryRequest].self, forKey: .requests)
        rules = try container.decode(RuleSet.self, forKey: .rules)
        commands = decodedCommands(from: container, forKey: .commands)
    }
}

struct ChildSyncResponse: Decodable {
    let rules: RuleSet
    let grants: [TemporaryGrant]
    let requests: [TemporaryRequest]
    let commands: [RemoteCommand]

    private enum CodingKeys: String, CodingKey {
        case rules, grants, requests, commands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode(RuleSet.self, forKey: .rules)
        grants = try container.decode([TemporaryGrant].self, forKey: .grants)
        requests = try container.decode([TemporaryRequest].self, forKey: .requests)
        commands = decodedCommands(from: container, forKey: .commands)
    }
}

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "服务器地址无效"
        case .invalidResponse: "服务器返回了无法识别的数据"
        case let .server(status, message): "服务器错误 \(status)：\(message)"
        }
    }
}

struct APIClient {
    let baseURL: URL
    let token: String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: String, token: String? = nil) throws {
        guard let url = URL(string: baseURL), let scheme = url.scheme,
              scheme == "https" || scheme == "http" else {
            throw APIError.invalidBaseURL
        }
        self.baseURL = url
        self.token = token
        encoder = APIJSONCoding.makeEncoder()
        decoder = APIJSONCoding.makeDecoder()
    }

    func bootstrap(setupKey: String, deviceName: String) async throws -> BootstrapResponse {
        try await send(
            path: "api/bootstrap",
            method: "POST",
            body: ["setupKey": setupKey, "deviceName": deviceName],
            authenticated: false
        )
    }

    func createPairingCode() async throws -> PairingCodeResponse {
        try await send(path: "api/pairing-codes", method: "POST", body: EmptyBody())
    }

    func pair(code: String, deviceName: String) async throws -> PairResponse {
        try await send(
            path: "api/pair",
            method: "POST",
            body: ["code": code, "deviceName": deviceName],
            authenticated: false
        )
    }

    func fetchParentSync() async throws -> ParentSyncResponse {
        try await send(path: "api/sync/parent", method: "GET", body: Optional<EmptyBody>.none)
    }

    func fetchChildSync() async throws -> ChildSyncResponse {
        try await send(path: "api/sync/child", method: "GET", body: Optional<EmptyBody>.none)
    }

    func updateRules(_ rules: RuleSet) async throws {
        let _: AckResponse = try await send(path: "api/rules", method: "PUT", body: rules)
    }

    func updateStatus(_ status: DeviceStatus) async throws {
        let _: AckResponse = try await send(path: "api/status", method: "PUT", body: status)
    }

    func uploadEvent(_ event: ViolationEvent) async throws {
        let _: AckResponse = try await send(path: "api/events", method: "POST", body: event)
    }

    func createRequest(_ request: TemporaryRequest) async throws {
        let _: AckResponse = try await send(path: "api/requests", method: "POST", body: request)
    }

    func resolveRequest(id: UUID, approved: Bool) async throws -> TemporaryGrant? {
        struct ResolveBody: Encodable { let approved: Bool }
        struct ResolveResponse: Decodable { let grant: TemporaryGrant? }
        let response: ResolveResponse = try await send(
            path: "api/requests/\(id.uuidString)",
            method: "PATCH",
            body: ResolveBody(approved: approved)
        )
        return response.grant
    }

    func createRemoteCommand(
        kind: RemoteCommandKind,
        target: RemoteTarget,
        lock: RemoteLockOption
    ) async throws -> RemoteCommand {
        struct CommandBody: Encodable {
            let kind: RemoteCommandKind
            let target: RemoteTarget
            let lock: RemoteLockOption
        }
        struct CommandResponse: Decodable { let command: RemoteCommand }
        let response: CommandResponse = try await send(
            path: "api/commands",
            method: "POST",
            body: CommandBody(kind: kind, target: target, lock: lock)
        )
        return response.command
    }

    func reportRemoteCommand(_ report: RemoteCommandReport) async throws {
        let _: AckResponse = try await send(path: "api/commands", method: "PATCH", body: report)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        authenticated: Bool = true
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token else { throw APIError.server(status: 401, message: "缺少设备凭据") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ServerErrorResponse.self, from: data).error)
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            throw APIError.server(status: http.statusCode, message: message)
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw APIError.invalidResponse
        }
        return decoded
    }
}

private struct EmptyBody: Codable {}
private struct AckResponse: Codable { let ok: Bool }
private struct ServerErrorResponse: Codable { let error: String }
