import Foundation

/// 把收藏夹旧歌和发现新歌编进同一条 1+4 封面墙，不另开分区。
enum HomeCoverMixer {
    static let groupSize = 5
    static let discoveryPerGroup = 2

    static func discoveryBudget(forLibraryCount count: Int) -> Int {
        let groups = max(4, Int(ceil(Double(max(count, 1)) / Double(groupSize))))
        return min(48, max(12, groups * discoveryPerGroup))
    }

    static func mix(library: [Track], discovery: [Track]) -> [Track] {
        let library = Track.uniquedByBVIDPreferringCID(library)
        let libraryBVIDs = Set(library.map(\.bvid))
        let discovery = Track.uniquedByBVIDPreferringCID(
            discovery.filter { !libraryBVIDs.contains($0.bvid) })
        guard !discovery.isEmpty else { return library }
        guard !library.isEmpty else { return discovery }

        var mixed: [Track] = []
        mixed.reserveCapacity(library.count + discovery.count)
        var libraryIndex = 0
        var discoveryIndex = 0
        var groupIndex = 0

        while libraryIndex < library.count || discoveryIndex < discovery.count {
            var added = 0
            let preferDiscoveryFeatured = groupIndex.isMultiple(of: 2)
            var takenDiscovery = 0

            for slot in 0..<groupSize {
                let wantDiscovery = preferDiscoveryFeatured
                    ? (slot == 0 || slot == 3)
                    : (slot == 1 || slot == 3)
                if wantDiscovery,
                   takenDiscovery < discoveryPerGroup,
                   discoveryIndex < discovery.count {
                    mixed.append(discovery[discoveryIndex])
                    discoveryIndex += 1
                    takenDiscovery += 1
                    added += 1
                } else if libraryIndex < library.count {
                    mixed.append(library[libraryIndex])
                    libraryIndex += 1
                    added += 1
                } else if discoveryIndex < discovery.count {
                    mixed.append(discovery[discoveryIndex])
                    discoveryIndex += 1
                    added += 1
                }
            }

            groupIndex += 1
            if added == 0 { break }
        }

        return mixed
    }
}
