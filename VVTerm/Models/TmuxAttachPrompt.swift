import Foundation

enum TmuxSocketScope: String, Codable, CaseIterable, Equatable, Hashable {
    case userDefault
    case managed
}

struct TmuxAttachSessionInfo: Identifiable, Equatable {
    let name: String
    let scope: TmuxSocketScope
    let attachedClients: Int
    let windowCount: Int

    var id: String { "\(scope.rawValue):\(name)" }
}

struct TmuxAttachPrompt: Identifiable, Equatable {
    /// Session ID (ConnectionSession.id or Terminal paneId) that is waiting for selection.
    let id: UUID
    let serverId: UUID
    let serverName: String
    let existingSessions: [TmuxAttachSessionInfo]
}

enum TmuxAttachSelection: Equatable {
    case createManaged
    case attachExisting(sessionName: String, scope: TmuxSocketScope)
    case skipTmux
}
