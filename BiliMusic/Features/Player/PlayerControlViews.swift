import AVKit
import SwiftUI

// MARK: - Playback Controls

struct PlayerIconButton: View {
    let systemName: String
    let size: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ActionSymbolButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
        .accessibilityLabel(title)
    }
}

struct ActionSymbolLabel: View {
    let title: String
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel(title)
    }
}

struct PlayerToolbarActionButton: View {
    let title: String
    let systemName: String
    var isActive = false
    var isEnabled = true
    var isBusy = false
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isBusy else { return }
            action()
        } label: {
            PlayerToolbarActionVisual(
                title: title,
                systemName: systemName,
                isActive: isActive,
                isEnabled: isEnabled,
                isBusy: isBusy
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? (isActive ? "已开启" : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifierIfPresent(accessibilityIdentifier)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifierIfPresent(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

struct PlayerToolbarActionLabel: View {
    let title: String
    let systemName: String
    var isActive = false
    var isEnabled = true
    var isBusy = false
    var accessibilityLabel: String? = nil
    var accessibilityValue: String? = nil

    var body: some View {
        PlayerToolbarActionVisual(
            title: title,
            systemName: systemName,
            isActive: isActive,
            isEnabled: isEnabled,
            isBusy: isBusy
        )
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityValue ?? (isActive ? "已开启" : ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct PlayerToolbarActionVisual: View {
    let title: String
    let systemName: String
    let isActive: Bool
    let isEnabled: Bool
    let isBusy: Bool

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(foregroundColor)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 19, weight: isActive ? .semibold : .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 46, height: 38)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1 : 0.34)
        .contentShape(Circle())
    }

    private var foregroundColor: Color {
        guard isEnabled else { return PlayerSurface.controlDisabled }
        return isActive ? PlayerSurface.controlStrong : PlayerSurface.controlIdle
    }
}

// MARK: - Progress Bar

/// 进度条独立成视图,把对 `engine.currentTime` 的订阅限制在这里。
/// scrub 状态也只在本视图持有,避免拖动时反复刷新外层播放器。
struct PlayerProgressBar: View {
    @Environment(PlayerEngine.self) private var engine
    var onScrubChanged: (Bool) -> Void = { _ in }
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var scrubHapticTrigger = 0

    private enum Metrics {
        static let horizontalPadding: CGFloat = 30
        static let sliderHeight: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: progressBinding,
                in: 0...max(engine.duration, 1),
                onEditingChanged: handleEditingChanged
            )
            .sliderThumbVisibility(.hidden)
            .tint(PlayerSurface.textPrimary)
            .frame(height: Metrics.sliderHeight)
            .sensoryFeedback(.intent(.selection), trigger: scrubHapticTrigger)

            HStack {
                Text(MusicFormatters.playbackTime(isScrubbing ? scrubValue : engine.currentTime))
                Spacer()
                Text(MusicFormatters.playbackTime(engine.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(PlayerSurface.textTertiary)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue(
            "\(MusicFormatters.playbackTime(isScrubbing ? scrubValue : engine.currentTime)) / \(MusicFormatters.playbackTime(engine.duration))"
        )
        .accessibilityIdentifier("nowPlayingProgress")
        .onDisappear {
            guard isScrubbing else { return }
            engine.endScrub(to: scrubValue)
            isScrubbing = false
            onScrubChanged(false)
        }
        .onChange(of: engine.current?.key) { oldKey, newKey in
            if let oldKey, let newKey, oldKey.isCIDEnrichment(to: newKey) {
                return
            }
            guard isScrubbing else { return }
            isScrubbing = false
            onScrubChanged(false)
        }
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                isScrubbing
                    ? scrubValue
                    : ProgressScrubMath.clampedTime(engine.currentTime, duration: engine.duration)
            },
            set: { value in
                scrubValue = ProgressScrubMath.clampedTime(value, duration: engine.duration)
            }
        )
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing {
            guard !isScrubbing else { return }
            scrubValue = ProgressScrubMath.clampedTime(engine.currentTime, duration: engine.duration)
            isScrubbing = true
            engine.beginScrub()
            onScrubChanged(true)
            scrubHapticTrigger += 1
        } else {
            guard isScrubbing else { return }
            engine.endScrub(to: scrubValue)
            isScrubbing = false
            onScrubChanged(false)
            scrubHapticTrigger += 1
        }
    }
}

enum ProgressScrubMath {
    static func clampedTime(_ time: Double, duration: Double) -> Double {
        guard time.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }
}

// MARK: - Inline Lyrics

/// Keeps the half-second playback-time observation inside this small subtree.
struct PlayerInlineLyricsPreview: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionPhase = false

    let isMotionEnabled: Bool
    let performanceScore: LyricPerformanceScore?
    let action: () -> Void

    var body: some View {
        if let snapshot {
            Button(action: action) {
                ZStack {
                    if snapshot.cue.effect == .echo {
                        Text(snapshot.current.text)
                            .font(.system(
                                size: snapshot.cue.fontSize,
                                weight: snapshot.cue.weight.fontWeight
                            ))
                            .multilineTextAlignment(snapshot.cue.alignment.textAlignment)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(PlayerSurface.textPrimary.opacity(motionPhase ? 0.06 : 0.20))
                            .offset(
                                x: CGFloat(snapshot.cue.direction * snapshot.cue.intensity) * (motionPhase ? 16 : 5),
                                y: motionPhase ? CGFloat(-5 * snapshot.cue.intensity) : 1
                            )
                            .blur(radius: motionPhase ? 1.8 : 0.4)
                            .frame(maxWidth: 340, alignment: snapshot.cue.alignment.frameAlignment)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 8) {
                        ForEach(snapshot.visibleLines) { visibleLine in
                            lyricLine(visibleLine, snapshot: snapshot)
                        }
                    }
                    .multilineTextAlignment(snapshot.cue.alignment.textAlignment)
                    .frame(maxWidth: 340, alignment: snapshot.cue.alignment.frameAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .offset(x: activeOffset(for: snapshot.cue), y: activeVerticalOffset(for: snapshot.cue))
                    .scaleEffect(
                        x: activeScaleX(for: snapshot.cue),
                        y: activeScaleY(for: snapshot.cue)
                    )
                    .rotationEffect(.degrees(activeRotation(for: snapshot.cue)))
                    .id(snapshot.current.id)
                    .transition(transition(for: snapshot.cue))
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(transitionAnimation(for: snapshot.cue), value: snapshot.current.id)
            .task(id: MotionTaskID(
                lineID: snapshot.current.id,
                shouldAnimate: isMotionEnabled && engine.state == .playing && scenePhase == .active
            )) {
                motionPhase = false
                guard isMotionEnabled,
                      engine.state == .playing,
                      scenePhase == .active,
                      !snapshot.cue.reduceMotion else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: snapshot.motionDuration)) {
                    motionPhase = true
                }
            }
            .accessibilityLabel("当前歌词，\(snapshot.current.text)")
            .accessibilityHint("打开完整歌词")
            .accessibilityIdentifier("playerInlineLyricsPreview")
        }
    }

    private var snapshot: Snapshot? {
        guard engine.playbackMode != .mv,
              engine.lyricsFollowPlayback,
              !engine.lyrics.isEmpty else { return nil }

        let time = engine.adjustedLyricTime
        let activeIndices = LyricHighlightModel.activeLineIndices(lines: engine.lyrics, at: time)
        let activeIndex = activeIndices.isEmpty
            ? nil
            : LyricHighlightModel.activeLineIndex(lines: engine.lyrics, at: time)
        let index = activeIndex ?? engine.lyrics.firstIndex(where: { $0.from > time })
        guard let index, let current = engine.lyrics[safe: index] else { return nil }

        let fallbackCue = LyricMotionDirector.cue(
            text: current.text,
            lineDuration: current.to - current.from,
            trackID: engine.current?.key.description ?? "unknown-track",
            lineIndex: index,
            reduceMotion: reduceMotion
        )
        let cue = performanceScore?.cue(for: index, fallback: fallbackCue) ?? fallbackCue
        let visibleIndices: [Int]
        if activeIndices.count > 1 {
            // Timing owns simultaneous vocals. Luna may style the resulting
            // stack, but it must not replace a real overlap with unrelated
            // neighboring lines.
            visibleIndices = activeIndices
        } else if let performanceScore {
            visibleIndices = performanceScore.textLineIndices(for: index) ?? [index]
        } else {
            visibleIndices = [index, index + 1]
        }
        let visibleLines = visibleIndices.compactMap { visibleIndex -> VisibleLine? in
            guard let line = engine.lyrics[safe: visibleIndex] else { return nil }
            return VisibleLine(
                index: visibleIndex,
                position: visibleIndices.firstIndex(of: visibleIndex) ?? 0,
                line: line,
                isCurrent: activeIndices.contains(visibleIndex) || visibleIndex == index,
                isPrimary: visibleIndex == index
            )
        }
        let remainingDuration = current.to - max(time, current.from)
        return Snapshot(
            current: current,
            visibleLines: visibleLines,
            isUpcoming: activeIndex == nil,
            cue: cue,
            wordCue: performanceScore?.wordCue(for: index),
            motionDuration: motionDuration(remaining: remainingDuration, cue: cue)
        )
    }

    @ViewBuilder
    private func lyricLine(_ visibleLine: VisibleLine, snapshot: Snapshot) -> some View {
        let tokens = LyricWordPerformanceModel.displayTokens(for: visibleLine.line)
        Group {
            if visibleLine.isCurrent,
               visibleLine.isPrimary,
               !snapshot.isUpcoming,
               tokens.allSatisfy({ $0.wordIndex != nil }) {
                TimelineView(.animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: !isWordTimelineActive
                )) { _ in
                    LyricWordPerformanceLine(
                        tokens: tokens,
                        cue: snapshot.cue,
                        wordCue: snapshot.wordCue,
                        time: preciseLyricTime)
                }
                .frame(maxWidth: 340, alignment: snapshot.cue.alignment.frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                let aiScore = LyricEmbellishmentStore.shared.score(
                    for: engine.current?.key.description ?? "",
                    lyricsHash: LyricPerformanceFingerprint.lyricsHash(engine.lyrics)
                )
                let lineStyle = visibleLine.isCurrent
                    ? LyricEmbellishmentDirector.embellishment(
                        forLine: visibleLine.line.text,
                        lineIndex: visibleLine.index,
                        isSecondary: visibleLine.line.voiceRole.isSecondary,
                        aiScore: aiScore
                    )
                    : .none
                Text(visibleLine.line.text)
                    .font(.system(
                        size: visibleLine.isCurrent
                            ? activeFontSize(for: visibleLine, cue: snapshot.cue)
                            : min(max(snapshot.cue.fontSize * 0.64, 17), 21),
                        weight: visibleLine.isCurrent
                            ? activeFontWeight(for: visibleLine, cue: snapshot.cue)
                            : .semibold
                    ))
                    .tracking(tracking(for: visibleLine, cue: snapshot.cue))
                    .foregroundStyle(visibleLine.isCurrent
                        ? PlayerSurface.textPrimary.opacity(activeOpacity(for: visibleLine, upcoming: snapshot.isUpcoming))
                        : PlayerSurface.textSecondary.opacity(0.62))
                    .lyricEmbellishment(
                        style: lineStyle,
                        state: visibleLine.isCurrent ? .current(progress: 0.5) : .unsung,
                        reduceMotion: reduceMotion
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .blur(radius: blurRadius(for: visibleLine, cue: snapshot.cue))
        .offset(y: cascadeOffset(for: visibleLine, cue: snapshot.cue))
        .opacity(cascadeOpacity(for: snapshot.cue))
        .animation(cascadeAnimation(for: visibleLine, cue: snapshot.cue), value: motionPhase)
    }

    private var isWordTimelineActive: Bool {
        isMotionEnabled && engine.state == .playing && scenePhase == .active
    }

    private var preciseLyricTime: Double {
        let playerTime = engine.avPlayer?.currentTime().seconds ?? engine.currentTime
        let base = playerTime.isFinite ? playerTime : engine.currentTime
        return base + Double(engine.lyricOffsetMilliseconds) / 1_000
    }

    private func motionDuration(remaining: Double, cue: LyricMotionCue) -> Double {
        let available = min(max(remaining, 0.4), cue.duration)
        switch cue.effect {
        case .focus, .drop:
            return min(available, 0.62)
        case .stretch, .cascade:
            return min(available, 0.82)
        default:
            return available
        }
    }

    private func transition(for cue: LyricMotionCue) -> AnyTransition {
        guard !cue.reduceMotion else { return .opacity }
        switch cue.effect {
        case .rise:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .impact:
            return .asymmetric(
                insertion: .scale(scale: 0.68).combined(with: .opacity),
                removal: .scale(scale: 1.16).combined(with: .opacity)
            )
        case .drift:
            let incoming: Edge = cue.direction < 0 ? .trailing : .leading
            let outgoing: Edge = cue.direction < 0 ? .leading : .trailing
            return .asymmetric(
                insertion: .move(edge: incoming).combined(with: .opacity),
                removal: .move(edge: outgoing).combined(with: .opacity)
            )
        case .breathe:
            return .asymmetric(
                insertion: .scale(scale: 0.90).combined(with: .opacity),
                removal: .scale(scale: 1.06).combined(with: .opacity)
            )
        case .echo:
            return .modifier(
                active: LyricEchoTransitionModifier(
                    x: CGFloat(cue.direction) * 24,
                    scale: 1.08,
                    blur: 5,
                    opacity: 0
                ),
                identity: LyricEchoTransitionModifier(
                    x: 0,
                    scale: 1,
                    blur: 0,
                    opacity: 1
                )
            )
        case .focus:
            return .modifier(
                active: LyricEchoTransitionModifier(x: 0, scale: 0.97, blur: 5, opacity: 0),
                identity: LyricEchoTransitionModifier(x: 0, scale: 1, blur: 0, opacity: 1)
            )
        case .drop:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .scale(scale: 0.96).combined(with: .opacity)
            )
        case .stretch:
            return .asymmetric(
                insertion: .scale(scale: 0.78).combined(with: .opacity),
                removal: .scale(scale: 1.08).combined(with: .opacity)
            )
        case .cascade:
            return .opacity
        }
    }

    private func transitionAnimation(for cue: LyricMotionCue) -> Animation? {
        guard !cue.reduceMotion else { return .linear(duration: 0.14) }
        switch cue.effect {
        case .rise:
            return .easeOut(duration: 0.38)
        case .impact:
            return .spring(response: 0.40, dampingFraction: 0.68)
        case .drift:
            return .easeOut(duration: 0.46)
        case .breathe:
            return .easeInOut(duration: 0.56)
        case .echo:
            return .easeOut(duration: 0.48)
        case .focus:
            return .easeOut(duration: 0.58)
        case .drop:
            return .spring(response: 0.52, dampingFraction: 0.74)
        case .stretch:
            return .easeOut(duration: 0.72)
        case .cascade:
            return .easeOut(duration: 0.64)
        }
    }

    private func activeOffset(for cue: LyricMotionCue) -> CGFloat {
        guard motionPhase, !cue.reduceMotion else { return 0 }
        switch cue.effect {
        case .drift:
            return CGFloat(cue.direction * cue.intensity) * 14
        case .echo:
            return CGFloat(cue.direction * cue.intensity) * -3
        default:
            return 0
        }
    }

    private func activeVerticalOffset(for cue: LyricMotionCue) -> CGFloat {
        guard !cue.reduceMotion else { return 0 }
        switch cue.effect {
        case .rise:
            return motionPhase ? CGFloat(-6 * cue.intensity) : 0
        case .drop:
            return motionPhase ? 0 : CGFloat(-18 * cue.intensity)
        default:
            return 0
        }
    }

    private func activeScaleX(for cue: LyricMotionCue) -> CGFloat {
        guard !cue.reduceMotion else { return 1 }
        switch cue.effect {
        case .impact:
            return motionPhase ? CGFloat(1 + 0.035 * cue.intensity) : 1
        case .stretch:
            return motionPhase ? 1 : CGFloat(max(0.72, 1 - 0.20 * cue.intensity))
        default:
            return 1
        }
    }

    private func activeScaleY(for cue: LyricMotionCue) -> CGFloat {
        guard motionPhase, !cue.reduceMotion else { return 1 }
        switch cue.effect {
        case .breathe:
            return CGFloat(1 + 0.025 * cue.intensity)
        default:
            return 1
        }
    }

    private func activeFontSize(for visibleLine: VisibleLine, cue: LyricMotionCue) -> Double {
        switch visibleLine.line.voiceRole {
        case .lead, .together:
            return visibleLine.isPrimary ? cue.fontSize : cue.fontSize * 0.86
        case .duetA, .duetB:
            return visibleLine.isPrimary ? cue.fontSize * 0.90 : cue.fontSize * 0.84
        case .backing:
            return min(max(cue.fontSize * 0.64, 17), 22)
        }
    }

    private func activeFontWeight(for visibleLine: VisibleLine, cue: LyricMotionCue) -> Font.Weight {
        switch visibleLine.line.voiceRole {
        case .backing:
            return .semibold
        case .duetA, .duetB:
            return visibleLine.isPrimary ? cue.weight.fontWeight : .bold
        case .lead, .together:
            return visibleLine.isPrimary ? cue.weight.fontWeight : .bold
        }
    }

    private func activeOpacity(for visibleLine: VisibleLine, upcoming: Bool) -> Double {
        if upcoming { return 0.68 }
        return visibleLine.line.voiceRole.isSecondary ? 0.68 : 0.94
    }

    private func tracking(for visibleLine: VisibleLine, cue: LyricMotionCue) -> CGFloat {
        guard visibleLine.isCurrent, visibleLine.isPrimary else { return 0 }
        if cue.effect == .focus, !cue.reduceMotion {
            return motionPhase
                ? CGFloat(cue.tracking * 0.18)
                : CGFloat(cue.tracking + 1.8 * cue.intensity)
        }
        return CGFloat(motionPhase ? cue.tracking : cue.tracking * 0.25)
    }

    private func blurRadius(for visibleLine: VisibleLine, cue: LyricMotionCue) -> CGFloat {
        guard visibleLine.isCurrent,
              visibleLine.isPrimary,
              cue.effect == .focus,
              !cue.reduceMotion,
              !motionPhase else { return 0 }
        return CGFloat(4.5 * cue.intensity)
    }

    private func cascadeOffset(for visibleLine: VisibleLine, cue: LyricMotionCue) -> CGFloat {
        guard cue.effect == .cascade, !cue.reduceMotion, !motionPhase else { return 0 }
        return CGFloat(10 + visibleLine.position * 6) * CGFloat(cue.intensity)
    }

    private func cascadeOpacity(for cue: LyricMotionCue) -> Double {
        guard cue.effect == .cascade, !cue.reduceMotion else { return 1 }
        return motionPhase ? 1 : 0
    }

    private func cascadeAnimation(for visibleLine: VisibleLine, cue: LyricMotionCue) -> Animation? {
        guard cue.effect == .cascade, !cue.reduceMotion else { return nil }
        return .easeOut(duration: 0.38).delay(Double(visibleLine.position) * 0.09)
    }

    private func activeRotation(for cue: LyricMotionCue) -> Double {
        guard motionPhase, !cue.reduceMotion else { return 0 }
        switch cue.effect {
        case .drift:
            return cue.direction * 0.8 * cue.intensity
        case .echo:
            return cue.direction * -1.2 * cue.intensity
        default:
            return 0
        }
    }

    private struct Snapshot {
        let current: PlayerEngine.LyricLine
        let visibleLines: [VisibleLine]
        let isUpcoming: Bool
        let cue: LyricMotionCue
        let wordCue: LyricWordCue?
        let motionDuration: Double
    }

    private struct VisibleLine: Identifiable {
        let index: Int
        let position: Int
        let line: PlayerEngine.LyricLine
        let isCurrent: Bool
        let isPrimary: Bool

        var id: Int { index }
    }

    private struct MotionTaskID: Hashable {
        let lineID: UUID
        let shouldAnimate: Bool
    }
}

private struct LyricWordPerformanceLine: View {
    let tokens: [LyricWordDisplayToken]
    let cue: LyricMotionCue
    let wordCue: LyricWordCue?
    let time: Double

    var body: some View {
        LyricWordWrapLayout(alignment: cue.alignment) {
            ForEach(tokens) { token in
                LyricWordPerformanceToken(
                    token: token,
                    state: LyricWordPerformanceModel.playbackState(for: token, at: time),
                    cue: cue,
                    wordCue: wordCue)
            }
        }
    }
}

private struct LyricWordPerformanceToken: View {
    let token: LyricWordDisplayToken
    let state: LyricWordPlaybackState
    let cue: LyricMotionCue
    let wordCue: LyricWordCue?

    var body: some View {
        ZStack {
            if effect == .echoTrail, isTarget, currentProgress != nil, !cue.reduceMotion {
                ForEach(1...2, id: \.self) { layer in
                    wordText
                        .foregroundStyle(PlayerSurface.textPrimary.opacity(echoOpacity(layer: layer)))
                        .offset(x: echoOffset(layer: layer))
                        .blur(radius: CGFloat(layer) * 0.45)
                        .accessibilityHidden(true)
                }
            }
            wordText
                .foregroundStyle(foregroundColor)
                .shadow(
                    color: PlayerSurface.textPrimary.opacity(activeGlowOpacity),
                    radius: activeGlowRadius)
        }
        .scaleEffect(x: scaleX, y: scaleY)
        .offset(y: verticalOffset)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var wordText: some View {
        Text(token.text)
            .font(.system(size: cue.fontSize, weight: cue.weight.fontWeight))
            .tracking(cue.tracking)
    }

    private var isTarget: Bool {
        guard let wordIndex = token.wordIndex else { return false }
        return wordCue?.contains(wordIndex: wordIndex) == true
    }

    private var effect: LyricWordEffect {
        isTarget ? (wordCue?.effect ?? .sweep) : .sweep
    }

    private var intensity: Double {
        isTarget ? (wordCue?.intensity ?? 0.7) : 0.7
    }

    private var currentProgress: Double? {
        guard case let .current(progress) = state else { return nil }
        return progress
    }

    private var wave: Double {
        guard let currentProgress else { return 0 }
        return sin(.pi * currentProgress)
    }

    private var foregroundColor: Color {
        switch state {
        case .unsung:
            return PlayerSurface.textSecondary.opacity(0.28)
        case let .current(progress):
            let emphasis = effect == .sweep ? 0.0 : 0.08 * intensity
            return PlayerSurface.textPrimary.opacity(min(1, 0.62 + progress * 0.34 + emphasis))
        case .sung:
            return PlayerSurface.textPrimary.opacity(0.94)
        }
    }

    private var scaleX: CGFloat {
        guard !cue.reduceMotion else { return 1 }
        switch effect {
        case .impact:
            return CGFloat(1 + 0.08 * intensity * wave)
        case .stretch:
            return CGFloat(1 + 0.16 * intensity * wave)
        default:
            return 1
        }
    }

    private var scaleY: CGFloat {
        guard !cue.reduceMotion, effect == .impact else { return 1 }
        return CGFloat(1 + 0.05 * intensity * wave)
    }

    private var verticalOffset: CGFloat {
        guard !cue.reduceMotion, effect == .impact else { return 0 }
        return CGFloat(-3 * intensity * wave)
    }

    private var activeGlowOpacity: Double {
        guard currentProgress != nil else { return 0 }
        return min(0.35, 0.12 + 0.16 * intensity * wave)
    }

    private var activeGlowRadius: CGFloat {
        currentProgress == nil ? 0 : CGFloat(2 + 4 * intensity * wave)
    }

    private func echoOpacity(layer: Int) -> Double {
        max(0, (0.22 / Double(layer)) * intensity * wave)
    }

    private func echoOffset(layer: Int) -> CGFloat {
        let direction = CGFloat(wordCue?.direction ?? 1)
        return direction * CGFloat(layer) * CGFloat(4 + 7 * wave)
    }
}

struct LyricWordWrapLayout: Layout {
    let alignment: LyricMotionAlignment
    private let lineSpacing: CGFloat = 3

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = max(1, proposal.width ?? 340)
        let rows = makeRows(subviews: subviews, maxWidth: maxWidth)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(subviews: subviews, maxWidth: max(1, bounds.width))
        var y = bounds.minY
        for row in rows {
            let originX: CGFloat
            switch alignment {
            case .leading:
                originX = bounds.minX
            case .center:
                originX = bounds.midX - row.width / 2
            case .trailing:
                originX = bounds.maxX - row.width
            }
            var x = originX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: .unspecified)
                x += item.size.width
            }
            y += row.height + lineSpacing
        }
    }

    private func makeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        func flush() {
            guard !items.isEmpty else { return }
            rows.append(Row(items: items, width: width, height: height))
            items.removeAll(keepingCapacity: true)
            width = 0
            height = 0
        }

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !items.isEmpty, width + size.width > maxWidth {
                flush()
            }
            items.append(Item(index: index, size: size))
            width += size.width
            height = max(height, size.height)
        }
        flush()
        return rows
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        let items: [Item]
        let width: CGFloat
        let height: CGFloat
    }
}

private struct LyricEchoTransitionModifier: ViewModifier {
    let x: CGFloat
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private extension LyricMotionWeight {
    var fontWeight: Font.Weight {
        switch self {
        case .semibold: .semibold
        case .bold: .bold
        case .black: .black
        }
    }
}

private extension LyricMotionAlignment {
    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

// MARK: - System Media Controls

/// Keeps AirPlay routing in the system-owned picker rather than recreating it.
struct SystemRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor.white.withAlphaComponent(0.72)
        picker.activeTintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor.white.withAlphaComponent(0.72)
        uiView.activeTintColor = .white
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
