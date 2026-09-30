import Testing
import Foundation
@testable import BreathRelaxStretch

@MainActor
struct RemoteProfileTests {

    private func encode(_ p: RemoteProfile) throws -> [String: Any] {
        let data = try JSONEncoder().encode(p)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func nilSaverFieldsAreOmittedFromUpload() throws {
        let p = RemoteProfile(id: "x", displayName: "A", totalPoints: 1, streak: 1,
                              totalMinutes: 1, lastSessionAt: nil)
        let json = try encode(p)
        #expect(json["points_spent"] == nil)
        #expect(json["streak_freeze_tokens"] == nil)
    }

    @Test func saverFieldsEncodeWithSnakeCaseKeys() throws {
        let p = RemoteProfile(id: "x", displayName: "A", totalPoints: 1, streak: 1,
                              totalMinutes: 1, lastSessionAt: nil,
                              pointsSpent: 150, streakFreezeTokens: 2)
        let json = try encode(p)
        #expect(json["points_spent"] as? Int == 150)
        #expect(json["streak_freeze_tokens"] as? Int == 2)
    }

    @Test func rowsWithoutSaverColumnsStillDecode() throws {
        let raw = #"{"id":"x","display_name":"A","total_points":1,"streak":1,"total_minutes":1}"#
        let p = try JSONDecoder().decode(RemoteProfile.self, from: Data(raw.utf8))
        #expect(p.pointsSpent == nil)
        #expect(p.streakFreezeTokens == nil)
    }
}
