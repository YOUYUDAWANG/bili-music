import Foundation
import Observation

@Observable
@MainActor
final class FavoriteManager {
    static let shared = FavoriteManager()

    private(set) var favoriteBVIDs: Set<String> = []
    private(set) var busyBVIDs: Set<String> = []
    private(set) var lastError: String?
    private(set) var defaultFolderTitle: String?
    private(set) var folders: [BiliClient.FavFolder] = []
    private(set) var foldersLoading = false

    private let lastFolderKey = "lastFavoriteFolderId"

    var lastFolderId: Int? {
        get {
            let saved = UserDefaults.standard.integer(forKey: lastFolderKey)
            return saved == 0 ? nil : saved
        }
        set {
            UserDefaults.standard.set(newValue ?? 0, forKey: lastFolderKey)
        }
    }

    private let client = BiliClient()

    private init() {}

    func markLoaded(folderId: Int, title: String? = nil, tracks: [Track]) {
        lastFolderId = folderId
        if let title {
            defaultFolderTitle = title
        }
        favoriteBVIDs.formUnion(tracks.map(\.bvid))
    }

    func remember(folderId: Int, title: String) {
        lastFolderId = folderId
        defaultFolderTitle = title
    }

    func isFavorite(_ track: Track) -> Bool {
        favoriteBVIDs.contains(track.bvid)
    }

    func toggle(track: Track) async {
        guard let folderId = await defaultFolderId() else {
            lastError = "没有可用收藏夹,请先在 B 站创建一个收藏夹"
            return
        }
        await toggle(track: track, folderId: folderId)
    }

    func toggle(track: Track, folder: BiliClient.FavFolder) async {
        remember(folderId: folder.id, title: folder.title)
        await toggle(track: track, folderId: folder.id)
    }

    func loadFolders() async {
        guard !foldersLoading else { return }
        foldersLoading = true
        defer { foldersLoading = false }
        do {
            folders = try await client.favFolders()
            if let lastFolderId,
               let folder = folders.first(where: { $0.id == lastFolderId }) {
                defaultFolderTitle = folder.title
            }
            lastError = nil
        } catch {
            lastError = friendlyMessage(for: error)
        }
    }

    @discardableResult
    func defaultFolderId() async -> Int? {
        if let lastFolderId {
            return lastFolderId
        }
        await loadFolders()
        guard let folder = folders.first(where: { $0.title.contains("默认") }) ?? folders.first else {
            return nil
        }
        remember(folderId: folder.id, title: folder.title)
        return folder.id
    }

    private func toggle(track: Track, folderId: Int) async {
        guard !busyBVIDs.contains(track.bvid) else { return }
        busyBVIDs.insert(track.bvid)
        defer { busyBVIDs.remove(track.bvid) }

        do {
            let aid = try await resolveAid(track)
            let add = !favoriteBVIDs.contains(track.bvid)
            try await client.setFavorite(aid: aid, folderId: folderId, add: add)
            if add {
                favoriteBVIDs.insert(track.bvid)
            } else {
                favoriteBVIDs.remove(track.bvid)
            }
            lastError = nil
        } catch {
            lastError = friendlyMessage(for: error)
        }
    }

    private func resolveAid(_ track: Track) async throws -> Int {
        if let aid = track.aid { return aid }
        return try await client.videoInfo(bvid: track.bvid).aid
    }

    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? BiliClient.APIError, apiError.code == 401 {
            return "收藏授权失效,请在设置里重新扫码登录"
        }
        return error.localizedDescription
    }
}
