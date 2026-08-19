import Foundation
import OSLog

private let lyricsResolverLog = Logger(subsystem: "com.fubuki.BiliMusic", category: "lyrics-resolver")

struct LyricsResolution: Sendable {
    var session: MusicLyricsSession
    var fromCache: Bool
    var networkRequests: Int
}

actor LyricsResolver {
    private let catalog: any LyricsCatalogSearching
    private let amllProvider: AMLLLyricsProvider?
    private let vocadbProvider: VocaDBLyricsProvider?
    private let lrclibProvider: LRCLibLyricsProvider?
    private let lddcProvider: (any LDDCLyricsBackendSearching)?
    private(set) var networkRequests = 0

    init(
        catalog: any LyricsCatalogSearching,
        amllProvider: AMLLLyricsProvider? = nil,
        vocadbProvider: VocaDBLyricsProvider? = nil,
        lrclibProvider: LRCLibLyricsProvider? = nil,
        lddcProvider: (any LDDCLyricsBackendSearching)? = nil
    ) {
        self.catalog = catalog
        self.amllProvider = amllProvider
        self.vocadbProvider = vocadbProvider
        self.lrclibProvider = lrclibProvider
        self.lddcProvider = lddcProvider
    }

    func resetNetworkCount() {
        networkRequests = 0
    }

    func resolve(
        track: Track,
        metadata: NormalizedTrackMetadata?,
        store: LyricsStore,
        ignoreCache: Bool,
        scope: LyricsSearchScope = .automatic
    ) async -> LyricsResolution {
        if !ignoreCache, let cached = await store.entry(for: track) {
            if let document = cached.document, document.hasLyrics, !document.result.provider.isRetired {
                let refreshed = applyPolicy(
                    document,
                    scope: document.versionScope,
                    track: track,
                    candidate: document.result,
                    userInitiated: document.versionScope == .manual)
                let resetsGeneratedOffset = refreshed.result.provider == .precisionHost
                    && (cached.offsetMilliseconds != 0 || cached.offsetIsUserSet)
                let effectiveOffset = resetsGeneratedOffset ? 0 : cached.offsetMilliseconds
                let effectiveOffsetIsUserSet = resetsGeneratedOffset ? false : cached.offsetIsUserSet
                if refreshed.followsPlayback != document.followsPlayback
                    || refreshed.timingKind != document.timingKind
                    || resetsGeneratedOffset {
                    await store.save(
                        document: refreshed,
                        offsetMilliseconds: effectiveOffset,
                        offsetIsUserSet: effectiveOffsetIsUserSet,
                        for: track)
                }
                return LyricsResolution(
                    session: MusicLyricsSession(
                        document: refreshed,
                        offsetMilliseconds: effectiveOffset,
                        offsetIsUserSet: effectiveOffsetIsUserSet,
                        keyword: "",
                        provider: refreshed.result.provider,
                        candidates: [],
                        error: nil,
                        isLoading: false,
                        isMissCached: false),
                    fromCache: true,
                    networkRequests: 0)
            }
            if cached.isActiveMiss() {
                return LyricsResolution(
                    session: MusicLyricsSession(
                        document: nil,
                        offsetMilliseconds: 0,
                        keyword: "",
                        provider: .netease,
                        candidates: [],
                        error: "最近没有找到歌词，可重新搜索",
                        isLoading: false,
                        isMissCached: true),
                    fromCache: true,
                    networkRequests: 0)
            }
        }

        networkRequests = 0
        let isCover = metadata?.isCover == true
        var candidates: [LyricsSearchResult] = []
        var keyword = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata) ?? track.title

        if scope == .coverVersion || (scope == .automatic && isCover) {
            let coverMatch = await searchPass(
                queries: coverQueries(track: track, metadata: metadata),
                track: track,
                metadata: metadata,
                preferCover: true,
                userInitiated: scope != .automatic,
                requireHighConfidenceCover: scope == .automatic)
            candidates = coverMatch.candidates
            keyword = coverMatch.keyword
            if let document = coverMatch.document {
                let saved = await persist(document, for: track, store: store)
                return resolution(
                    document: saved.document,
                    keyword: keyword,
                    candidates: candidates,
                    networkRequests: networkRequests,
                    offsetMilliseconds: saved.offset,
                    offsetIsUserSet: saved.userSet)
            }
            if scope == .coverVersion {
                await store.saveMiss(for: track)
                return resolution(document: nil, keyword: keyword, candidates: candidates, networkRequests: networkRequests, error: "没有找到翻唱版本歌词")
            }
        }

        if scope != .coverVersion {
            let originalMatch = await searchPass(
                queries: originalQueries(track: track, metadata: metadata),
                track: track,
                metadata: metadata,
                preferCover: false,
                userInitiated: scope != .automatic)
            if candidates.isEmpty {
                candidates = originalMatch.candidates
                keyword = originalMatch.keyword
            }
            if let document = originalMatch.document {
                let saved = await persist(document, for: track, store: store)
                return resolution(
                    document: saved.document,
                    keyword: keyword,
                    candidates: candidates,
                    networkRequests: networkRequests,
                    offsetMilliseconds: saved.offset,
                    offsetIsUserSet: saved.userSet)
            }
        }

        await store.saveMiss(for: track)
        return resolution(
            document: nil,
            keyword: keyword,
            candidates: candidates,
            networkRequests: networkRequests,
            error: "自动匹配失败，可手动搜索或导入歌词")
    }

    private func searchPass(
        queries: [String],
        track: Track,
        metadata: NormalizedTrackMetadata?,
        preferCover: Bool,
        userInitiated: Bool,
        requireHighConfidenceCover: Bool = false
    ) async -> (keyword: String, candidates: [LyricsSearchResult], document: LyricsDocument?) {
        var lastKeyword = queries.first ?? track.title
        let originals = metadata?.originalArtists ?? []
        let covers = metadata?.coverPerformers ?? []
        let expectedTitles = LyricsAutoMatchGate.expectedTitles(track: track, metadata: metadata)
        guard !expectedTitles.isEmpty else {
            return (lastKeyword, [], nil)
        }

        var pooled: [LyricsSearchResult] = []
        var ready: [String: LyricsDocument] = [:]
        let title = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata) ?? track.title
        let artist = preferCover ? covers.first : originals.first
        let wantsInternational = LyricsVersionClassifier.isJapaneseContext(track: track, metadata: metadata)
            || LyricsVersionClassifier.isVirtualSingerContext(track: track, metadata: metadata)
        var backendHasWordTiming = false

        if let lddcProvider {
            do {
                let hits = try await lddcProvider.lookup(
                    track: track,
                    metadata: metadata,
                    preferCover: preferCover)
                networkRequests += 1
                let wanted = wantedScopes(preferCover: preferCover, metadata: metadata)
                backendHasWordTiming = hits.contains { hit in
                    guard hit.document.hasWordSync else { return false }
                    let scope = candidateScope(
                        for: hit.result,
                        metadata: metadata,
                        originalArtists: originals,
                        coverPerformers: covers,
                        preferCover: preferCover)
                    guard wanted.contains(scope),
                          LyricsAutoMatchGate.accepts(hit.result, titles: expectedTitles) else { return false }
                    return !requireHighConfidenceCover || LyricsAutoMatchGate.isHighConfidenceCover(
                        hit.result,
                        titles: expectedTitles,
                        coverPerformers: covers,
                        trackDuration: track.duration)
                }
                merge(hits, into: &pooled, documents: &ready)
            } catch LDDCLyricsBackendError.notConfigured {
                // An unconfigured optional backend is the normal local-development fallback.
            } catch {
                lyricsResolverLog.debug("LDDC lyrics backend failed \(error.localizedDescription, privacy: .public)")
            }
        }

        if !backendHasWordTiming, wantsInternational {
            if let hits = await lrclibProvider?.lookup(title: title, artist: artist, duration: track.duration) {
                networkRequests += 1
                merge(hits, into: &pooled, documents: &ready)
            }
            if let hits = await vocadbProvider?.lookup(title: title, artist: artist, duration: track.duration) {
                networkRequests += 1
                merge(hits, into: &pooled, documents: &ready)
            }
        } else if !backendHasWordTiming, preferCover == false {
            if let hits = await lrclibProvider?.lookup(title: title, artist: artist, duration: track.duration) {
                networkRequests += 1
                merge(hits, into: &pooled, documents: &ready)
            }
        }

        if !backendHasWordTiming {
            let providers: [LyricsProvider] = [.netease, .tencent, .kugou]
            for query in queries where !query.isEmpty {
                lastKeyword = query
                let found = await searchChineseCatalog(query: query, providers: providers)
                networkRequests += providers.count
                pooled.append(contentsOf: found)
            }
        }

        var seen = Set<String>()
        pooled = pooled.filter { seen.insert($0.stableID).inserted }
        let ranked = MetingLyricsClient.rankedCandidates(
            pooled,
            keyword: lastKeyword,
            originalArtists: originals,
            coverPerformers: covers,
            duration: track.duration > 0 ? track.duration : nil,
            preferCover: preferCover)
        let wanted = wantedScopes(preferCover: preferCover, metadata: metadata)
        let accepted = ranked.filter { candidate in
            let scope = candidateScope(
                for: candidate,
                metadata: metadata,
                originalArtists: originals,
                coverPerformers: covers,
                preferCover: preferCover)
            guard wanted.contains(scope) else { return false }
            guard LyricsAutoMatchGate.accepts(candidate, titles: expectedTitles) else { return false }
            if requireHighConfidenceCover {
                return LyricsAutoMatchGate.isHighConfidenceCover(
                    candidate,
                    titles: expectedTitles,
                    coverPerformers: covers,
                    trackDuration: track.duration)
            }
            return true
        }
        let ordered = LyricsAdoption.orderedForFetch(
            accepted,
            documents: ready,
            originalArtists: originals,
            coverPerformers: covers,
            preferCover: preferCover)
        var adopted: [(identityRank: Int, document: LyricsDocument)] = []
        var identityRank: Int?
        var bestQuality = 0
        for candidate in ordered.prefix(8) {
            let scope = candidateScope(
                for: candidate,
                metadata: metadata,
                originalArtists: originals,
                coverPerformers: covers,
                preferCover: preferCover)
            let rank = LyricsVersionClassifier.rank(scope, preferCover: preferCover)
            if let identityRank, rank > identityRank { break }

            let readyDocument = ready[candidate.stableID]
            let readyQuality = LyricsAdoption.knownTimingQuality(readyDocument)
            if bestQuality >= 1, readyDocument == nil {
                continue
            }
            if bestQuality >= 1, readyQuality <= bestQuality {
                continue
            }

            let raw: LyricsDocument?
            if let readyDocument, readyDocument.hasLyrics {
                raw = readyDocument
            } else {
                networkRequests += 1
                if let document = try? await catalog.fetchLyrics(for: candidate), document.hasLyrics {
                    if let amll = await amllProvider?.lyrics(for: candidate), amll.hasLyrics {
                        networkRequests += 1
                        raw = amll
                    } else {
                        raw = document
                    }
                } else {
                    raw = nil
                }
            }
            guard let raw, raw.hasLyrics else { continue }
            let applied = applyPolicy(
                raw,
                scope: scope,
                track: track,
                candidate: candidate,
                userInitiated: userInitiated)
            if identityRank == nil { identityRank = rank }
            adopted.append((rank, applied))
            bestQuality = max(bestQuality, LyricsAdoption.timingQuality(applied.timingKind))
            if bestQuality >= 2 { break }
        }
        return (lastKeyword, ranked, LyricsAdoption.bestDocument(in: adopted))
    }

    private func searchChineseCatalog(query: String, providers: [LyricsProvider]) async -> [LyricsSearchResult] {
        let catalog = catalog
        return await withTaskGroup(of: [LyricsSearchResult].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await catalog.search(keyword: query, provider: provider)
                    } catch {
                        lyricsResolverLog.debug("lyrics search failed provider=\(provider.rawValue, privacy: .public) \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }
            var combined: [LyricsSearchResult] = []
            for await found in group {
                combined.append(contentsOf: found)
            }
            return combined
        }
    }

    private func merge(
        _ hits: [LyricsExternalHit],
        into pooled: inout [LyricsSearchResult],
        documents: inout [String: LyricsDocument]
    ) {
        for hit in hits {
            pooled.append(hit.result)
            documents[hit.result.stableID] = hit.document
        }
    }

    private func applyPolicy(
        _ document: LyricsDocument,
        scope: LyricsVersionScope,
        track: Track,
        candidate: LyricsSearchResult,
        userInitiated: Bool
    ) -> LyricsDocument {
        let policy = userInitiated
            ? LyricsTimingPolicy.forExplicitChoice(
                hasWordSync: document.hasWordSync,
                hasLineSync: document.hasLineSync)
            : LyricsTimingPolicy.resolve(
                scope: scope,
                trackDuration: track.duration,
                candidateDuration: candidate.duration,
                hasWordSync: document.hasWordSync,
                hasLineSync: document.hasLineSync)
        return document.applying(policy: policy)
    }

    private func persist(_ document: LyricsDocument, for track: Track, store: LyricsStore) async -> (document: LyricsDocument, offset: Int, userSet: Bool) {
        let existing = await store.entry(for: track)
        let offset: Int
        let userSet: Bool
        if let existing, existing.offsetIsUserSet {
            offset = existing.offsetMilliseconds
            userSet = true
        } else if let existing,
                  existing.document?.result.stableID == document.result.stableID {
            offset = existing.offsetMilliseconds
            userSet = false
        } else {
            offset = 0
            userSet = false
        }
        await store.save(
            document: document,
            offsetMilliseconds: offset,
            offsetIsUserSet: userSet,
            for: track)
        return (document, offset, userSet)
    }

    private func resolution(
        document: LyricsDocument?,
        keyword: String,
        candidates: [LyricsSearchResult],
        networkRequests: Int,
        error: String? = nil,
        offsetMilliseconds: Int = 0,
        offsetIsUserSet: Bool = false
    ) -> LyricsResolution {
        LyricsResolution(
            session: MusicLyricsSession(
                document: document,
                offsetMilliseconds: offsetMilliseconds,
                offsetIsUserSet: offsetIsUserSet,
                keyword: keyword,
                provider: document?.result.provider ?? .netease,
                candidates: candidates,
                error: document == nil ? error : nil,
                isLoading: false,
                isMissCached: false),
            fromCache: false,
            networkRequests: networkRequests)
    }

    private func wantedScopes(
        preferCover: Bool,
        metadata: NormalizedTrackMetadata?
    ) -> Set<LyricsVersionScope> {
        if preferCover { return [.exactCover] }
        if metadata?.isCover == true { return [.canonicalOriginal, .textOnlyFallback] }
        return [.sameRecording, .canonicalOriginal, .textOnlyFallback]
    }

    private func candidateScope(
        for candidate: LyricsSearchResult,
        metadata: NormalizedTrackMetadata?,
        originalArtists: [String],
        coverPerformers: [String],
        preferCover: Bool
    ) -> LyricsVersionScope {
        let classified = LyricsVersionClassifier.scope(
            for: candidate,
            originalArtists: originalArtists,
            coverPerformers: coverPerformers,
            isCoverSearch: preferCover)
        if metadata?.isCover == true, !preferCover, classified == .sameRecording {
            return .canonicalOriginal
        }
        return classified
    }

    private func coverQueries(track: Track, metadata: NormalizedTrackMetadata?) -> [String] {
        guard let title = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata) else {
            return []
        }
        let performers = metadata?.coverPerformers ?? []
        return versionQueries(title: title, names: performers, includeBareTitle: performers.isEmpty)
    }

    private func originalQueries(track: Track, metadata: NormalizedTrackMetadata?) -> [String] {
        guard let title = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata) else {
            return []
        }
        return versionQueries(
            title: title,
            names: metadata?.originalArtists ?? [],
            includeBareTitle: true)
    }

    private func versionQueries(title: String, names: [String], includeBareTitle: Bool) -> [String] {
        var queries: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            queries.append("\(title) \(trimmed)")
        }
        if includeBareTitle || queries.isEmpty {
            queries.append(title)
        }
        var seen = Set<String>()
        return queries.filter { seen.insert($0).inserted }
    }
}
