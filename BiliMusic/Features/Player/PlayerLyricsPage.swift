import SwiftUI

struct PlayerLyricsPage: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var showTranslation: Bool
    @Binding var showSearch: Bool
    @Binding var showImport: Bool
    @Binding var showIdentityEditor: Bool

    @State private var isUserScrolling = false
    @State private var resumeFollowTask: Task<Void, Never>?

    var body: some View {
        lyricsScrollView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDisappear {
                resumeFollowTask?.cancel()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playerLyricsPage")
    }

    @ViewBuilder
    private var lyricsScrollView: some View {
        let shouldAnimate = shouldAnimateWordHighlight
        ZStack(alignment: .top) {
            if engine.lyricsLoading && engine.lyrics.isEmpty {
                ProgressView("正在查找歌词")
                    .foregroundStyle(PlayerSurface.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.lyrics.isEmpty {
                ContentUnavailableView {
                    Label("暂无歌词", systemImage: "quote.bubble")
                } description: {
                    Text(engine.lyricSearchError ?? "自动匹配失败，可以手动选择歌词来源。")
                } actions: {
                    Button("手动搜索") { showSearch = true }
                        .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(PlayerSurface.textPrimary)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { _ in
                    lyricsTimelineContent(time: lyricTime())
                }
            }

            if let banner = engine.lyricsBanner {
                Text(banner)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityIdentifier("lyricsVersionBanner")
            }

            if isUserScrolling {
                Button {
                    resumeFollowNow()
                } label: {
                    Text("回到当前句")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityIdentifier("lyricsResumeButton")
            }
        }
    }

    private func lyricsTimelineContent(time: Double) -> some View {
        let activeIndex = activeLineIndex(at: time)
        let activeIndices = Set(LyricHighlightModel.highlightedLineIndices(lines: engine.lyrics, at: time))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(engine.lyrics.enumerated()), id: \.element.id) { index, line in
                        lyricRow(
                            line,
                            index: index,
                            isActive: activeIndices.contains(index),
                            time: time)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 96)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.13),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        userBeganScrolling()
                    }
                    .onEnded { _ in
                        userEndedScrolling()
                    }
            )
            .onChange(of: activeIndex) { _, index in
                guard !isUserScrolling,
                      engine.lyricsFollowPlayback,
                      let index,
                      let line = engine.lyrics[safe: index] else { return }
                animateScroll {
                    proxy.scrollTo(line.id, anchor: .center)
                }
            }
            .onChange(of: isUserScrolling) { _, scrolling in
                guard !scrolling,
                      engine.lyricsFollowPlayback,
                      let index = activeIndex,
                      let line = engine.lyrics[safe: index] else { return }
                animateScroll {
                    proxy.scrollTo(line.id, anchor: .center)
                }
            }
            .task(id: engine.lyricsDocument?.result.stableID) {
                guard engine.lyricsFollowPlayback,
                      let index = activeIndex,
                      let line = engine.lyrics[safe: index] else { return }
                proxy.scrollTo(line.id, anchor: .center)
            }
        }
    }

    private func lyricRow(_ line: PlayerEngine.LyricLine, index: Int, isActive: Bool, time: Double) -> some View {
        Button {
            engine.seek(to: line)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                lineText(line, index: index, isActive: isActive, time: time)
                    .font(.system(
                        size: line.voiceRole.isSecondary ? 20 : 26,
                        weight: line.voiceRole.isSecondary ? .semibold : .bold))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showTranslation,
                   let translation = line.translation,
                   !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PlayerSurface.textPrimary.opacity(isActive ? 0.72 : 1))
                        .opacity(isActive ? 1 : 0.35)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .opacity(isActive && line.words.isEmpty
                ? (line.voiceRole.isSecondary ? 0.74 : 1)
                : (isActive ? (line.voiceRole.isSecondary ? 0.8 : 1) : 0.35))
            .scaleEffect(isActive && !line.voiceRole.isSecondary ? 1.02 : 1, anchor: .leading)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: isActive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line.voiceRole.isSecondary ? "和声，\(line.text)" : line.text)
        .accessibilityHint("跳转到这句歌词")
    }

    @ViewBuilder
    private func lineText(_ line: PlayerEngine.LyricLine, index: Int, isActive: Bool, time: Double) -> some View {
        if isActive, !line.words.isEmpty {
            let states = LyricHighlightModel.wordStates(of: line, at: time)
            let words = line.words.sorted { lhs, rhs in
                if lhs.from == rhs.from { return lhs.to < rhs.to }
                return lhs.from < rhs.from
            }
            KaraokeWordLine(lineIndex: index, lineText: line.text, words: words, states: states)
        } else {
            let aiScore = LyricEmbellishmentStore.shared.score(
                for: engine.current?.key.description ?? "",
                lyricsHash: LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
            )
            let style = isActive ? LyricEmbellishmentDirector.embellishment(
                forLine: line.text,
                lineIndex: index,
                isSecondary: line.voiceRole.isSecondary,
                aiScore: aiScore
            ) : .none
            Text(line.text)
                .foregroundStyle(PlayerSurface.textPrimary)
                .lyricEmbellishment(
                    style: style,
                    state: isActive ? .current(progress: 0.5) : .unsung,
                    reduceMotion: reduceMotion
                )
        }
    }

    private var shouldAnimateWordHighlight: Bool {
        guard !reduceMotion, engine.state == .playing else { return false }
        let indices = LyricHighlightModel.activeLineIndices(
            lines: engine.lyrics,
            at: engine.adjustedLyricTime)
        return indices.contains { index in
            engine.lyrics[safe: index]?.words.isEmpty == false
        }
    }

    private func lyricTime() -> Double {
        if shouldAnimateWordHighlight, let seconds = engine.avPlayer?.currentTime().seconds, seconds.isFinite {
            return seconds + Double(engine.lyricOffsetMilliseconds) / 1000
        }
        return engine.adjustedLyricTime
    }

    private func activeLineIndex(at time: Double) -> Int? {
        guard engine.lyricsFollowPlayback else { return nil }
        return LyricHighlightModel.activeLineIndex(lines: engine.lyrics, at: time)
    }

    private func userBeganScrolling() {
        isUserScrolling = true
        resumeFollowTask?.cancel()
    }

    private func userEndedScrolling() {
        resumeFollowTask?.cancel()
        resumeFollowTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            resumeFollowNow()
        }
    }

    private func resumeFollowNow() {
        resumeFollowTask?.cancel()
        isUserScrolling = false
    }

    private func animateScroll(_ updates: @escaping () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8), updates)
        }
    }
}

private struct KaraokeWordLine: View {
    let lineIndex: Int
    let lineText: String
    let words: [PlayerEngine.LyricWord]
    let states: [LyricWordState]
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let aiScore = LyricEmbellishmentStore.shared.score(
            for: engine.current?.key.description ?? "",
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
        )
        LyricWordWrapLayout(alignment: .leading) {
            ForEach(Array(zip(words, states).enumerated()), id: \.offset) { item in
                let word = item.element.0
                let state = item.element.1
                let style = LyricEmbellishmentDirector.embellishment(
                    forWord: word.text,
                    lineIndex: lineIndex,
                    wordIndex: item.offset,
                    lineText: lineText,
                    aiScore: aiScore
                )
                KaraokeWordToken(
                    text: word.text,
                    state: state,
                    style: style,
                    reduceMotion: reduceMotion
                )
            }
        }
        .accessibilityRepresentation {
            Text(words.map(\.text).joined())
                .accessibilityIdentifier("lyricsKaraokeWordLine")
        }
    }
}

private struct KaraokeWordToken: View {
    let text: String
    let state: LyricWordState
    let style: LyricEmbellishmentStyle
    let reduceMotion: Bool

    var body: some View {
        Text(text)
            .foregroundStyle(PlayerSurface.lyricUnsung)
            .overlay(alignment: .leading) {
                if fillProgress > 0 {
                    Text(text)
                        .foregroundStyle(PlayerSurface.textPrimary)
                        .mask(alignment: .leading) {
                            GeometryReader { geometry in
                                Rectangle()
                                    .frame(width: geometry.size.width * fillProgress)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .blur(radius: 0.65)
                            }
                        }
                }
            }
            .lyricEmbellishment(style: style, state: state, reduceMotion: reduceMotion)
            .shadow(
                color: isCurrent ? PlayerSurface.textPrimary.opacity(0.22) : .clear,
                radius: isCurrent ? 5 : 0)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var fillProgress: CGFloat {
        CGFloat(LyricHighlightModel.fillProgress(for: state))
    }

    private var isCurrent: Bool {
        if case .current = state { return true }
        return false
    }
}

struct PlayerLyricsOverflowMenu: View {
    @Environment(PlayerEngine.self) private var engine
    @Binding var showTranslation: Bool
    @Binding var showSearch: Bool
    @Binding var showImport: Bool
    @Binding var showIdentityEditor: Bool
    @Binding var showOffset: Bool

    var body: some View {
        Menu {
            if engine.lyrics.contains(where: { $0.translation?.isEmpty == false }) {
                Button(showTranslation ? "隐藏翻译" : "显示翻译") {
                    showTranslation.toggle()
                }
            }

            Button("歌词校准") {
                showOffset = true
            }

            Divider()

            Button("✨ 露娜智能装帧（微巧思）") {
                Task {
                    guard let track = engine.current, !engine.lyrics.isEmpty else { return }
                    if let score = try? await LyricEmbellishmentClient.shared.embellish(track: track, lines: engine.lyrics) {
                        LyricEmbellishmentStore.shared.save(score)
                    }
                }
            }

            if LyricEmbellishmentStore.shared.score(
                for: engine.current?.key.description ?? "",
                lyricsHash: LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
            ) != nil {
                Button("恢复本地规则微巧思") {
                    if let trackID = engine.current?.key.description {
                        LyricEmbellishmentStore.shared.remove(for: trackID)
                    }
                }
            }

            Divider()

            Button("重新识别歌曲") {
                Task { await engine.refreshTrackIdentity() }
            }
            Button("搜索翻唱者版本") {
                Task { await engine.searchLyrics(scope: .coverVersion) }
            }
            Button("搜索原唱歌词") {
                Task { await engine.searchLyrics(scope: .originalRecording) }
            }
            Button("手动搜索候选…") {
                showSearch = true
            }

            Button("导入本地歌词") {
                showImport = true
            }
            Button("手动修正歌曲身份") {
                showIdentityEditor = true
            }

            if engine.lyricsDocument?.versionScope == .canonicalOriginal {
                Button("这份歌词适用于当前翻唱版本") {
                    Task { await engine.confirmCurrentLyricsApplyToCover() }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PlayerSurface.controlIdle)
                .frame(width: 46, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多")
        .accessibilityIdentifier("lyricsMoreMenu")
    }
}
