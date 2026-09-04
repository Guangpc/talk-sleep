import Foundation

public enum AIFriendRepositoryError: Error, Equatable, Sendable {
    case friendNotFound
}

public struct StoredAIFriend: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var reviewedProfile: String
    public var voiceReference: String
    public var createdAt: Date

    public init(
        id: UUID,
        name: String,
        reviewedProfile: String,
        voiceReference: String,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.reviewedProfile = reviewedProfile
        self.voiceReference = voiceReference
        self.createdAt = createdAt
    }
}

public protocol AIFriendRepository: Sendable {
    func loadAll() throws -> [StoredAIFriend]
    func save(_ friend: StoredAIFriend) throws
    func delete(id: UUID) throws
    func bindVoice(_ voiceReference: String, to friendID: UUID) throws -> StoredAIFriend
}

public final class FileAIFriendRepository: AIFriendRepository, @unchecked Sendable {
    private struct Envelope: Codable {
        let schemaVersion: Int
        var friends: [StoredAIFriend]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = fileURL
        self.fileManager = fileManager
        try ensureParentDirectory()
    }

    public func loadAll() throws -> [StoredAIFriend] {
        try lock.withLock { try readEnvelope().friends.sorted { $0.createdAt < $1.createdAt } }
    }

    public func save(_ friend: StoredAIFriend) throws {
        try lock.withLock {
            var envelope = try readEnvelope()
            if let index = envelope.friends.firstIndex(where: { $0.id == friend.id }) {
                envelope.friends[index] = friend
            } else {
                envelope.friends.append(friend)
            }
            try write(envelope)
        }
    }

    public func delete(id: UUID) throws {
        try lock.withLock {
            var envelope = try readEnvelope()
            envelope.friends.removeAll { $0.id == id }
            try write(envelope)
        }
    }

    public func bindVoice(_ voiceReference: String, to friendID: UUID) throws -> StoredAIFriend {
        try lock.withLock {
            var envelope = try readEnvelope()
            guard let index = envelope.friends.firstIndex(where: { $0.id == friendID }) else {
                throw AIFriendRepositoryError.friendNotFound
            }
            envelope.friends[index].voiceReference = voiceReference
            try write(envelope)
            return envelope.friends[index]
        }
    }

    private func ensureParentDirectory() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func readEnvelope() throws -> Envelope {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Envelope(schemaVersion: 1, friends: [])
        }
        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return envelope
    }

    private func write(_ envelope: Envelope) throws {
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

public final class InMemoryAIFriendRepository: AIFriendRepository, @unchecked Sendable {
    private var friends: [UUID: StoredAIFriend] = [:]
    private let lock = NSLock()

    public init() {}

    public func loadAll() throws -> [StoredAIFriend] {
        try lock.withLock { friends.values.sorted { $0.createdAt < $1.createdAt } }
    }

    public func save(_ friend: StoredAIFriend) throws {
        try lock.withLock { friends[friend.id] = friend }
    }

    public func delete(id: UUID) throws {
        try lock.withLock { friends.removeValue(forKey: id) }
    }

    public func bindVoice(_ voiceReference: String, to friendID: UUID) throws -> StoredAIFriend {
        try lock.withLock {
            guard var friend = friends[friendID] else { throw AIFriendRepositoryError.friendNotFound }
            friend.voiceReference = voiceReference
            friends[friendID] = friend
            return friend
        }
    }
}
