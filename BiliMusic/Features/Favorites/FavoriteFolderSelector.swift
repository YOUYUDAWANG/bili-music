import Foundation

/// 已登录时「点收藏」的目标夹：先音乐收藏夹，没有再退回 B 站默认夹。
enum FavoriteFolderSelector {
    static var preferredMusicFolderID: Int {
        UserDefaults.standard.integer(forKey: SettingsView.recommendFolderKey)
    }

    static func isMusicLibraryTitle(_ title: String) -> Bool {
        title.localizedCaseInsensitiveContains("music")
            || title.contains("音乐")
            || title.contains("歌曲")
    }

    static func musicLibraryFolder(
        from folders: [BiliClient.FavFolder],
        preferredId: Int
    ) -> BiliClient.FavFolder? {
        if preferredId != 0, let selected = folders.first(where: { $0.id == preferredId }) {
            return selected
        }
        return folders.first(where: { isMusicLibraryTitle($0.title) })
    }

    static func fallbackDefaultFolder(from folders: [BiliClient.FavFolder]) -> BiliClient.FavFolder? {
        folders.first(where: { $0.title.contains("默认") }) ?? folders.first
    }

    static func targetFolder(
        from folders: [BiliClient.FavFolder],
        preferredId: Int
    ) -> BiliClient.FavFolder? {
        musicLibraryFolder(from: folders, preferredId: preferredId)
            ?? fallbackDefaultFolder(from: folders)
    }
}
