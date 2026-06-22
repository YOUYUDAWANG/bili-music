import Foundation

enum SearchResultMode: String, CaseIterable, Identifiable {
    case music
    case mv
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "音乐"
        case .mv: "MV"
        case .expanded: "扩大"
        }
    }

    var usesBiliMusicOnlySearch: Bool {
        switch self {
        case .music, .mv: true
        case .expanded: false
        }
    }
}

struct SearchCacheKey: Hashable {
    let query: String
    let mode: SearchResultMode

    init(query: String, mode: SearchResultMode) {
        self.query = query
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.mode = mode
    }
}

struct SearchCachedSnapshot {
    var tracks: [Track]
    var nextPage: Int
    var activeKeywords: [String]
    var hasMoreResults: Bool
}

struct SearchResultSections {
    var bestMatch: Track?
    var songs: [Track]
    var mvs: [Track]

    static func make(from tracks: [Track]) -> SearchResultSections {
        let best = tracks.first
        let rest = Array(tracks.dropFirst())
        let mvTracks = rest.filter { track in
            track.typeID == 193 || track.title.localizedCaseInsensitiveContains("mv")
        }
        let mvKeys = Set(mvTracks.map(\.key))
        let songs = rest.filter { track in
            !mvKeys.contains { $0.matches(track) }
        }
        return SearchResultSections(bestMatch: best, songs: songs, mvs: mvTracks)
    }
}
