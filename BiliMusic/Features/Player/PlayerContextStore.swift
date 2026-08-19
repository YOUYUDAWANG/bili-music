import Foundation
import SwiftUI

struct RecommendationPanelRefreshPolicy: Equatable {
    var shouldLoadImmediately: Bool
    var shouldMarkStale: Bool

    static func currentTrackChanged(
        suppressImmediateRefresh: Bool,
        recommendationPanelVisible: Bool
    ) -> RecommendationPanelRefreshPolicy {
        if suppressImmediateRefresh {
            return RecommendationPanelRefreshPolicy(shouldLoadImmediately: false, shouldMarkStale: true)
        }
        if recommendationPanelVisible {
            return RecommendationPanelRefreshPolicy(shouldLoadImmediately: true, shouldMarkStale: false)
        }
        return RecommendationPanelRefreshPolicy(shouldLoadImmediately: false, shouldMarkStale: true)
    }
}

struct RecommendationVisibleLoadPolicy: Equatable {
    var shouldLoad: Bool

    static func playbackStarted(
        recommendationContextVisible: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        visibleLoad(
            recommendationContextVisible: recommendationContextVisible,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendationsEmpty,
            recommendationsMismatched: recommendationsMismatched)
    }

    static func visibleContextChanged(
        recommendationContextVisible: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        visibleLoad(
            recommendationContextVisible: recommendationContextVisible,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendationsEmpty,
            recommendationsMismatched: recommendationsMismatched)
    }

    private static func visibleLoad(
        recommendationContextVisible: Bool,
        recommendationsStale: Bool,
        recommendationsEmpty: Bool,
        recommendationsMismatched: Bool
    ) -> RecommendationVisibleLoadPolicy {
        RecommendationVisibleLoadPolicy(
            shouldLoad: recommendationContextVisible &&
                (recommendationsStale || recommendationsEmpty || recommendationsMismatched))
    }
}

struct PlaylistLookupResult {
    let playlist: BiliClient.UPPlaylist?
    let tracks: [Track]
    let error: String?
}

@MainActor
final class PlayerPlaylistLookupCache {
    static let shared = PlayerPlaylistLookupCache()

    private struct Entry {
        let result: PlaylistLookupResult
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let capacity = 32

    func result(for bvid: String, now: Date = Date()) -> PlaylistLookupResult? {
        guard let entry = entries[bvid] else { return nil }
        let ttl: TimeInterval
        if entry.result.error != nil {
            ttl = 60
        } else if entry.result.playlist == nil {
            ttl = 30 * 60
        } else {
            ttl = 2 * 60 * 60
        }
        guard now.timeIntervalSince(entry.storedAt) < ttl else {
            entries[bvid] = nil
            return nil
        }
        return entry.result
    }

    func store(_ result: PlaylistLookupResult, for bvid: String, now: Date = Date()) {
        entries[bvid] = Entry(result: result, storedAt: now)
        guard entries.count > capacity else { return }
        let overflow = entries.count - capacity
        for key in entries
            .sorted(by: { $0.value.storedAt < $1.value.storedAt })
            .prefix(overflow)
            .map(\.key) {
            entries[key] = nil
        }
    }
}

@Observable
@MainActor
final class PlayerContextStore {
    var recommendedTracks: [Track] = []
    var recommendationsLoading = false
    var recommendationsError: String?
    var currentPlaylist: BiliClient.UPPlaylist?
    var currentPlaylistTracks: [Track] = []
    var currentPlaylistLoading = false
    var currentPlaylistError: String?
    var suppressNextRecommendationRefresh = false
    var recommendationsStale = false
    var recommendationSeedKey: TrackKey?
    var shownRecommendationKeys: Set<TrackKey> = []
    var recommendationTask: Task<Void, Never>?
    var recommendationLoadID = UUID()
    var playlistLookupTask: Task<Void, Never>?
    var scheduledPlaylistBVID: String?

    func recommendationsMatchCurrentTrack(engine: PlayerEngine) -> Bool {
        guard let current = engine.current else {
            return recommendedTracks.isEmpty && recommendationSeedKey == nil
        }
        guard let recommendationSeedKey else { return false }
        return recommendationSeedKey.matches(current)
    }

    func cancelPendingWork() {
        recommendationTask?.cancel()
        recommendationLoadID = UUID()
        playlistLookupTask?.cancel()
        scheduledPlaylistBVID = nil
    }

    func resetForCurrentTrackChange() {
        cancelPendingWork()
        currentPlaylist = nil
        currentPlaylistTracks = []
        currentPlaylistError = nil
        currentPlaylistLoading = false
        recommendationSeedKey = nil
        recommendedTracks = []
        recommendationsError = nil
        shownRecommendationKeys = []
    }

    func ensureRecommendationsLoadedIfVisible(engine: PlayerEngine, recommendationContextVisible: Bool) {
        let loadPolicy = RecommendationVisibleLoadPolicy.visibleContextChanged(
            recommendationContextVisible: recommendationContextVisible,
            recommendationsStale: recommendationsStale,
            recommendationsEmpty: recommendedTracks.isEmpty,
            recommendationsMismatched: !recommendationsMatchCurrentTrack(engine: engine))
        guard loadPolicy.shouldLoad else { return }
        recommendationsStale = false
        scheduleRecommendationLoad(engine: engine, recommendationContextVisible: recommendationContextVisible, clear: !recommendedTracks.isEmpty)
    }

    func scheduleRecommendationLoad(engine: PlayerEngine, recommendationContextVisible: Bool, clear: Bool) {
        recommendationTask?.cancel()
        recommendationLoadID = UUID()
        recommendationsError = nil
        if clear {
            recommendedTracks = []
            recommendationSeedKey = nil
        }
        guard let current = engine.current else {
            recommendationsLoading = false
            return
        }
        guard recommendationContextVisible else {
            recommendationsLoading = false
            return
        }
        if !clear, recommendationSeedKey?.matches(current) == true, !recommendedTracks.isEmpty {
            recommendationsLoading = false
            return
        }
        let isVisible = recommendationContextVisible
        if isVisible && recommendedTracks.isEmpty {
            recommendationsLoading = true
        }
        let loadID = UUID()
        recommendationLoadID = loadID
        recommendationTask = Task(priority: isVisible ? .userInitiated : .utility) {
            try? await Task.sleep(for: .milliseconds(clear && isVisible ? 260 : 0))
            guard !Task.isCancelled, self.recommendationLoadID == loadID else { return }
            await self.loadRecommendations(engine: engine, recommendationContextVisible: recommendationContextVisible, loadID: loadID)
        }
    }

    func scheduleCurrentPlaylistLookup(engine: PlayerEngine, force: Bool, delay: Duration) {
        guard let current = engine.current else {
            playlistLookupTask?.cancel()
            scheduledPlaylistBVID = nil
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = nil
            currentPlaylistLoading = false
            return
        }

        let bvid = current.bvid
        if !force, let cached = PlayerPlaylistLookupCache.shared.result(for: bvid) {
            playlistLookupTask?.cancel()
            scheduledPlaylistBVID = nil
            applyPlaylistLookup(cached, for: bvid, engine: engine)
            return
        }
        guard force || scheduledPlaylistBVID != bvid else { return }

        playlistLookupTask?.cancel()
        scheduledPlaylistBVID = bvid
        currentPlaylist = nil
        currentPlaylistTracks = []
        currentPlaylistError = nil
        currentPlaylistLoading = false
        playlistLookupTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  engine.current?.bvid == bvid else { return }
            await self.loadCurrentPlaylistIfNeeded(engine: engine, force: force)
        }
    }

    func applyPlaylistLookup(_ result: PlaylistLookupResult, for bvid: String, engine: PlayerEngine) {
        guard engine.current?.bvid == bvid else { return }
        currentPlaylist = result.playlist
        currentPlaylistTracks = result.tracks
        currentPlaylistError = result.error
        currentPlaylistLoading = false
    }

    func loadRecommendations(engine: PlayerEngine, recommendationContextVisible: Bool, loadID: UUID) async {
        guard let current = engine.current else { return }
        let currentKey = current.key
        recommendationsLoading = recommendationContextVisible && recommendedTracks.isEmpty
        defer {
            if recommendationLoadID == loadID {
                recommendationsLoading = false
            }
        }
        await RecommendationMemory.shared.loadIfNeeded()
        let excluded = shownRecommendationKeys
            .union([currentKey])
            .union(await RecommendationMemory.shared.recentKeys())
        let tracks = await RecommendationEngine().recommendations(
            mode: .relatedPanel,
            context: .init(
                current: current,
                queue: engine.queue,
                playlistTracks: currentPlaylistTracks,
                excludedKeys: excluded),
            limit: 24)
        guard !Task.isCancelled,
              recommendationLoadID == loadID,
              engine.current.map({ currentKey.matches($0) }) ?? false else { return }
        shownRecommendationKeys.formUnion(tracks.map(\.key))
        await RecommendationMemory.shared.record(tracks.map(\.bvid))
        recommendationSeedKey = currentKey
        recommendedTracks = tracks
        recommendationsError = tracks.isEmpty ? "没有找到合适的推荐歌曲" : nil
        engine.preload(tracks: recommendedTracks, limit: 2, delay: .milliseconds(500))
    }

    func loadCurrentPlaylistIfNeeded(engine: PlayerEngine, force: Bool) async {
        guard let current = engine.current else {
            currentPlaylist = nil
            currentPlaylistTracks = []
            currentPlaylistError = nil
            return
        }
        if !force, currentPlaylistTracks.contains(where: { $0.bvid == current.bvid }) {
            return
        }

        let bvid = current.bvid
        if !force, let cached = PlayerPlaylistLookupCache.shared.result(for: bvid) {
            applyPlaylistLookup(cached, for: bvid, engine: engine)
            return
        }

        currentPlaylistLoading = true
        currentPlaylistError = nil
        defer {
            if scheduledPlaylistBVID == bvid {
                currentPlaylistLoading = false
                scheduledPlaylistBVID = nil
            }
        }
        do {
            let client = BiliClient()
            var resolvedOwnerMid = current.ownerMid
            var playlist = try await client.currentVideoPlaylist(bvid: bvid)
            if playlist == nil {
                if resolvedOwnerMid == nil {
                    resolvedOwnerMid = try? await client.videoInfo(bvid: bvid).owner.mid
                    guard !Task.isCancelled else { return }
                }
                if let ownerMid = resolvedOwnerMid {
                    playlist = try? await client.upPlaylistContaining(
                        bvid: bvid,
                        mid: ownerMid,
                        maxPlaylists: 4,
                        maxPages: 2)
                    guard !Task.isCancelled else { return }
                }
            }
            guard let playlist else {
                guard engine.current?.bvid == bvid else { return }
                let result = PlaylistLookupResult(playlist: nil, tracks: [], error: nil)
                storePlaylistLookup(result, for: bvid)
                applyPlaylistLookup(result, for: bvid, engine: engine)
                return
            }
            let artist = current.artist
            let ownerMid = resolvedOwnerMid
            let tracks = playlist.items?.map { item in
                Track(
                    aid: item.aid,
                    ownerMid: ownerMid,
                    bvid: item.bvid,
                    cid: item.cid,
                    title: item.title,
                    artist: artist,
                    coverURL: normalizedCoverURL(item.pic),
                    duration: item.duration ?? 0)
            } ?? []
            guard engine.current?.bvid == bvid else { return }
            let result = PlaylistLookupResult(playlist: playlist, tracks: tracks, error: nil)
            storePlaylistLookup(result, for: bvid)
            applyPlaylistLookup(result, for: bvid, engine: engine)
            engine.preload(tracks: tracks, limit: 2, delay: .milliseconds(700))
        } catch {
            guard !Task.isCancelled, engine.current?.bvid == bvid else { return }
            let result = PlaylistLookupResult(
                playlist: nil,
                tracks: [],
                error: "合集检测失败: \(error.localizedDescription)")
            storePlaylistLookup(result, for: bvid)
            applyPlaylistLookup(result, for: bvid, engine: engine)
        }
    }

    func storePlaylistLookup(_ result: PlaylistLookupResult, for bvid: String) {
        PlayerPlaylistLookupCache.shared.store(result, for: bvid)
    }

    func playCurrentPlaylistTrack(engine: PlayerEngine, at index: Int) async {
        guard currentPlaylistTracks.indices.contains(index) else { return }
        await engine.play(tracks: currentPlaylistTracks, startAt: index, queueMode: .sequential)
    }

    func scrollCurrentPlaylist(_ proxy: ScrollViewProxy, engine: PlayerEngine, reduceMotion: Bool) {
        guard let current = engine.current,
              let currentIndex = currentPlaylistTracks.firstIndex(where: { $0.key.matches(current) })
        else { return }
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(currentIndex, anchor: .center)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    private func normalizedCoverURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        return URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
    }
}
