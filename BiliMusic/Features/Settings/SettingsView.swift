import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    @State private var loggedIn = CookieStore.isLoggedIn
    @State private var username: String?
    @State private var showLogin = false
    @AppStorage("autoCache") private var autoCache = false
    @AppStorage("playbackQuality") private var playbackQuality = 0
    @AppStorage("downloadQuality") private var downloadQuality = 0
    @AppStorage("preferMVOnWiFi") private var preferMVOnWiFi = true
    @AppStorage("recommendFolderId") private var recommendFolderId = 0
    @State private var favFolders: [BiliClient.FavFolder] = []

    var body: some View {
        NavigationStack {
            List {
                Section("账号") {
                    if loggedIn {
                        LabeledContent("已登录", value: username ?? "…")
                        Button("退出登录", role: .destructive) {
                            CookieStore.cookie = nil
                            loggedIn = false
                            username = nil
                        }
                    } else {
                        Button("扫码登录 B 站账号") { showLogin = true }
                        Text("登录后可获得更高音质、个性化推荐和收藏夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if loggedIn {
                    Section("推荐") {
                        Picker("推荐种子收藏夹", selection: $recommendFolderId) {
                            Text("默认收藏夹").tag(0)
                            ForEach(favFolders) { folder in
                                Text("\(folder.title)(\(folder.media_count))").tag(folder.id)
                            }
                        }
                        Text("首页推荐会从这个收藏夹随机取歌当种子,建议选你的音乐收藏夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("音质") {
                    Picker("播放音质", selection: $playbackQuality) {
                        Text("最高可用").tag(0)
                        Text("Hi-Res").tag(30251)
                        Text("高码率").tag(30280)
                        Text("132K").tag(30232)
                        Text("64K").tag(30216)
                    }
                    Picker("下载音质", selection: $downloadQuality) {
                        Text("最高可用").tag(0)
                        Text("Hi-Res").tag(30251)
                        Text("高码率").tag(30280)
                        Text("132K").tag(30232)
                        Text("64K").tag(30216)
                    }
                    Text("“最高可用”含 Hi-Res 无损(需大会员);流量紧张选低档")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("缓存") {
                    Toggle("自动缓存播放过的歌曲", isOn: $autoCache)
                    Text("在线播放的歌曲会在后台存到本地,下次播放不再消耗流量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("播放") {
                    Toggle("连接 Wi-Fi 时优先播放 MV", isOn: $preferMVOnWiFi)
                    Text("进入后台会自动切回纯音乐流,保持锁屏播放体验")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        PlaybackHistoryView()
                    } label: {
                        Label("播放历史", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
            .navigationTitle("设置")
            .sheet(isPresented: $showLogin) {
                QRLoginView {
                    loggedIn = true
                    showLogin = false
                    Task { await loadUsername() }
                }
            }
            .task {
                await loadUsername()
                await loadFolders()
            }
        }
    }

    private func loadUsername() async {
        guard loggedIn else { return }
        username = try? await BiliClient().myInfo().uname
    }

    private func loadFolders() async {
        guard loggedIn else { return }
        favFolders = (try? await BiliClient().favFolders()) ?? []
    }
}

private struct PlaybackHistoryView: View {
    @Environment(PlayerEngine.self) private var engine
    private var history: PlaybackHistoryStore { .shared }

    var body: some View {
        List {
            ForEach(history.entries) { entry in
                Button {
                    let tracks = history.entries.map(\.track)
                    let index = history.entries.firstIndex(of: entry) ?? 0
                    Task { await engine.play(tracks: tracks, startAt: index) }
                } label: {
                    HStack {
                        TrackRow(track: entry.track, isPlaying: engine.current?.bvid == entry.bvid)
                        Text("\(entry.playCount)次")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        Task { await engine.playRadio(seed: entry.track) }
                    } label: {
                        Label("电台播放", systemImage: PlayerEngine.QueueMode.radio.icon)
                    }
                }
            }
            if !history.entries.isEmpty {
                Button("清空播放历史", role: .destructive) {
                    history.clear()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .navigationTitle("播放历史")
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView("没有播放历史", systemImage: "clock")
            }
        }
    }
}

/// 展示登录二维码并轮询结果,用 B 站手机 App 扫码确认。
struct QRLoginView: View {
    let onSuccess: () -> Void
    @State private var qrImage: UIImage?
    @State private var status = "用 B 站 App 扫一扫"
    @State private var expired = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Text("扫码登录").font(.title2.bold())
            ZStack {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 220, height: 220)
                        .opacity(expired ? 0.2 : 1)
                } else {
                    ProgressView().frame(width: 220, height: 220)
                }
                if expired {
                    Button("已过期,点击刷新") { startLogin() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(status).foregroundStyle(.secondary)
        }
        .padding(40)
        .presentationDetents([.medium])
        .onAppear { startLogin() }
        .onDisappear { pollTask?.cancel() }
    }

    private func startLogin() {
        expired = false
        status = "用 B 站 App 扫一扫"
        pollTask?.cancel()
        pollTask = Task {
            do {
                let client = BiliClient()
                let qr = try await client.qrCodeGenerate()
                qrImage = makeQR(qr.url)
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    switch try await client.qrCodePoll(key: qr.qrcode_key) {
                    case .success(let cookie):
                        CookieStore.cookie = cookie
                        onSuccess()
                        return
                    case .expired:
                        expired = true
                        return
                    case .waiting:
                        continue
                    }
                }
            } catch {
                status = "出错了: \(error.localizedDescription)"
            }
        }
    }

    private func makeQR(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
