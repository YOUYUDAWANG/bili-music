import CoreImage.CIFilterBuiltins
import SwiftUI

/// 设置页：账号登录/登出、推荐种子夹、音质、缓存、播放偏好、播放历史入口。
struct SettingsView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var loggedIn = CookieStore.isLoggedIn
    @State private var username: String?
    @State private var showLogin = false
    @AppStorage("autoCache") private var autoCache = false
    @AppStorage("playbackQuality") private var playbackQuality = 0
    @AppStorage("downloadQuality") private var downloadQuality = 0
    @AppStorage("preferMVOnWiFi") private var preferMVOnWiFi = true
    @AppStorage("recommendFolderId") private var recommendFolderId = 0
    @AppStorage(AudioCDNSelector.preferredHostDefaultsKey) private var preferredAudioCDNHost = ""
    @AppStorage("audioCDNProbeRows") private var audioCDNProbeRowsData = ""
    @State private var favFolders: [BiliClient.FavFolder] = []
    @State private var cdnProbeRows: [AudioCDNProbeRow] = []
    @State private var isTestingCDN = false
    @State private var cdnProbeMessage: String?

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
                        ForEach(BiliClient.qualityOptions, id: \.id) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    Picker("下载音质", selection: $downloadQuality) {
                        ForEach(BiliClient.qualityOptions, id: \.id) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    Text("\"自动(最高)\"含 Hi-Res 无损(需大会员);流量紧张选低档")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("CDN 线路") {
                    Picker("音频 CDN", selection: $preferredAudioCDNHost) {
                        Text("自动").tag("")
                        if !preferredAudioCDNHost.isEmpty,
                           !cdnProbeRows.contains(where: { $0.host == preferredAudioCDNHost }) {
                            Text(preferredAudioCDNHost).tag(preferredAudioCDNHost)
                        }
                        ForEach(cdnProbeRows.filter(\.reachable)) { row in
                            Text(row.pickerTitle).tag(row.host)
                        }
                    }
                    Button {
                        Task { await runCDNProbe() }
                    } label: {
                        HStack {
                            Label(isTestingCDN ? "测速中" : "测速", systemImage: "speedometer")
                            Spacer()
                            if isTestingCDN {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTestingCDN)
                    if let cdnProbeMessage {
                        Text(cdnProbeMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(cdnProbeRows) { row in
                        Button {
                            guard row.reachable else { return }
                            preferredAudioCDNHost = row.host
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: row.reachable ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(row.reachable ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.host)
                                        .lineLimit(1)
                                    Text(row.measuredAtText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.latencyText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(row.reachable ? .primary : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!row.reachable)
                    }
                    Text("选择某个 host 后,若本次 playurl 返回该 CDN 会优先使用;播放失败或慢启动仍会自动切换备用线路")
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
                loadCDNProbeRows()
                await loadUsername()
                await loadFolders()
            }
        }
    }

    /// 登录后拉取并显示用户名。
    private func loadUsername() async {
        guard loggedIn else { return }
        username = try? await BiliClient().myInfo().uname
    }

    /// 拉取收藏夹列表，用于「推荐种子收藏夹」选择器。
    private func loadFolders() async {
        guard loggedIn else { return }
        favFolders = (try? await BiliClient().favFolders()) ?? []
    }

    private func runCDNProbe() async {
        guard !isTestingCDN else { return }
        isTestingCDN = true
        cdnProbeMessage = "正在获取候选线路..."
        defer { isTestingCDN = false }

        guard let track = await cdnProbeTrack() else {
            cdnProbeMessage = "先播放一首歌后再测速"
            return
        }

        do {
            let cid: Int
            if let trackCID = track.cid {
                cid = trackCID
            } else if let page = try await BiliClient().pageList(bvid: track.bvid).first {
                cid = page.cid
            } else {
                throw BiliClient.APIError(code: -1, message: "无分P")
            }

            let stream = try await BiliClient().audioStream(
                bvid: track.bvid,
                cid: cid,
                preferredQuality: playbackQuality)
            let measurements = await AudioCDNSelector.measureCandidates(
                from: stream.candidateURLs,
                timeout: .milliseconds(1400),
                maxConcurrentProbes: 8)
            let rows = measurements.map {
                AudioCDNProbeRow(
                    host: $0.host,
                    milliseconds: $0.milliseconds,
                    reachable: $0.reachable,
                    measuredAt: Date())
            }
            cdnProbeRows = rows
            saveCDNProbeRows()
            if let fastest = rows.first(where: \.reachable) {
                cdnProbeMessage = "最快线路: \(fastest.host)"
            } else {
                cdnProbeMessage = "没有可用线路,播放仍会使用 B 站默认地址"
            }
        } catch {
            cdnProbeMessage = "测速失败: \(error.localizedDescription)"
        }
    }

    private func cdnProbeTrack() async -> Track? {
        if let current = engine.current {
            return current
        }
        await PlaybackHistoryStore.shared.loadIfNeeded()
        return PlaybackHistoryStore.shared.entries.first?.track
    }

    private func loadCDNProbeRows() {
        guard let data = audioCDNProbeRowsData.data(using: .utf8),
              let rows = try? JSONDecoder().decode([AudioCDNProbeRow].self, from: data) else {
            cdnProbeRows = []
            return
        }
        cdnProbeRows = rows
    }

    private func saveCDNProbeRows() {
        guard let data = try? JSONEncoder().encode(cdnProbeRows),
              let raw = String(data: data, encoding: .utf8) else { return }
        audioCDNProbeRowsData = raw
    }
}

private struct AudioCDNProbeRow: Identifiable, Codable, Equatable {
    let host: String
    let milliseconds: Double?
    let reachable: Bool
    let measuredAt: Date

    var id: String { host }

    var pickerTitle: String {
        "\(host) \(latencyText)"
    }

    var latencyText: String {
        guard reachable, let milliseconds else { return "失败" }
        return "\(Int(milliseconds.rounded())) ms"
    }

    var measuredAtText: String {
        measuredAt.formatted(date: .omitted, time: .shortened)
    }
}

/// 播放历史页：点击重播、可清空。
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
                        TrackRow(track: entry.track, isPlaying: engine.current.map { entry.track.key.matches($0) } ?? false)
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
        .task {
            await history.loadIfNeeded()
        }
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

    /// 生成二维码并开始轮询扫码结果，成功即存 Cookie 并回调。
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

    /// 把登录 URL 渲染成二维码图片。
    private func makeQR(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
