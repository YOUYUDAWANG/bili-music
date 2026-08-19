import Foundation
import OSLog

private let metadataLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "music-metadata")

/// 歌词与清洗元数据的编排。不进入起播热路径；由 `PlayerEngine` 在出声后调用。
@MainActor
final class MusicMetadataController {
    private let lyricsStore: LyricsStore
    private let lyricsClient: MetingLyricsClient
    private let metadataStore: TrackMetadataStore
    private let lyricsResolver: LyricsResolver
    private let amllProvider: AMLLLyricsProvider
    private let vocadbProvider: VocaDBLyricsProvider
    private let lrclibProvider: LRCLibLyricsProvider
    private let lddcProvider: LDDCLyricsBackendClient
    private var manualLyricsDocuments: [String: LyricsDocument] = [:]
    private var manualLyricsDocumentOrder: [String] = []

    init(
        lyricsStore: LyricsStore? = nil,
        lyricsClient: MetingLyricsClient = MetingLyricsClient(),
        metadataStore: TrackMetadataStore = .shared,
        lyricsResolver: LyricsResolver? = nil
    ) {
        let store = lyricsStore ?? .shared
        self.lyricsStore = store
        self.lyricsClient = lyricsClient
        self.metadataStore = metadataStore
        let amll = AMLLLyricsProvider()
        let vocadb = VocaDBLyricsProvider()
        let lrclib = LRCLibLyricsProvider()
        let lddc = LDDCLyricsBackendClient()
        self.amllProvider = amll
        self.vocadbProvider = vocadb
        self.lrclibProvider = lrclib
        self.lddcProvider = lddc
        self.lyricsResolver = lyricsResolver ?? LyricsResolver(
            catalog: lyricsClient,
            amllProvider: amll,
            vocadbProvider: vocadb,
            lrclibProvider: lrclib,
            lddcProvider: lddc)
    }

    func metadata(for track: Track) async -> MusicMetadata {
        let lyrics = await lyricsStore.entry(for: track)
        return MusicMetadata.compose(track: track, metadataStore: metadataStore, lyrics: lyrics)
    }

    func applyCachedIdentity(to track: Track) -> Track {
        metadataStore.applyingCachedMetadata(to: track)
    }

    func loadAutomaticLyrics(
        for track: Track,
        ignoreCache: Bool,
        scope: LyricsSearchScope = .automatic
    ) async -> MusicLyricsSession {
        let metadata = metadataStore.entry(for: track)?.metadata
        let resolution = await lyricsResolver.resolve(
            track: track,
            metadata: metadata,
            store: lyricsStore,
            ignoreCache: ignoreCache,
            scope: scope)
        if let document = resolution.session.document {
            metadataLog.info("lyrics loaded provider=\(document.result.provider.rawValue, privacy: .public) scope=\(document.versionScope.rawValue, privacy: .public) cache=\(resolution.fromCache)")
        } else {
            metadataLog.warning("lyrics no match cache=\(resolution.fromCache) miss=\(resolution.session.isMissCached)")
        }
        return resolution.session
    }

    func search(keyword: String, track: Track) async -> MusicLyricsSession {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MusicLyricsSession(
                document: nil,
                offsetMilliseconds: 0,
                keyword: trimmed,
                provider: .netease,
                candidates: [],
                error: "输入歌名或歌手再搜索",
                isLoading: false,
                isMissCached: false)
        }
        let metadata = metadataStore.entry(for: track)?.metadata
        async let lddcHitsTask: [LyricsExternalHit] = {
            do {
                return try await self.lddcProvider.search(
                    keyword: trimmed,
                    track: track,
                    metadata: metadata)
            } catch {
                return []
            }
        }()
        let batches = await withTaskGroup(of: [LyricsSearchResult].self) { group in
            for provider in LyricsProvider.catalogCases {
                group.addTask { await self.results(for: trimmed, provider: provider) }
            }
            var collected: [[LyricsSearchResult]] = []
            for await batch in group {
                collected.append(batch)
            }
            return collected
        }
        let lddcHits = await lddcHitsTask
        let verifiedWordHits = lddcHits.filter { $0.document.hasWordSync }
        for hit in verifiedWordHits {
            cacheManualLyricsDocument(hit.document, for: hit.result)
        }
        // Keep the validated backend row when the same platform/id also appeared in
        // the ordinary catalog batch, otherwise deduplication would discard its word hint.
        let allBatches = [verifiedWordHits.map(\.result)] + batches
        let ranked = MetingLyricsClient.aggregatedCandidates(
            allBatches,
            keyword: trimmed,
            originalArtists: metadata?.originalArtists ?? [],
            coverPerformers: metadata?.coverPerformers ?? [],
            duration: track.duration > 0 ? track.duration : nil,
            preferCover: metadata?.isCover == true)
        return MusicLyricsSession(
            document: nil,
            offsetMilliseconds: 0,
            keyword: trimmed,
            provider: ranked.first?.provider ?? .netease,
            candidates: ranked,
            error: ranked.isEmpty ? "没有搜索到候选歌曲" : nil,
            isLoading: false,
            isMissCached: false)
    }

    private func results(for keyword: String, provider: LyricsProvider) async -> [LyricsSearchResult] {
        switch provider {
        case .lrclib:
            return await lrclibProvider.search(keyword: keyword)
        case .vocadb:
            return await vocadbProvider.search(keyword: keyword)
        case .netease, .kugou, .tencent:
            return (try? await lyricsClient.search(keyword: keyword, provider: provider)) ?? []
        case .amll, .biliSubtitle, .imported, .precisionHost:
            return []
        }
    }

    func select(
        _ result: LyricsSearchResult,
        for track: Track,
        offsetMilliseconds: Int,
        offsetIsUserSet: Bool = false
    ) async -> MusicLyricsSession {
        do {
            let fetched: LyricsDocument
            if let cached = manualLyricsDocuments[result.stableID], cached.hasLyrics {
                fetched = cached
            } else if result.timingKindHint == .word,
                      let refreshed = try? await lddcProvider.search(
                        keyword: "\(result.title)-\(result.artist)",
                        track: track,
                        metadata: metadataStore.entry(for: track)?.metadata),
                      let hit = refreshed.first(where: { $0.result.stableID == result.stableID }),
                      hit.document.hasWordSync {
                cacheManualLyricsDocument(hit.document, for: hit.result)
                fetched = hit.document
            } else {
                switch result.provider {
                case .lrclib:
                    if let cached = await lrclibProvider.fetch(for: result) {
                        fetched = cached
                    } else if let hit = await lrclibProvider.lookup(
                        title: result.title,
                        artist: result.artist,
                        duration: result.duration
                    ).first(where: { $0.result.id == result.id }) {
                        fetched = hit.document
                    } else {
                        throw MetingLyricsClient.ClientError.noLyrics
                    }
                case .vocadb:
                    if let cached = await vocadbProvider.fetch(for: result) {
                        fetched = cached
                    } else if let hit = await vocadbProvider.lookup(
                        title: result.title,
                        artist: result.artist,
                        duration: result.duration
                    ).first(where: { $0.result.id == result.id }) {
                        fetched = hit.document
                    } else {
                        throw MetingLyricsClient.ClientError.noLyrics
                    }
                default:
                    do {
                        let catalog = try await lyricsClient.fetchLyrics(for: result)
                        if let amll = await amllProvider.lyrics(for: result), amll.hasLyrics {
                            fetched = amll
                        } else {
                            fetched = catalog
                        }
                    } catch {
                        if let amll = await amllProvider.lyrics(for: result), amll.hasLyrics {
                            fetched = amll
                        } else {
                            throw error
                        }
                    }
                }
            }
            let document = fetched.applying(
                policy: LyricsTimingPolicy.forExplicitChoice(
                    hasWordSync: fetched.hasWordSync,
                    hasLineSync: fetched.hasLineSync))
            await lyricsStore.save(
                document: document,
                offsetMilliseconds: offsetIsUserSet ? offsetMilliseconds : 0,
                offsetIsUserSet: offsetIsUserSet,
                for: track)
            return MusicLyricsSession(
                document: document,
                offsetMilliseconds: offsetIsUserSet ? offsetMilliseconds : 0,
                offsetIsUserSet: offsetIsUserSet,
                keyword: "",
                provider: result.provider,
                candidates: [],
                error: nil,
                isLoading: false,
                isMissCached: false)
        } catch {
            return MusicLyricsSession(
                document: nil,
                offsetMilliseconds: offsetMilliseconds,
                offsetIsUserSet: offsetIsUserSet,
                keyword: "",
                provider: result.provider,
                candidates: [],
                error: error.localizedDescription,
                isLoading: false,
                isMissCached: false)
        }
    }

    func importLyrics(_ document: LyricsDocument, for track: Track) async {
        await lyricsStore.save(document: document, offsetMilliseconds: 0, offsetIsUserSet: true, for: track)
    }

    func saveGeneratedWordLyrics(_ document: LyricsDocument, for track: Track) async {
        await lyricsStore.save(
            document: document,
            offsetMilliseconds: 0,
            offsetIsUserSet: false,
            for: track)
    }

    func saveOnDeviceWordLyrics(_ document: LyricsDocument, for track: Track) async {
        await saveGeneratedWordLyrics(document, for: track)
    }

    func markCurrentLyricsAppliesToCover(for track: Track) async -> (document: LyricsDocument, offsetMilliseconds: Int)? {
        guard let entry = await lyricsStore.entry(for: track),
              let document = entry.document else { return nil }
        let restored = document.restoringPlaybackTiming()
        let offset: Int
        let userSet: Bool
        if entry.offsetIsUserSet {
            offset = entry.offsetMilliseconds
            userSet = true
        } else {
            offset = 0
            userSet = false
        }
        await lyricsStore.save(
            document: restored,
            offsetMilliseconds: offset,
            offsetIsUserSet: userSet,
            for: track)
        return (restored, offset)
    }

    func persistOffset(_ offsetMilliseconds: Int, userSet: Bool = true, for track: Track) async {
        await lyricsStore.updateOffset(offsetMilliseconds, userSet: userSet, for: track)
    }

    func flush() async {
        await lyricsStore.flush()
    }

    private func cacheManualLyricsDocument(
        _ document: LyricsDocument,
        for result: LyricsSearchResult
    ) {
        let key = result.stableID
        if manualLyricsDocuments[key] == nil {
            manualLyricsDocumentOrder.append(key)
        }
        manualLyricsDocuments[key] = document
        while manualLyricsDocumentOrder.count > 64 {
            let expired = manualLyricsDocumentOrder.removeFirst()
            manualLyricsDocuments.removeValue(forKey: expired)
        }
    }
}
