import CoreImage.CIFilterBuiltins
import SwiftUI

/// 设置页：账号登录/登出、首页音乐收藏夹、音质、缓存、播放偏好、播放历史入口。
struct SettingsView: View {
    /// 保留旧 key，已有用户升级后无需重新选择收藏夹。
    static let recommendFolderKey = "recommendFolderId"

    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerEngine.self) private var engine
    @State private var loggedIn = CookieStore.isLoggedIn
    @State private var username: String?
    @State private var showLogin = false
    @AppStorage(PlaybackPreferences.autoCacheKey) private var autoCache = true
    @AppStorage(PlaybackPreferences.playbackQualityKey) private var playbackQuality = 30280
    @AppStorage(PlaybackPreferences.downloadQualityKey) private var downloadQuality = 0
    @AppStorage(PlaybackPreferences.preferMVOnWiFiKey) private var preferMVOnWiFi = true
    @AppStorage(TrackTitleFormatter.cleanListTitlesDefaultsKey) private var cleanListTitles = false
    @AppStorage(SettingsView.recommendFolderKey) private var recommendFolderId = 0
    @AppStorage(AudioCDNSelector.preferredHostDefaultsKey) private var preferredAudioCDNHost = ""
    @AppStorage("audioCDNProbeRows") private var audioCDNProbeRowsData = ""
    @State private var favFolders: [BiliClient.FavFolder] = []
    @State private var cdnProbeRows: [AudioCDNProbeRow] = []
    @State private var isTestingCDN = false
    @State private var cdnProbeMessage: String?
    @State private var localAlignerBytes = OnDeviceLyricsAligner.downloadedModelBytes
    @State private var localAlignerBusy = false
    @State private var localAlignerStatus: String?
    @AppStorage(PrecisionLyricsHostConfiguration.overrideURLKey) private var precisionHostURL = ""
    @State private var precisionHostTesting = false
    @State private var precisionHostStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loggedIn {
                        LabeledContent("已登录", value: username ?? "…")
                        Button("退出登录", role: .destructive) {
                            if CookieStore.save(nil) {
                                FavoriteManager.shared.resetForAuthenticationChange()
                                loggedIn = false
                                username = nil
                                favFolders = []
                                recommendFolderId = 0
                            }
                        }
                    } else {
                        Button("扫码登录 B 站账号") { showLogin = true }
                    }
                } header: {
                    Text("账号")
                } footer: {
                    if CookieStore.isExpired {
                        Text("登录已失效，请重新扫码。本地「我喜欢」和已缓存的收藏夹仍可播放。")
                    } else if !loggedIn {
                        Text("登录后可获得更高音质、收藏夹和封面资料库。未登录也可以先把歌曲加入「我喜欢」。")
                    }
                }
                if loggedIn {
                    Section {
                        Picker("首页音乐收藏夹", selection: $recommendFolderId) {
                            Text("默认收藏夹").tag(0)
                            ForEach(favFolders) { folder in
                                Text("\(folder.title)（\(folder.media_count)）").tag(folder.id)
                            }
                        }
                    } header: {
                        Text("音乐资料库")
                    } footer: {
                        Text("首页会用这个收藏夹当旧封面，并混入一批新歌。建议选择一个只保存音乐的收藏夹。")
                    }
                }
                Section {
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
                } header: {
                    Text("音质")
                } footer: {
                    Text("“自动（最高）”会选择账号可用的最高音质，包括可能需要大会员的 Hi-Res。")
                }
                Section {
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
                } header: {
                    Text("CDN 线路")
                } footer: {
                    Text("指定线路仅在本次播放地址包含该 CDN 时优先使用；播放失败或启动缓慢时仍会自动切换备用线路。")
                }
                Section {
                    Toggle("自动缓存播放过的歌曲", isOn: $autoCache)
                } header: {
                    Text("缓存")
                } footer: {
                    Text("在线播放的歌曲会在后台保存到本地，下次播放不再消耗流量。")
                }
                Section {
                    LabeledContent("Qwen3 本机歌词模型") {
                        Text(localAlignerBytes > 0 ? formattedModelSize : "未下载")
                            .foregroundStyle(.secondary)
                    }
                    if localAlignerBusy {
                        HStack {
                            ProgressView()
                            Text(localAlignerStatus ?? "正在删除本机模型")
                                .foregroundStyle(.secondary)
                        }
                    } else if localAlignerBytes > 0 {
                        Button("删除本机歌词模型", role: .destructive) {
                            removeLocalAlignerModel()
                        }
                    }
                    if let localAlignerStatus, !localAlignerBusy {
                        Text(localAlignerStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("本机逐字歌词（已停用）")
                } footer: {
                    Text("真机两次确认 MLX 在 Metal 完成队列触发不可捕获的 SIGABRT，因此不再提供本机生成入口。已有模型可以删除；逐字生成请使用下面的高精度主机。")
                }
                Section {
                    TextField("http://100.78.10.98:8765", text: $precisionHostURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        testPrecisionLyricsHost()
                    } label: {
                        HStack {
                            Label(precisionHostTesting ? "连接中" : "测试主机", systemImage: "desktopcomputer.and.macbook")
                            Spacer()
                            if precisionHostTesting { ProgressView() }
                        }
                    }
                    .disabled(precisionHostTesting || PrecisionLyricsHostConfiguration.baseURL == nil)
                    if let precisionHostStatus {
                        Text(precisionHostStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("高精度逐字歌词主机")
                } footer: {
                    Text(PrecisionLyricsHostConfiguration.accessToken == nil
                        ? "当前构建没有注入访问令牌。地址可留空使用构建默认值；生成只在你主动点击时上传缓存音频。"
                        : "Windows 主机使用人声分离、Qwen 与 WhisperX 双模型共识。只在你主动点击时上传缓存音频，失败不会覆盖现有歌词。")
                }
                Section {
                    Toggle("连接 Wi-Fi 时优先播放 MV", isOn: $preferMVOnWiFi)
                    Toggle("清洗列表标题", isOn: $cleanListTitles)
                    NavigationLink {
                        PlaybackHistoryView()
                    } label: {
                        Label("播放历史", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("播放")
                } footer: {
                    Text("进入后台时 MV 会切回纯音乐流。列表标题清洗只作用于尚未识别的歌曲；已识别的翻唱会显示“翻唱者 · 原唱”。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogin) {
                QRLoginView {
                    FavoriteManager.shared.resetForAuthenticationChange()
                    loggedIn = true
                    showLogin = false
                    Task {
                        await loadUsername()
                        await loadFolders()
                    }
                }
            }
            .task {
                refreshLocalAlignerState()
                loadCDNProbeRows()
                await loadUsername()
                await loadFolders()
            }
            .onReceive(NotificationCenter.default.publisher(for: .biliAuthenticationDidChange)) { _ in
                // CookieStore.isLoggedIn 非响应式:登录态广播后手动同步 @State(只初始化一次)
                loggedIn = CookieStore.isLoggedIn
                if loggedIn {
                    Task {
                        await loadUsername()
                        await loadFolders()
                    }
                } else {
                    username = nil
                    favFolders = []
                }
            }
        }
    }

    private var formattedModelSize: String {
        ByteCountFormatter.string(fromByteCount: localAlignerBytes, countStyle: .file)
    }

    private func refreshLocalAlignerState() {
        localAlignerBytes = OnDeviceLyricsAligner.downloadedModelBytes
    }

    private func prepareLocalAlignerModel() {
        guard !localAlignerBusy else { return }
        localAlignerBusy = true
        localAlignerStatus = "正在下载本机模型"
        Task { @MainActor in
            defer {
                localAlignerBusy = false
                refreshLocalAlignerState()
            }
            do {
                try await OnDeviceLyricsAligner.shared.prepareCompletePipeline { _, message in
                    Task { @MainActor in
                        localAlignerStatus = message.localizedAlignerStatus
                    }
                }
                localAlignerStatus = "模型已就绪"
            } catch {
                localAlignerStatus = error.localizedDescription
            }
        }
    }

    private func removeLocalAlignerModel() {
        guard !localAlignerBusy else { return }
        localAlignerBusy = true
        Task { @MainActor in
            defer {
                localAlignerBusy = false
                refreshLocalAlignerState()
            }
            do {
                try await OnDeviceLyricsAligner.shared.removeDownloadedModel()
                localAlignerStatus = "模型已删除"
            } catch {
                localAlignerStatus = error.localizedDescription
            }
        }
    }

    private func testPrecisionLyricsHost() {
        guard !precisionHostTesting else { return }
        precisionHostTesting = true
        precisionHostStatus = "正在连接..."
        Task { @MainActor in
            defer { precisionHostTesting = false }
            do {
                let milliseconds = try await PrecisionLyricsHostClient.shared.healthCheck()
                precisionHostStatus = "主机在线 · \(milliseconds) ms"
            } catch {
                precisionHostStatus = error.localizedDescription
            }
        }
    }

    /// 登录后拉取并显示用户名。
    private func loadUsername() async {
        if let cached = BiliSessionStore.shared.session.uname, !cached.isEmpty {
            username = cached
        }
        guard loggedIn, let accountID = CookieStore.mid else { return }
        await BiliSessionStore.shared.refreshFromNav()
        if let sessionName = BiliSessionStore.shared.session.uname, !sessionName.isEmpty {
            username = sessionName
            return
        }
        let loadedUsername = try? await BiliClient().myInfo().uname
        guard loggedIn, CookieStore.mid == accountID else { return }
        username = loadedUsername
    }

    /// 拉取收藏夹列表，用于首页音乐资料库选择器。
    private func loadFolders() async {
        guard loggedIn, let accountID = CookieStore.mid else { return }
        do {
            let loadedFolders = try await BiliClient().favFolders()
            guard loggedIn, CookieStore.mid == accountID else { return }
            favFolders = loadedFolders
            // 只在请求成功且确实不含该夹时才重置;请求失败不能把用户的选择误判为「不存在」
            if recommendFolderId != 0,
               !loadedFolders.contains(where: { $0.id == recommendFolderId }) {
                recommendFolderId = 0
            }
        } catch {
            // 请求失败:保留现有选择和列表,下次进入设置页会重试
        }
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
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
    @State private var refreshPrompt: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var loginAttemptID = UUID()

    var body: some View {
        VStack(spacing: 20) {
            Text("扫码登录").font(.title2.bold())
            ZStack {
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 220, height: 220)
                        .opacity(refreshPrompt == nil ? 1 : 0.2)
                } else {
                    ProgressView().frame(width: 220, height: 220)
                }
                if let refreshPrompt {
                    Button(refreshPrompt) { startLogin() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(status).foregroundStyle(.secondary)
        }
        .padding(40)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { startLogin() }
        .onDisappear {
            loginAttemptID = UUID()
            pollTask?.cancel()
        }
    }

    /// 生成二维码并开始轮询扫码结果，成功即存 Cookie 并回调。
    private func startLogin() {
        let attemptID = UUID()
        loginAttemptID = attemptID
        refreshPrompt = nil
        qrImage = nil
        status = "用 B 站 App 扫一扫"
        pollTask?.cancel()
        pollTask = Task {
            do {
                let client = BiliClient()
                let qr = try await client.qrCodeGenerate()
                guard !Task.isCancelled, loginAttemptID == attemptID else { return }
                qrImage = makeQR(qr.url)
                var consecutivePollFailures = 0
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    do {
                        let result = try await client.qrCodePoll(key: qr.qrcode_key)
                        guard !Task.isCancelled, loginAttemptID == attemptID else { return }
                        consecutivePollFailures = 0
                        switch result {
                        case .success(let cookie, let refreshToken, let buvid3):
                            guard CookieStore.save(cookie) else {
                                status = "登录信息无法写入钥匙串"
                                return
                            }
                            BiliSessionStore.shared.adopt(
                                cookie: cookie,
                                refreshToken: refreshToken,
                                buvid3: buvid3)
                            onSuccess()
                            return
                        case .scanned:
                            status = "已扫码，请在手机上确认"
                            continue
                        case .expired:
                            refreshPrompt = "已过期，点击刷新"
                            status = "二维码已过期"
                            return
                        case .waiting:
                            continue
                        }
                    } catch let error as URLError {
                        guard !Task.isCancelled, loginAttemptID == attemptID else { return }
                        // 单次轮询失败(网络抖动)不终止扫码流程:循环顶部的 2s sleep 兼作退避,
                        // 连续 3 次失败才视为过期,露出刷新按钮
                        consecutivePollFailures += 1
                        if consecutivePollFailures >= 3 {
                            refreshPrompt = "网络异常，点击重试"
                            status = "连续轮询失败：\(error.localizedDescription)"
                            return
                        }
                        status = "网络波动，正在重试（\(consecutivePollFailures)/3）"
                    } catch {
                        guard !Task.isCancelled, loginAttemptID == attemptID else { return }
                        refreshPrompt = "登录失败，点击重试"
                        status = error.localizedDescription
                        return
                    }
                }
            } catch {
                guard !Task.isCancelled, loginAttemptID == attemptID else { return }
                refreshPrompt = "加载失败，点击重试"
                status = error.localizedDescription
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
