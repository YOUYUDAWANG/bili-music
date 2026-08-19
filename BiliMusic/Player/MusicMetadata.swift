import Foundation

/// 挂在 `TrackKey` 上的音乐身份：清洗后的歌名/歌手、歌词和用户偏移。
/// `Track` 继续只表示 B 站播放物。
struct MusicMetadata: Equatable, Sendable {
    var trackKey: TrackKey
    var sourceTitle: String
    var sourceArtist: String
    var normalized: NormalizedTrackMetadata?
    var lyricsDocument: LyricsDocument?
    var lyricOffsetMilliseconds: Int
    var albumArtURL: URL?
    var updatedAt: Date

    var displayTitle: String {
        let title = normalized?.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? sourceTitle : title
    }

    var displayArtist: String {
        normalized?.displayArtist(fallback: sourceArtist) ?? sourceArtist
    }

    var hasLyrics: Bool { lyricsDocument?.hasLyrics == true }

    func applying(to track: Track) -> Track {
        normalized?.applying(to: track) ?? track
    }

    static func compose(
        track: Track,
        metadataStore: TrackMetadataStore,
        lyrics: StoredLyricsEntry? = nil
    ) -> MusicMetadata {
        let stored = metadataStore.entry(for: track)
        return MusicMetadata(
            trackKey: stored?.trackKey ?? track.key,
            sourceTitle: stored?.sourceTitle ?? track.title,
            sourceArtist: stored?.sourceArtist ?? track.artist,
            normalized: stored?.metadata,
            lyricsDocument: lyrics?.document,
            lyricOffsetMilliseconds: lyrics?.offsetMilliseconds ?? 0,
            albumArtURL: nil,
            updatedAt: stored?.updatedAt ?? lyrics?.updatedAt ?? Date(timeIntervalSince1970: 0))
    }
}

enum MusicDisplayMetadata {
    static func resolve(
        for track: Track,
        metadataStore: TrackMetadataStore = .shared,
        clean: Bool = TrackTitleFormatter.shouldCleanListTitles
    ) -> TrackTitleFormatter.DisplayMetadata {
        _ = metadataStore
        return TrackTitleFormatter.displayMetadata(for: track, clean: clean)
    }

    static func coverURL(
        for track: Track,
        metadata: MusicMetadata?,
        preferMetadataCover: Bool
    ) -> URL? {
        if preferMetadataCover, let albumArtURL = metadata?.albumArtURL {
            return albumArtURL
        }
        return track.coverURL
    }
}

struct MusicLyricsSession: Equatable, Sendable {
    var document: LyricsDocument?
    var offsetMilliseconds: Int
    var offsetIsUserSet: Bool = false
    var keyword: String
    var provider: LyricsProvider
    var candidates: [LyricsSearchResult]
    var error: String?
    var isLoading: Bool
    var isMissCached: Bool

    static let empty = MusicLyricsSession(
        document: nil,
        offsetMilliseconds: 0,
        offsetIsUserSet: false,
        keyword: "",
        provider: .netease,
        candidates: [],
        error: nil,
        isLoading: false,
        isMissCached: false)
}
