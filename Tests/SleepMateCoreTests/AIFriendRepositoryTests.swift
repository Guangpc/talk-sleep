import Foundation
import XCTest
@testable import SleepMateCore

final class AIFriendRepositoryTests: XCTestCase {
    func testSaveAndReloadPreservesReviewedProfileAndVoiceReference() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let friendID = UUID()
        let friend = StoredAIFriend(
            id: friendID,
            name: "小林",
            reviewedProfile: "性格：温和\n地址：杭州\n工作环境：医院\n工作内容：护理",
            voiceReference: "voice://xiaolin",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let firstLaunch = try FileAIFriendRepository(fileURL: fileURL)
        try firstLaunch.save(friend)
        let nextLaunch = try FileAIFriendRepository(fileURL: fileURL)

        XCTAssertEqual(try nextLaunch.loadAll(), [friend])
    }
    func testSaveUpdatesOneFriendWithoutDuplicatingIt() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let id = UUID()
        let repository = try FileAIFriendRepository(fileURL: fileURL)
        try repository.save(StoredAIFriend(id: id, name: "小林", reviewedProfile: "性格：温和", voiceReference: "voice://stock", createdAt: Date(timeIntervalSince1970: 100)))
        try repository.save(StoredAIFriend(id: id, name: "小林", reviewedProfile: "性格：温和", voiceReference: "voice://clone", createdAt: Date(timeIntervalSince1970: 100)))

        let friends = try repository.loadAll()
        XCTAssertEqual(friends.count, 1)
        XCTAssertEqual(friends.first?.voiceReference, "voice://clone")
    }

    func testBindingVoiceUpdatesOnlySelectedFriend() throws {
        let repository = InMemoryAIFriendRepository()
        let first = StoredAIFriend(
            id: UUID(),
            name: "小林",
            reviewedProfile: "性格：温和",
            voiceReference: "voice://stock-a",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let selected = StoredAIFriend(
            id: UUID(),
            name: "阿哲",
            reviewedProfile: "性格：幽默",
            voiceReference: "voice://stock-b",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try repository.save(first)
        try repository.save(selected)

        let updated = try repository.bindVoice("voice://clone-zhe", to: selected.id)

        XCTAssertEqual(updated.id, selected.id)
        XCTAssertEqual(updated.voiceReference, "voice://clone-zhe")
        XCTAssertEqual(try repository.loadAll(), [first, updated])
    }

    func testBindingVoiceRequiresExistingSelectedFriend() throws {
        let repository = InMemoryAIFriendRepository()

        XCTAssertThrowsError(try repository.bindVoice("voice://clone", to: UUID())) { error in
            XCTAssertEqual(error as? AIFriendRepositoryError, .friendNotFound)
        }
    }

}
