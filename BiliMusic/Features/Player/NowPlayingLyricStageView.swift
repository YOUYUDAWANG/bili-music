import SwiftUI

/// 播放主页中区高能歌词光场舞台 (NowPlaying Lyric Stage)
/// 融合四大场景动态编舞语法 (Assemble / Gravity / Duet / Cosmic Drift) 与露娜 AI 艺术总监
struct NowPlayingLyricStageView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var lunaMood: String? = nil
    @State private var isLunaLoading: Bool = false

    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isTimelineActive)) { _ in
                let time = currentLyricTime
                let currentSnapshot = snapshot(at: time)
                let interlude = isInterludeActive(at: time)

                stageContainer(snapshot: currentSnapshot, interlude: interlude, time: time)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: trackLyricsFingerprint) {
            await fetchLunaEmbellishmentsIfNeeded()
        }
        .accessibilityLabel(snapshot(at: currentLyricTime)?.current?.text ?? "当前暂无歌词")
        .accessibilityHint("打开完整歌词")
        .accessibilityIdentifier("nowPlayingLyricStageView")
    }

    private var trackLyricsFingerprint: String {
        "\(engine.current?.key.description ?? "")-\(LyricPerformanceFingerprint.lyricsHash(engine.lyrics))"
    }

    // MARK: - Stage Container

    @ViewBuilder
    private func stageContainer(snapshot: StageSnapshot?, interlude: Bool, time: Double) -> some View {
        ZStack {
            // 1. 动态封面三元流体极光 (Top / Middle / Bottom 呼吸共鸣)
            if isActive, engine.state == .playing, !reduceMotion {
                LyricStageLightField(
                    palette: engine.currentArtworkPalette,
                    isCurrentActive: snapshot?.current != nil
                )
            }

            // 2. 歌词三层景深与核心舞台
            if let snapshot {
                stageContent(snapshot: snapshot, time: time)
                    .id(snapshot.current?.id ?? snapshot.next?.id ?? UUID())
                    .transition(stageTransition)
            } else if interlude {
                // 3. 前奏与长间奏律动呼吸指示器
                LyricInterludePulseView(reduceMotion: reduceMotion)
                    .transition(.opacity)
            } else {
                // 4. 空歌词优雅占位
                Text("暂无歌词")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PlayerSurface.textTertiary)
            }
        }
        .animation(stageAnimation, value: snapshot?.current?.id)
    }

    private var stageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        } else {
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        }
    }

    private var stageAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.76)
    }

    // MARK: - Luna Auto Fetch

    private func fetchLunaEmbellishmentsIfNeeded() async {
        guard let track = engine.current, !engine.lyrics.isEmpty else {
            lunaMood = nil
            return
        }
        let trackID = track.key.description
        let lyricsHash = LyricPerformanceFingerprint.lyricsHash(engine.lyrics)

        // 1. 先查本地缓存
        if let existing = LyricEmbellishmentStore.shared.score(for: trackID, lyricsHash: lyricsHash) {
            lunaMood = existing.mood
            return
        }

        // 2. 自动在后台向 Luna 发送轻量装帧请求
        isLunaLoading = true
        do {
            let score = try await LyricEmbellishmentClient.shared.embellish(track: track, lines: engine.lyrics)
            LyricEmbellishmentStore.shared.save(score)
            lunaMood = score.mood
        } catch {
            lunaMood = nil
        }
        isLunaLoading = false
    }

    // MARK: - Stage Content Layout

    @ViewBuilder
    private func stageContent(snapshot: StageSnapshot, time: Double) -> some View {
        VStack(spacing: 14) {
            // 露娜 AI 情绪标签微徽章
            if let mood = lunaMood, !mood.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text("Luna · \(mood)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PlayerSurface.textSecondary.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(.ultraThinMaterial.opacity(0.55), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            // A. 前一句 (Past Context: 景深散焦微暗)
            if let previous = snapshot.previous {
                Text(previous.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PlayerSurface.textSecondary)
                    .opacity(0.35)
                    .blur(radius: 0.8)
                    .lineLimit(1)
                    .frame(maxWidth: 340, alignment: .leading)
            }

            // B. 核心唱词 (Hero Present Line: 四大场景编舞 + 实时流光 / 字级动效)
            if let current = snapshot.current {
                heroCurrentLine(current, index: snapshot.currentIndex, time: time)
                    .frame(maxWidth: 340, alignment: frameAlignment(for: current.voiceRole))
            } else if let upcoming = snapshot.next {
                // 预备句
                Text(upcoming.text)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(PlayerSurface.textPrimary)
                    .opacity(0.65)
                    .lineLimit(2)
                    .frame(maxWidth: 340, alignment: .leading)
            }

            // C. 下一句 (Future Context: 预备半透明)
            if snapshot.current != nil, let next = snapshot.next {
                Text(next.text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PlayerSurface.textSecondary)
                    .opacity(0.48)
                    .lineLimit(1)
                    .frame(maxWidth: 340, alignment: .leading)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Hero Current Line

    @ViewBuilder
    private func heroCurrentLine(_ line: PlayerEngine.LyricLine, index: Int, time: Double) -> some View {
        let aiScore = LyricEmbellishmentStore.shared.score(
            for: engine.current?.key.description ?? "",
            lyricsHash: LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
        )
        let fontSize = heroFontSize(for: line.text)
        let elapsed = max(0, time - line.from)
        let sceneMode = LyricCinematicSceneMode.resolve(
            for: line,
            index: index,
            aiMood: lunaMood,
            totalLines: engine.lyrics.count
        )

        VStack(alignment: alignment(for: line.voiceRole), spacing: 6) {
            // 多声部标识 (二重唱从右边进，和声居中，主唱从左边进)
            if line.voiceRole.isSecondary {
                Text(line.voiceRole == .backing ? "和声" : "二重唱")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(line.voiceRole == .backing ? Color.orange : Color.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background((line.voiceRole == .backing ? Color.orange : Color.cyan).opacity(0.18), in: Capsule())
            }

            if !line.words.isEmpty {
                // 1. 逐字时间轴模式 (Word-Timed Karaoke + 四大分镜编舞 + 字级 VFX)
                let items = buildWordItems(for: line, at: time)
                LyricWordWrapLayout(alignment: motionAlignment(for: line.voiceRole)) {
                    ForEach(items) { item in
                        let style = LyricEmbellishmentDirector.embellishment(
                            forWord: item.word.text,
                            lineIndex: index,
                            wordIndex: item.index,
                            lineText: line.text,
                            aiScore: aiScore
                        )

                        StaggeredWordToken(
                            word: item.word,
                            wordIndex: item.index,
                            state: item.state,
                            style: style,
                            fontSize: fontSize,
                            alignment: textAlignment(for: line.voiceRole),
                            sceneMode: sceneMode,
                            elapsed: elapsed,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            } else {
                // 2. 整行时间轴模式 (Line-Timed Fluid Liquid Sweep + 流光探针)
                let style = LyricEmbellishmentDirector.embellishment(
                    forLine: line.text,
                    lineIndex: index,
                    isSecondary: line.voiceRole.isSecondary,
                    aiScore: aiScore
                )
                LyricVFXLineView(
                    line: line,
                    time: time,
                    style: style,
                    fontSize: fontSize,
                    reduceMotion: reduceMotion
                )
            }

            // 3. 伴随翻译歌词 (优雅同步淡入)
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PlayerSurface.textPrimary.opacity(0.70))
                    .frame(maxWidth: .infinity, alignment: frameAlignment(for: line.voiceRole))
                    .transition(.opacity)
            }
        }
    }

    private struct WordItem: Identifiable {
        let id: Int
        let index: Int
        let word: PlayerEngine.LyricWord
        let state: LyricWordState
    }

    private func buildWordItems(for line: PlayerEngine.LyricLine, at time: Double) -> [WordItem] {
        let states = LyricHighlightModel.wordStates(of: line, at: time)
        let words = line.words.sorted { lhs, rhs in
            lhs.from == rhs.from ? lhs.to < rhs.to : lhs.from < rhs.from
        }
        return zip(words, states).enumerated().map { index, pair in
            WordItem(id: index, index: index, word: pair.0, state: pair.1)
        }
    }

    private func heroFontSize(for text: String) -> CGFloat {
        let count = text.count
        if count <= 8 { return 30 }
        if count <= 16 { return 26 }
        return 22
    }

    private func frameAlignment(for voiceRole: LyricVoiceRole) -> Alignment {
        switch voiceRole {
        case .duetB, .backing: return .trailing
        case .duetA: return .leading
        default: return .leading
        }
    }

    private func alignment(for voiceRole: LyricVoiceRole) -> HorizontalAlignment {
        switch voiceRole {
        case .duetB, .backing: return .trailing
        case .duetA: return .leading
        default: return .leading
        }
    }

    private func motionAlignment(for voiceRole: LyricVoiceRole) -> LyricMotionAlignment {
        switch voiceRole {
        case .duetB, .backing: return .trailing
        case .duetA: return .leading
        default: return .leading
        }
    }

    private func textAlignment(for voiceRole: LyricVoiceRole) -> TextAlignment {
        switch voiceRole {
        case .duetB, .backing: return .trailing
        case .duetA: return .leading
        default: return .leading
        }
    }

    private var isTimelineActive: Bool {
        isActive && engine.state == .playing && scenePhase == .active
    }

    private var currentLyricTime: Double {
        if let playerTime = engine.avPlayer?.currentTime().seconds, playerTime.isFinite {
            return playerTime + Double(engine.lyricOffsetMilliseconds) / 1000.0
        }
        return engine.adjustedLyricTime
    }

    // MARK: - Snapshot Model

    private struct StageSnapshot {
        let previous: PlayerEngine.LyricLine?
        let current: PlayerEngine.LyricLine?
        let currentIndex: Int
        let next: PlayerEngine.LyricLine?
    }

    private func snapshot(at time: Double) -> StageSnapshot? {
        guard engine.playbackMode != .mv,
              engine.lyricsFollowPlayback,
              !engine.lyrics.isEmpty else { return nil }

        let activeIndices = LyricHighlightModel.activeLineIndices(lines: engine.lyrics, at: time)
        let activeIndex = activeIndices.isEmpty
            ? nil
            : LyricHighlightModel.activeLineIndex(lines: engine.lyrics, at: time)

        if let activeIndex, let current = engine.lyrics[safe: activeIndex] {
            let previous = activeIndex > 0 ? engine.lyrics[safe: activeIndex - 1] : nil
            let next = engine.lyrics[safe: activeIndex + 1]
            return StageSnapshot(
                previous: previous,
                current: current,
                currentIndex: activeIndex,
                next: next
            )
        }

        // 间奏或前奏中，预备下一句
        if let nextIndex = engine.lyrics.firstIndex(where: { $0.from > time }),
           let next = engine.lyrics[safe: nextIndex] {
            let previous = nextIndex > 0 ? engine.lyrics[safe: nextIndex - 1] : nil
            return StageSnapshot(
                previous: previous,
                current: nil,
                currentIndex: nextIndex,
                next: next
            )
        }

        return nil
    }

    private func isInterludeActive(at time: Double) -> Bool {
        guard engine.playbackMode != .mv, !engine.lyrics.isEmpty else { return false }
        if let first = engine.lyrics.first, time < first.from - 2.0 {
            return true
        }
        return false
    }
}

// MARK: - Staggered Word Assembly with Scene Modes

private struct StaggeredWordToken: View {
    let word: PlayerEngine.LyricWord
    let wordIndex: Int
    let state: LyricWordState
    let style: LyricEmbellishmentStyle
    let fontSize: CGFloat
    let alignment: TextAlignment
    let sceneMode: LyricCinematicSceneMode
    let elapsed: Double
    let reduceMotion: Bool

    var body: some View {
        let dynamics = computeDynamics()

        LyricVFXWordToken(
            text: word.text,
            state: state,
            style: style,
            fontSize: fontSize,
            alignment: alignment,
            reduceMotion: reduceMotion
        )
        .scaleEffect(dynamics.scale, anchor: .center)
        .offset(x: dynamics.offsetX, y: dynamics.offsetY)
        .blur(radius: dynamics.blur)
        .opacity(dynamics.opacity)
    }

    private struct WordDynamics {
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        let blur: CGFloat
        let opacity: Double
    }

    private func computeDynamics() -> WordDynamics {
        guard !reduceMotion else {
            return WordDynamics(scale: 1.0, offsetX: 0, offsetY: 0, blur: 0, opacity: 1.0)
        }

        let staggerDelay = Double(wordIndex) * 0.035
        let settleProgress = min(1.0, max(0, (elapsed - staggerDelay) / 0.28))

        switch sceneMode {
        case .gravity:
            // 重力下坠模式：自上方落体碰撞 (Drop bounce)
            let drop = bounceOut(settleProgress)
            let scaleY: CGFloat = 0.85 + 0.15 * CGFloat(drop)
            let offsetY: CGFloat = CGFloat(-24.0 * (1.0 - drop))
            return WordDynamics(
                scale: scaleY,
                offsetX: 0,
                offsetY: offsetY,
                blur: CGFloat((1.0 - settleProgress) * 1.5),
                opacity: min(1.0, settleProgress * 2.0)
            )

        case .cosmicDrift:
            // 星海浮游模式：轻柔双轴起伏微浮游
            let driftX = CGFloat(sin(elapsed * 1.4 + Double(wordIndex) * 0.6) * 1.6)
            let driftY = CGFloat(cos(elapsed * 1.8 + Double(wordIndex) * 0.8) * 1.8)
            let scale: CGFloat = 0.92 + 0.08 * CGFloat(backOut(settleProgress))
            return WordDynamics(
                scale: scale,
                offsetX: driftX,
                offsetY: driftY,
                blur: CGFloat((1.0 - settleProgress) * 1.2),
                opacity: min(1.0, settleProgress * 1.8)
            )

        case .duet:
            // 对唱模式：平滑横向滑入
            let slideX = CGFloat((1.0 - backOut(settleProgress)) * 12.0)
            return WordDynamics(
                scale: 0.90 + 0.10 * CGFloat(backOut(settleProgress)),
                offsetX: slideX,
                offsetY: 0,
                blur: CGFloat((1.0 - settleProgress) * 1.5),
                opacity: min(1.0, settleProgress * 1.8)
            )

        case .assemble:
            // 构筑凝聚模式：弹性过冲与散焦聚焦
            let settleScale: CGFloat = CGFloat(0.85 + 0.15 * backOut(settleProgress))
            let settleOffsetY: CGFloat = CGFloat((1.0 - settleProgress) * 6.0)
            let settleBlur: CGFloat = CGFloat((1.0 - settleProgress) * 2.0)
            return WordDynamics(
                scale: settleScale,
                offsetX: 0,
                offsetY: settleOffsetY,
                blur: settleBlur,
                opacity: min(1.0, settleProgress * 1.5)
            )
        }
    }

    private func backOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1) - 1
        let s = 1.70158
        return 1 + (s + 1) * x * x * x + s * x * x
    }

    private func bounceOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        let base = 7.5625
        let step = 2.75
        if x < 1 / step { return base * x * x }
        if x < 2 / step {
            let shifted = x - 1.5 / step
            return base * shifted * shifted + 0.75
        }
        if x < 2.5 / step {
            let shifted = x - 2.25 / step
            return base * shifted * shifted + 0.9375
        }
        let shifted = x - 2.625 / step
        return base * shifted * shifted + 0.984375
    }
}

// MARK: - Triple-Lobe Fluid Aurora Ambient Light Field

private struct LyricStageLightField: View {
    let palette: PlayerArtworkPalette
    let isCurrentActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let pulse = sin(phase * 1.6) * 0.06
            let drift = cos(phase * 1.2) * 10
            ZStack {
                // 1. 封面 Top 色流体光斑 (左上方极光)
                RadialGradient(
                    colors: [
                        Color(uiColor: palette.top).opacity(isCurrentActive ? (0.28 + pulse) : 0.08),
                        Color(uiColor: palette.top).opacity(0.06),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 200
                )
                .frame(maxWidth: 360, maxHeight: 220)
                .offset(x: -drift, y: drift * 0.5)
                .blur(radius: 28)

                // 2. 封面 Middle 色流体光斑 (中心呼吸极光)
                RadialGradient(
                    colors: [
                        Color(uiColor: palette.middle).opacity(isCurrentActive ? (0.20 + pulse * 0.8) : 0.05),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 30,
                    endRadius: 180
                )
                .frame(maxWidth: 320, maxHeight: 180)
                .blur(radius: 26)

                // 3. 封面 Bottom 色流体光斑 (右下方极光)
                RadialGradient(
                    colors: [
                        Color(uiColor: palette.bottom).opacity(isCurrentActive ? (0.22 + pulse * 0.7) : 0.06),
                        Color.clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 30,
                    endRadius: 220
                )
                .frame(maxWidth: 360, maxHeight: 220)
                .offset(x: drift, y: -drift * 0.5)
                .blur(radius: 32)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Instrumental Interlude Indicator

struct LyricInterludePulseView: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = sin((time * 2.2) - Double(index) * 0.75)
                    let scale = reduceMotion ? 1.0 : (0.8 + max(0, phase) * 0.45)
                    let opacity = reduceMotion ? 0.6 : (0.3 + max(0, phase) * 0.65)
                    Circle()
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 7, height: 7)
                        .scaleEffect(scale)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.4), in: Capsule())
            .accessibilityHidden(true)
        }
    }
}
