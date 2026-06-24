import SwiftUI

/// 资料库标签页：在线收藏夹 + 离线缓存在一个页面内通过分段控制器切换。
struct LibraryTabView: View {
    @State private var selectedTab: LibraryTab = .favorites

    enum LibraryTab: String, CaseIterable, Identifiable {
        case favorites
        case cache

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorites: "收藏夹"
            case .cache: "缓存"
            }
        }

        var icon: String {
            switch self {
            case .favorites: "heart.fill"
            case .cache: "arrow.down.circle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("资料库", selection: $selectedTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            TabView(selection: $selectedTab) {
                FavoritesView()
                    .tag(LibraryTab.favorites)

                LibraryView()
                    .tag(LibraryTab.cache)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(AppTheme.groupedBackground)
    }
}
