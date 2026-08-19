import XCTest
@testable import BiliMusic

final class FavoriteFolderSelectorTests: XCTestCase {
    private let defaultFolder = BiliClient.FavFolder(id: 1, title: "默认收藏夹", media_count: 3)
    private let musicFolder = BiliClient.FavFolder(id: 8, title: "音乐", media_count: 12)
    private let watchLater = BiliClient.FavFolder(id: 9, title: "稍后再看", media_count: 4)

    func testExplicitMusicFolderBeatsDefaultFolder() {
        let folders = [defaultFolder, musicFolder, watchLater]
        let target = FavoriteFolderSelector.targetFolder(from: folders, preferredId: 8)
        XCTAssertEqual(target?.id, 8)
        XCTAssertEqual(target?.title, "音乐")
    }

    func testInferredMusicFolderWhenNoPreference() {
        let folders = [defaultFolder, watchLater, musicFolder]
        let target = FavoriteFolderSelector.targetFolder(from: folders, preferredId: 0)
        XCTAssertEqual(target?.id, 8)
    }

    func testFallbackToDefaultFolderWhenNoMusicFolder() {
        let folders = [watchLater, defaultFolder]
        let target = FavoriteFolderSelector.targetFolder(from: folders, preferredId: 0)
        XCTAssertEqual(target?.id, 1)
        XCTAssertEqual(target?.title, "默认收藏夹")
    }

    func testMissingPreferredIdFallsBackToInferredThenDefault() {
        let folders = [defaultFolder, musicFolder]
        let missingPreferred = FavoriteFolderSelector.targetFolder(from: folders, preferredId: 99)
        XCTAssertEqual(missingPreferred?.id, 8)

        let noMusic = FavoriteFolderSelector.targetFolder(from: [defaultFolder], preferredId: 99)
        XCTAssertEqual(noMusic?.id, 1)
    }
}
