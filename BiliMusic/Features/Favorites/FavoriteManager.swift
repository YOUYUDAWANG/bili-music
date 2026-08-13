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
    private var allIDsSyncedAt: Date?
    private var allIDsSyncAttemptedAt: Date?
    private var allIDsSyncTask: Task<Void, Never>?
    private var folderBVIDs: [Int: Set<String>] = [:]
    private var fullyLoadedFolderIDs: Set<Int> = []
    private var folderMutationVersions: [Int: Int] = [:]
    private var folderLoadTasks: [Int: Task<Set<String>, Error>] = [:]
    private var foldersLoadTask: Task<[BiliClient.FavFolder], Error>?
    private var busyOperationIDs: [String: UUID] = [:]
    private var authenticationGeneration = UUID()

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

    /// 登录账号变化后丢弃所有账号相关快照和在途任务，防止旧账号结果回写到新会话。
    func resetForAuthenticationChange() {
        authenticationGeneration = UUID()
        allIDsSyncTask?.cancel()
        allIDsSyncTask = nil
        foldersLoadTask?.cancel()
        foldersLoadTask = nil
        folderLoadTasks.values.forEach { $0.cancel() }
        folderLoadTasks = [:]
        favoriteBVIDs = []
        busyBVIDs = []
        busyOperationIDs = [:]
        lastError = nil
        defaultFolderTitle = nil
        folders = []
        foldersLoading = false
        allIDsSyncedAt = nil
        allIDsSyncAttemptedAt = nil
        folderBVIDs = [:]
        fullyLoadedFolderIDs = []
        folderMutationVersions = [:]
        lastFolderId = nil
    }

    /// 加载某收藏夹页面后调用：记住该夹并合并当前已知成员。
    func markLoaded(folderId: Int, title: String? = nil, tracks: [Track]) {
        lastFolderId = folderId
        if let title {
            defaultFolderTitle = title
        }
        folderBVIDs[folderId, default: []].formUnion(tracks.map(\.bvid))
        rebuildFavoriteBVIDs()
    }

    /// 记住默认收藏夹（不触发网络）。
    func remember(folderId: Int, title: String) {
        lastFolderId = folderId
        defaultFolderTitle = title
    }

    /// 该曲目是否已在已知收藏集合里。
    /// 统一用跨收藏夹并集判定(与「维护已收藏 bvid 全集」的语义一致),
    /// 避免默认夹加载完成前后同一首歌的心形状态无操作自翻转。
    func isFavorite(_ track: Track) -> Bool {
        favoriteBVIDs.contains(track.bvid)
    }

    /// 切换收藏到默认收藏夹（无默认夹则给出提示）。
    func toggle(track: Track) async {
        let generation = authenticationGeneration
        guard let folderId = await defaultFolderId() else {
            guard authenticationGeneration == generation else { return }
            // loadFolders 失败时 lastError 已是真实网络错误,不要用「没有收藏夹」覆盖;
            // 只有加载成功且确实没有任何夹时才提示去创建。
            if lastError == nil {
                lastError = "没有可用收藏夹,请先在 B 站创建一个收藏夹"
            }
            return
        }
        guard authenticationGeneration == generation else { return }
        await toggle(track: track, folderId: folderId)
    }

    /// 切换收藏到指定收藏夹，并把它记为新的默认夹。
    func toggle(track: Track, folder: BiliClient.FavFolder) async {
        if folders.isEmpty {
            await loadFolders()
        }
        guard folders.contains(where: { $0.id == folder.id }) else {
            lastError = "收藏夹已失效,请重新选择"
            return
        }
        remember(folderId: folder.id, title: folder.title)
        await toggle(track: track, folderId: folder.id)
    }

    /// 拉取收藏夹列表，并恢复上次默认夹的标题。
    func loadFolders() async {
        let generation = authenticationGeneration
        if let foldersLoadTask {
            await consumeFoldersLoad(foldersLoadTask, generation: generation)
            return
        }
        foldersLoading = true
        let task = Task<[BiliClient.FavFolder], Error> { [client] in
            try await client.favFolders()
        }
        foldersLoadTask = task
        await consumeFoldersLoad(task, generation: generation)
    }

    private func consumeFoldersLoad(
        _ task: Task<[BiliClient.FavFolder], Error>,
        generation: UUID
    ) async {
        do {
            let loadedFolders = try await task.value
            guard authenticationGeneration == generation else { return }
            folders = loadedFolders
            let validFolderIDs = Set(folders.map(\.id))
            folderBVIDs = folderBVIDs.filter { validFolderIDs.contains($0.key) }
            fullyLoadedFolderIDs.formIntersection(validFolderIDs)
            rebuildFavoriteBVIDs()
            if let lastFolderId,
               let folder = folders.first(where: { $0.id == lastFolderId }) {
                defaultFolderTitle = folder.title
            }
            lastError = nil
        } catch {
            guard authenticationGeneration == generation else { return }
            lastError = friendlyMessage(for: error)
        }
        guard authenticationGeneration == generation else { return }
        foldersLoadTask = nil
        foldersLoading = false
    }

    /// 同步「全部收藏」的 bvid 全集(跨所有收藏夹),供推荐去重用。
    /// 结果缓存 10 分钟；每个收藏夹独立维护成员，失败时保留上一份有效快照。
    /// 未登录直接返回——没有收藏可言。
    func syncAllFavoriteIDs(force: Bool = false) async {
        guard CookieStore.isLoggedIn else { return }
        let generation = authenticationGeneration
        if let allIDsSyncTask {
            await allIDsSyncTask.value
            return
        }
        if !force, let at = allIDsSyncedAt, Date().timeIntervalSince(at) < 600 { return }
        if !force, let at = allIDsSyncAttemptedAt, Date().timeIntervalSince(at) < 60 { return }
        allIDsSyncAttemptedAt = Date()
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performFavoriteIDSync(generation: generation)
        }
        allIDsSyncTask = task
        await task.value
        guard authenticationGeneration == generation else { return }
        allIDsSyncTask = nil
    }

    private func performFavoriteIDSync(generation: UUID) async {
        guard authenticationGeneration == generation else { return }
        if folders.isEmpty { await loadFolders() }
        guard authenticationGeneration == generation else { return }
        let targets = folders.filter { $0.media_count > 0 }.map(\.id)
        guard !targets.isEmpty else { allIDsSyncedAt = Date(); return }
        let versions = Dictionary(uniqueKeysWithValues: targets.map { ($0, folderMutationVersions[$0, default: 0]) })
        let results = await withTaskGroup(of: (Int, [String]?).self) { group in
            var iterator = targets.makeIterator()
            for _ in 0..<min(4, targets.count) {
                guard let folderId = iterator.next() else { break }
                group.addTask { [client] in
                    (folderId, try? await client.favItemIDs(folderId: folderId))
                }
            }
            var collected: [(Int, [String]?)] = []
            while let result = await group.next() {
                collected.append(result)
                if let folderId = iterator.next() {
                    group.addTask { [client] in
                        (folderId, try? await client.favItemIDs(folderId: folderId))
                    }
                }
            }
            return collected
        }
        guard authenticationGeneration == generation else { return }
        var allSucceeded = true
        for (folderId, ids) in results {
            guard let ids else {
                allSucceeded = false
                continue
            }
            guard folderMutationVersions[folderId, default: 0] == versions[folderId] else {
                allSucceeded = false
                continue
            }
            folderBVIDs[folderId] = Set(ids)
            fullyLoadedFolderIDs.insert(folderId)
        }
        rebuildFavoriteBVIDs()
        if allSucceeded {
            allIDsSyncedAt = Date()
        }
    }

    /// 取默认收藏夹 id：优先上次用的，否则取「默认」夹或第一个。
    @discardableResult
    func defaultFolderId() async -> Int? {
        if folders.isEmpty {
            await loadFolders()
        }
        if let lastFolderId,
           folders.contains(where: { $0.id == lastFolderId }) {
            return lastFolderId
        }
        guard let folder = folders.first(where: { $0.title.contains("默认") }) ?? folders.first else {
            return nil
        }
        remember(folderId: folder.id, title: folder.title)
        return folder.id
    }

    /// 实际执行收藏/取消：解析 aid → 调接口 → 更新本地集合。带 busy 去重。
    /// 边界：add/remove 只作用于目标收藏夹。若歌曲还收藏在其他夹,
    /// 移除后 `favoriteBVIDs` 并集仍包含它、心形保持点亮——与 `isFavorite`
    /// 的跨夹并集语义一致；接口失败时不改动本地集合,并集状态不会被误清。
    private func toggle(track: Track, folderId: Int) async {
        guard !busyBVIDs.contains(track.bvid) else { return }
        let generation = authenticationGeneration
        let operationID = UUID()
        busyOperationIDs[track.bvid] = operationID
        busyBVIDs.insert(track.bvid)
        defer {
            if busyOperationIDs[track.bvid] == operationID {
                busyOperationIDs[track.bvid] = nil
                busyBVIDs.remove(track.bvid)
            }
        }

        do {
            let aid = try await resolveAid(track)
            guard authenticationGeneration == generation else { return }
            let folderIDs = try await folderMembership(folderId: folderId)
            guard authenticationGeneration == generation else { return }
            let add = !folderIDs.contains(track.bvid)
            try await client.setFavorite(aid: aid, folderId: folderId, add: add)
            guard authenticationGeneration == generation else { return }
            var updated = folderBVIDs[folderId] ?? folderIDs
            if add {
                updated.insert(track.bvid)
            } else {
                updated.remove(track.bvid)
            }
            folderBVIDs[folderId] = updated
            folderMutationVersions[folderId, default: 0] += 1
            rebuildFavoriteBVIDs()
            lastError = nil
        } catch {
            guard authenticationGeneration == generation else { return }
            lastError = friendlyMessage(for: error)
        }
    }

    /// 取曲目 aid（缺失时回查 videoInfo）。
    private func resolveAid(_ track: Track) async throws -> Int {
        if let aid = track.aid { return aid }
        return try await client.videoInfo(bvid: track.bvid).aid
    }

    private func folderMembership(folderId: Int) async throws -> Set<String> {
        let generation = authenticationGeneration
        if fullyLoadedFolderIDs.contains(folderId) {
            return folderBVIDs[folderId] ?? []
        }
        if let task = folderLoadTasks[folderId] {
            return try await task.value
        }

        let version = folderMutationVersions[folderId, default: 0]
        let task = Task<Set<String>, Error> { [client] in
            Set(try await client.favItemIDs(folderId: folderId))
        }
        folderLoadTasks[folderId] = task
        do {
            let fetched = try await task.value
            guard authenticationGeneration == generation else {
                throw CancellationError()
            }
            folderLoadTasks[folderId] = nil
            if folderMutationVersions[folderId, default: 0] == version {
                folderBVIDs[folderId] = fetched
                fullyLoadedFolderIDs.insert(folderId)
                rebuildFavoriteBVIDs()
            }
            return folderBVIDs[folderId] ?? fetched
        } catch {
            if authenticationGeneration == generation {
                folderLoadTasks[folderId] = nil
            }
            throw error
        }
    }

    private func rebuildFavoriteBVIDs() {
        favoriteBVIDs = folderBVIDs.values.reduce(into: Set<String>()) {
            $0.formUnion($1)
        }
    }

    /// 把错误转成给用户看的中文提示（401 引导重新登录）。
    private func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? BiliClient.APIError,
           apiError.code == 401 || apiError.code == -101 {
            return "收藏授权失效,请在设置里重新扫码登录"
        }
        return error.localizedDescription
    }
}
