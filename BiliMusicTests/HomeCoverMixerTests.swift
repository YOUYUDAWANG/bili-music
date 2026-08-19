import XCTest
@testable import BiliMusic

final class HomeCoverMixerTests: XCTestCase {
    func testMixInterleavesDiscoveryIntoLibraryGroups() {
        let library = (1...6).map { makeTrack(bvid: "BVLIB\($0)", title: "旧\($0)") }
        let discovery = (1...4).map { makeTrack(bvid: "BVNEW\($0)", title: "新\($0)") }

        let mixed = HomeCoverMixer.mix(library: library, discovery: discovery)

        XCTAssertEqual(Set(mixed.map(\.bvid)).count, 10)
        XCTAssertEqual(mixed.first?.bvid, "BVNEW1")
        XCTAssertEqual(mixed.filter { $0.bvid.hasPrefix("BVNEW") }.count, 4)
        XCTAssertEqual(mixed.filter { $0.bvid.hasPrefix("BVLIB") }.count, 6)
    }

    func testMixDropsDiscoveryAlreadyInLibrary() {
        let library = [makeTrack(bvid: "BVSAME", title: "收藏")]
        let discovery = [
            makeTrack(bvid: "BVSAME", title: "重复"),
            makeTrack(bvid: "BVFRESH", title: "新歌")
        ]

        let mixed = HomeCoverMixer.mix(library: library, discovery: discovery)

        XCTAssertEqual(mixed.map(\.bvid), ["BVFRESH", "BVSAME"])
    }

    func testMixFallsBackWhenOneSideIsEmpty() {
        let library = [makeTrack(bvid: "BVLIB1", title: "旧")]
        let discovery = [makeTrack(bvid: "BVNEW1", title: "新")]

        XCTAssertEqual(HomeCoverMixer.mix(library: library, discovery: []).map(\.bvid), ["BVLIB1"])
        XCTAssertEqual(HomeCoverMixer.mix(library: [], discovery: discovery).map(\.bvid), ["BVNEW1"])
    }

    func testDiscoveryBudgetScalesWithLibraryButStaysBounded() {
        XCTAssertEqual(HomeCoverMixer.discoveryBudget(forLibraryCount: 3), 12)
        XCTAssertEqual(HomeCoverMixer.discoveryBudget(forLibraryCount: 40), 16)
        XCTAssertEqual(HomeCoverMixer.discoveryBudget(forLibraryCount: 400), 48)
    }
}

final class RadioRelatedPickerTests: XCTestCase {
    func testPickerSkipsRecentlyShownHubsAndPrefersUnusedMusic() {
        let hub = Track(
            typeID: 3,
            bvid: "BVHUB",
            title: "周杰伦《晴天》Official MV",
            artist: "周杰伦",
            coverURL: nil,
            duration: 269)
        let next = Track(
            typeID: 3,
            bvid: "BVNEXT",
            title: "林俊杰《修炼爱情》",
            artist: "林俊杰",
            coverURL: nil,
            duration: 287)
        let chatter = Track(
            typeID: 17,
            bvid: "BVCHAT",
            title: "三国杀实况攻略合集",
            artist: "游戏区UP",
            coverURL: nil,
            duration: 900)

        let pick = RadioRelatedPicker.pick(
            from: [hub, chatter, next],
            recentBVIDs: ["BVHUB"])

        XCTAssertEqual(pick?.bvid, "BVNEXT")
    }

    func testPickerReturnsNilWhenEveryMusicTrackWasJustShown() {
        let only = Track(
            typeID: 3,
            bvid: "BVONLY",
            title: "邓紫棋《光年之外》",
            artist: "G.E.M.",
            coverURL: nil,
            duration: 235)

        XCTAssertNil(RadioRelatedPicker.pick(from: [only], recentBVIDs: ["BVONLY"]))
    }
}

private func makeTrack(bvid: String, title: String) -> Track {
    Track(
        bvid: bvid,
        title: title,
        artist: "UP",
        coverURL: URL(string: "https://example.invalid/\(bvid).jpg"),
        duration: 200)
}
