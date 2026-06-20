import Foundation
import Observation

/// 收藏管理：维护本地已收藏 bvid 集合，并代理 B 站收藏夹的增删与「默认夹」记忆。
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

    /// 上次使用的收藏夹 id（持久化在 UserDefaults，0 视为无）。
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

    /// 加载某收藏夹后调用：记住该夹并把其中曲目并入已收藏集合。
    func markLoaded(folderId: Int, title: String? = nil, tracks: [Track]) {
        lastFolderId = folderId
        if let title {
            defaultFolderTitle = title
        }
        favoriteBVIDs.formUnion(tracks.map(\.bvid))
    }

    /// 记住默认收藏夹（不触发网络）。
    func remember(folderId: Int, title: String) {
        lastFolderId = folderId
        defaultFolderTitle = title
    }

    /// 该曲目是否已在已知收藏集合里。
    func isFavorite(_ track: Track) -> Bool {
        favoriteBVIDs.contains(track.bvid)
    }

    /// 切换收藏到默认收藏夹（无默认夹则给出提示）。
    func toggle(track: Track) async {
        guard let folderId = await defaultFolderId() else {
            lastError = "没有可用收藏夹,请先在 B 站创建一个收藏夹"
            return
        }
        await toggle(track: track, folderId: folderId)
    }

    /// 切换收藏到指定收藏夹，并把它记为新的默认夹。
    func toggle(track: Track, folder: BiliClient.FavFolder) async {
        remember(folderId: folder.id, title: folder.title)
        await toggle(track: track, folderId: folder.id)
    }

    /// 拉取收藏夹列表，并恢复上次默认夹的标题。
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

    /// 取默认收藏夹 id：优先上次用的，否则取「默认」夹或第一个。
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

    /// 实际执行收藏/取消：解析 aid → 调接口 → 更新本地集合。带 busy 去重。
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

    /// 取曲目 aid（缺失时回查 videoInfo）。
    private func resolveAid(_ track: Track) async throws -> Int {
        if let aid = track.aid { return aid }
        return try await client.videoInfo(bvid: track.bvid).aid
    }

    /// 把错误转成给用户看的中文提示（401 引导重新登录）。
    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? BiliClient.APIError, apiError.code == 401 {
            return "收藏授权失效,请在设置里重新扫码登录"
        }
        return error.localizedDescription
    }
}
