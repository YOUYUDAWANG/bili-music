import Foundation

struct LyricsTimingPolicy: Equatable, Sendable {
    var scope: LyricsVersionScope
    var timingKind: LyricsTimingKind
    var needsConfirmation: Bool
    var followsPlayback: Bool
    var appliesToCurrentCover: Bool
    var autoSave: Bool

    static func resolve(
        scope: LyricsVersionScope,
        trackDuration: Int,
        candidateDuration: Int?,
        hasWordSync: Bool,
        hasLineSync: Bool
    ) -> LyricsTimingPolicy {
        let syncedKind: LyricsTimingKind = hasWordSync ? .word : hasLineSync ? .line : .none
        switch scope {
        case .exactCover, .sameRecording:
            return LyricsTimingPolicy(
                scope: scope,
                timingKind: syncedKind,
                needsConfirmation: false,
                followsPlayback: syncedKind != .none,
                appliesToCurrentCover: true,
                autoSave: true)
        case .manual:
            return LyricsTimingPolicy(
                scope: .manual,
                timingKind: syncedKind,
                needsConfirmation: false,
                followsPlayback: syncedKind != .none,
                appliesToCurrentCover: true,
                autoSave: true)
        case .canonicalOriginal:
            let delta = abs((candidateDuration ?? Int.max) - trackDuration)
            if syncedKind != .none, candidateDuration != nil, delta <= 3 {
                return LyricsTimingPolicy(
                    scope: .canonicalOriginal,
                    timingKind: syncedKind,
                    needsConfirmation: true,
                    followsPlayback: true,
                    appliesToCurrentCover: false,
                    autoSave: true)
            }
            return LyricsTimingPolicy(
                scope: .canonicalOriginal,
                timingKind: .none,
                needsConfirmation: true,
                followsPlayback: false,
                appliesToCurrentCover: false,
                autoSave: true)
        case .textOnlyFallback:
            let durationFar = trackDuration > 0
                && candidateDuration != nil
                && abs((candidateDuration ?? 0) - trackDuration) > 25
            return LyricsTimingPolicy(
                scope: .textOnlyFallback,
                timingKind: syncedKind,
                needsConfirmation: syncedKind != .none,
                followsPlayback: syncedKind != .none && !durationFar,
                appliesToCurrentCover: false,
                autoSave: true)
        }
    }

    /// 用户点选或按版本搜索时保留时间轴；自动匹配才用原唱套翻唱的保守策略。
    static func forExplicitChoice(hasWordSync: Bool, hasLineSync: Bool) -> LyricsTimingPolicy {
        resolve(
            scope: .manual,
            trackDuration: 0,
            candidateDuration: 0,
            hasWordSync: hasWordSync,
            hasLineSync: hasLineSync)
    }
}

enum LyricsVersionClassifier {
    static func scope(
        for candidate: LyricsSearchResult,
        originalArtists: [String],
        coverPerformers: [String],
        isCoverSearch: Bool
    ) -> LyricsVersionScope {
        let performerHit = namesOverlap(candidate.artist, coverPerformers)
        let originalHit = namesOverlap(candidate.artist, originalArtists)
        if isCoverSearch, performerHit { return .exactCover }
        if isCoverSearch, originalHit { return .canonicalOriginal }
        if !isCoverSearch, originalHit { return .sameRecording }
        if performerHit { return .exactCover }
        if originalHit { return .canonicalOriginal }
        return .textOnlyFallback
    }

    static func rank(_ scope: LyricsVersionScope, preferCover: Bool) -> Int {
        switch (preferCover, scope) {
        case (true, .exactCover): return 0
        case (true, .sameRecording): return 1
        case (true, .canonicalOriginal): return 2
        case (true, .manual): return 3
        case (true, .textOnlyFallback): return 4
        case (false, .sameRecording): return 0
        case (false, .canonicalOriginal): return 1
        case (false, .exactCover): return 2
        case (false, .manual): return 3
        case (false, .textOnlyFallback): return 4
        }
    }

    static func titlesOverlap(_ left: String, _ right: String) -> Bool {
        namesOverlap(left, [right])
    }

    static func namesOverlap(_ value: String, _ names: [String]) -> Bool {
        let left = comparable(value)
        guard !left.isEmpty else { return false }
        return names.contains { name in
            let right = comparable(name)
            return !right.isEmpty && (left.contains(right) || right.contains(left))
        }
    }

    static func comparable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\-_/·・.,，。:：'\"“”‘’()\[\]【】（）《》「」『』!！?？&＆]"#, with: "", options: .regularExpression)
            .lowercased()
    }

    static func isJapaneseContext(track: Track, metadata: NormalizedTrackMetadata?) -> Bool {
        if metadata?.language == "ja" { return true }
        let title = LyricsAutoMatchGate.searchTitle(track: track, metadata: metadata)
            ?? metadata?.canonicalTitle
            ?? track.title
        return LyricsAutoMatchGate.containsJapaneseWriting(title)
    }

    static func isVirtualSingerContext(track: Track, metadata: NormalizedTrackMetadata?) -> Bool {
        let haystack = [
            track.title,
            track.artist,
            metadata?.canonicalTitle,
            metadata?.originalArtists.joined(separator: " "),
            metadata?.coverPerformers.joined(separator: " "),
            metadata?.uploader,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return ["vocaloid", "utau", "synthv", "cevio", "v家", "初音", "镜音", "巡音", "歌い手", "vsinger", "virtual singer", "ボカロ", "歌ってみた"]
            .contains { haystack.contains($0) }
    }
}

enum LyricsAdoption {
    static func timingQuality(_ kind: LyricsTimingKind) -> Int {
        switch kind {
        case .word: 2
        case .line: 1
        case .none: 0
        }
    }

    static func knownTimingQuality(_ document: LyricsDocument?) -> Int {
        guard let document else { return 0 }
        if document.hasWordSync { return 2 }
        if document.hasLineSync { return 1 }
        return 0
    }

    static func orderedForFetch(
        _ accepted: [LyricsSearchResult],
        documents: [String: LyricsDocument],
        originalArtists: [String],
        coverPerformers: [String],
        preferCover: Bool
    ) -> [LyricsSearchResult] {
        accepted.enumerated().sorted { lhs, rhs in
            let leftScope = LyricsVersionClassifier.scope(
                for: lhs.element,
                originalArtists: originalArtists,
                coverPerformers: coverPerformers,
                isCoverSearch: preferCover)
            let rightScope = LyricsVersionClassifier.scope(
                for: rhs.element,
                originalArtists: originalArtists,
                coverPerformers: coverPerformers,
                isCoverSearch: preferCover)
            let leftRank = LyricsVersionClassifier.rank(leftScope, preferCover: preferCover)
            let rightRank = LyricsVersionClassifier.rank(rightScope, preferCover: preferCover)
            if leftRank != rightRank { return leftRank < rightRank }
            let leftQuality = max(
                knownTimingQuality(documents[lhs.element.stableID]),
                timingQuality(lhs.element.timingKindHint ?? LyricsTimingKind.none))
            let rightQuality = max(
                knownTimingQuality(documents[rhs.element.stableID]),
                timingQuality(rhs.element.timingKindHint ?? LyricsTimingKind.none))
            if leftQuality != rightQuality { return leftQuality > rightQuality }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func bestDocument(in items: [(identityRank: Int, document: LyricsDocument)]) -> LyricsDocument? {
        guard let bestRank = items.map(\.identityRank).min() else { return nil }
        var winner: LyricsDocument?
        var winnerQuality = -1
        for item in items where item.identityRank == bestRank {
            let quality = timingQuality(item.document.timingKind)
            if quality > winnerQuality {
                winner = item.document
                winnerQuality = quality
            }
        }
        return winner
    }
}

enum LyricsAutoMatchGate {
    static func expectedTitles(track: Track, metadata: NormalizedTrackMetadata?) -> [String] {
        var titles: [String] = []
        if let canonical = metadata?.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
           !canonical.isEmpty {
            titles.append(canonical)
        }
        titles.append(contentsOf: metadata?.aliases ?? [])
        let parsed = TrackTitleParser.parseSongForDisplay(from: track.title, fallbackArtist: track.artist)
        if parsed.isDisplaySafe {
            titles.append(parsed.title)
        }
        return unique(titles.flatMap(splitBilingual))
    }

    /// 歌词检索用的歌名：有假名时用日文原名，不用中文译名。别名只用于匹配候选，不作为搜索词。
    static func preferredSearchTitle(canonicalTitle: String, aliases: [String] = []) -> String {
        let parts = ([canonicalTitle] + aliases).flatMap(splitBilingual)
        if let japanese = parts.first(where: containsJapaneseWriting) {
            return japanese
        }
        return canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchTitle(track: Track, metadata: NormalizedTrackMetadata?) -> String? {
        var titles: [String] = []
        if let canonical = metadata?.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
           !canonical.isEmpty {
            titles.append(canonical)
        }
        titles.append(contentsOf: metadata?.aliases ?? [])
        let parsed = TrackTitleParser.parseSongForDisplay(from: track.title, fallbackArtist: track.artist)
        if parsed.isDisplaySafe {
            titles.append(parsed.title)
        }
        let parts = unique(titles.flatMap(splitBilingual))
        if let japanese = parts.first(where: containsJapaneseWriting) {
            return japanese
        }
        return parts.first
    }

    static func defaultSearchKeyword(
        track: Track,
        metadata: NormalizedTrackMetadata?,
        lastKeyword: String
    ) -> String {
        let title = searchTitle(track: track, metadata: metadata) ?? track.title
        let last = lastKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if last.isEmpty { return title }
        if containsJapaneseWriting(title), !containsJapaneseWriting(last) {
            return title
        }
        return last
    }

    static func containsJapaneseKana(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value)
                || (0x30A0...0x30FF).contains(scalar.value)
                || (0x31F0...0x31FF).contains(scalar.value)
                || (0xFF66...0xFF9D).contains(scalar.value)
        }
    }

    /// 假名，或「拉丁字母 + 汉字」这种日语歌常见写法（You＆合図 没有假名）。
    static func containsJapaneseWriting(_ value: String) -> Bool {
        if containsJapaneseKana(value) { return true }
        let hasLatin = value.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && scalar.isASCII
        }
        let hasHan = value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        return hasLatin && hasHan
    }

    static func accepts(
        _ candidate: LyricsSearchResult,
        titles: [String]
    ) -> Bool {
        titles.contains { titleMatches(candidate.title, expected: $0) }
    }

    /// 自动采用翻唱词：歌名对上、演唱者是翻唱者。时长差只用来避开现场版；未知时长仍可采用。
    static func isHighConfidenceCover(
        _ candidate: LyricsSearchResult,
        titles: [String],
        coverPerformers: [String],
        trackDuration: Int
    ) -> Bool {
        guard accepts(candidate, titles: titles) else { return false }
        guard LyricsVersionClassifier.namesOverlap(candidate.artist, coverPerformers) else { return false }
        guard trackDuration > 0 else { return true }
        guard let duration = candidate.duration else { return true }
        return abs(duration - trackDuration) <= 25
    }

    static func titleMatches(_ candidate: String, expected: String) -> Bool {
        let left = stripPackaging(candidate)
        let right = stripPackaging(expected)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        let shorter = left.count < right.count ? left : right
        let longer = left.count < right.count ? right : left
        if longer.hasPrefix(shorter), shorter.count >= 2,
           Double(shorter.count) / Double(longer.count) >= 0.5 {
            return true
        }
        let prefix = zip(left, right).prefix { $0 == $1 }.count
        return prefix >= 2 && Double(prefix) / Double(min(left.count, right.count)) >= 0.35
    }

    private static func stripPackaging(_ value: String) -> String {
        var text = LyricsVersionClassifier.comparable(value)
        let suffixes = [
            "officialcover", "acousticcover", "cover", "covered", "official",
            "musicvideo", "lyricvideo", "karaoke", "version", "ver",
            "翻唱", "日文翻唱", "歌ってみた", "歌いました",
        ]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where text.hasSuffix(suffix) && text.count > suffix.count {
                text.removeLast(suffix.count)
                changed = true
                break
            }
        }
        return text
    }

    private static func splitBilingual(_ value: String) -> [String] {
        value
            .split(whereSeparator: { "/／|｜".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = LyricsVersionClassifier.comparable(value)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }
}
