import SwiftUI

/// 歌词词级/句级微巧思风格（12 种精品风格）
enum LyricEmbellishmentStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case whisper       // 低语 / 柔情（衬线、轻字重、宽字距、柔焦）
    case shimmer       // 星光 / 流光（白金高光遮罩流光、微光晕）
    case impact        // 呐喊 / 重音（特粗 Black、紧凑字距、唱响微弹跳）
    case floating      // 浮游 / 梦境（斜体、正弦波上下微浮游）
    case digital       // 数码 / 赛博（等宽字体、数码感）
    case ripple        // 回音 / 波纹（唱毕后同心微扩散环）
    case neon          // 霓虹 / 电光（青粉双色微发光、霓虹流光）
    case blaze         // 烈焰 / 炽热（暖金赤红双色渐变、微温跃动）
    case crystallize   // 晶霜 / 冰清（锐利超净、冰晶微闪十字光）
    case heartbeat     // 心跳 / 悸动（饱满字重、双阶段心跳律动）
    case vintage       // 复古 / 怀旧（古典衬线、老式暖木色温）
    case sway          // 微风 / 摇曳（舒展字形、左右柔和微晃）
}

/// 歌词微巧思分析与识别引擎（本地零延迟确定性规则与双层分发）
enum LyricEmbellishmentDirector {
    
    // MARK: - Keyword Dictionaries
    
    private static let whisperKeywords: Set<String> = [
        "嘘", "そっと", "静か", "内緒", "息", "眠", "微か", "かすか", "ささやき", "ため息", "消え",
        "whisper", "quiet", "soft", "secret", "breath", "silent", "gentle", "calm", "hush",
        "轻", "静", "悄悄", "温柔", "晚安", "低语", "叹息", "秘密", "微弱", "呼吸", "柔"
    ]
    
    private static let shimmerKeywords: Set<String> = [
        "星", "光", "夜空", "輝", "かがやき", "煌", "きら", "キラ", "照", "瞬", "星空", "銀河",
        "shine", "star", "light", "sparkle", "glimmer", "twinkle", "glow", "bright", "starlight",
        "闪", "亮", "耀", "灿烂", "星光", "月光", "晨曦", "璀璨", "微光", "辉", "光芒"
    ]
    
    private static let impactKeywords: Set<String> = [
        "叫", "叫べ", "跳", "跳べ", "撃", "轟", "走", "走れ", "砕", "断", "響け", "鳴らせ",
        "bang", "jump", "shout", "blast", "strike", "hit", "crash", "boom", "punch", "smash",
        "冲", "破", "轰", "狂", "爆", "炸", "战", "闯", "震", "吼", "飞", "撞"
    ]
    
    private static let floatingKeywords: Set<String> = [
        "夢", "ゆめ", "どこ", "漂", "ただよう", "宙", "空", "なぜ", "どうして", "幻", "雲", "彷徨",
        "dream", "where", "float", "drift", "sky", "why", "cloud", "illusion", "wander", "fly",
        "梦", "何处", "飘", "漂浮", "浮", "游", "空", "云", "为何", "幻想", "迷", "虚"
    ]
    
    private static let digitalKeywords: Set<String> = [
        "8bit", "8-bit", "rom", "pixel", "byte", "bit", "data", "system", "code", "cyber", "retro", "error", "cpu", "pc", "glitch",
        "未来", "信号", "回路", "電波", "機械", "コード", "データ", "システム",
        "数码", "代码", "机械", "系统", "像素", "程序", "电波", "网络", "芯片", "终端"
    ]
    
    private static let neonKeywords: Set<String> = [
        "neon", "city", "night", "cyberpunk", "disco", "laser", "electric", "club",
        "ネオン", "夜の街", "都会", "シティー", "レーザー", "エレクトロ",
        "霓虹", "电光", "夜市", "都市", "幻彩", "派对", "灯火", "夜色"
    ]
    
    private static let blazeKeywords: Set<String> = [
        "fire", "burn", "flame", "blaze", "heat", "hot", "passion", "sun", "ignite",
        "炎", "燃", "火", "熱", "情熱", "灼熱", "太陽", "燃え",
        "烈火", "燃烧", "火焰", "热情", "炽热", "滚烫", "烈日", "点燃", "火光"
    ]
    
    private static let crystallizeKeywords: Set<String> = [
        "ice", "snow", "crystal", "frost", "cold", "freeze", "glass", "diamond",
        "氷", "雪", "結晶", "クリスタル", "凍", "冷", "ガラス", "ダイヤモンド",
        "冰", "雪", "晶", "水晶", "冻", "霜", "清澈", "纯净", "冷冽", "钻石"
    ]
    
    private static let heartbeatKeywords: Set<String> = [
        "heart", "beat", "pulse", "love", "throb", "dokidoki", "chest",
        "心", "鼓動", "胸", "ドキドキ", "ドクドク", "脈", "愛",
        "心跳", "悸动", "脉搏", "心动", "怦怦", "深爱", "胸口"
    ]
    
    private static let vintageKeywords: Set<String> = [
        "vintage", "nostalgia", "memory", "old", "record", "film", "antique", "past",
        "懐かしい", "記憶", "過去", "レコード", "昔", "ノスタルジー", "想い出",
        "复古", "怀旧", "回忆", "岁月", "往事", "老唱片", "胶片", "从前"
    ]
    
    private static let swayKeywords: Set<String> = [
        "wind", "breeze", "sway", "wave", "leaf", "leaves", "flow", "dance",
        "風", "そよ風", "揺れる", "ゆらゆら", "波", "葉", "舞う", "流れる",
        "微风", "清风", "摇曳", "荡漾", "飞舞", "落叶", "微波", "流动"
    ]
    
    // MARK: - Word Level Embellishment
    
    /// 分析单个词的微巧思风格（优先消费露娜 AI 标签，否则走本地规则库）
    static func embellishment(
        forWord text: String,
        lineIndex: Int = 0,
        wordIndex: Int? = nil,
        lineText: String? = nil,
        aiScore: LyricEmbellishmentScore? = nil
    ) -> LyricEmbellishmentStyle {
        // 1. 优先消费 AI 谱表中的指定词巧思
        if let aiScore,
           let aiStyle = aiScore.style(forLine: lineIndex, wordIndex: wordIndex) {
            return aiStyle
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let lower = trimmed.lowercased()
        
        // 2. 标点特征优先
        if trimmed.contains("!") || trimmed.contains("！") {
            return .impact
        }
        if trimmed.contains("?") || trimmed.contains("？") {
            return .floating
        }
        if trimmed.contains("…") || trimmed.contains("...") || trimmed.contains("〜") || trimmed.contains("～") {
            return .whisper
        }
        
        // 3. 精确关键词字典匹配
        if heartbeatKeywords.contains(lower) || containsAny(in: trimmed, keywords: heartbeatKeywords) {
            return .heartbeat
        }
        if crystallizeKeywords.contains(lower) || containsAny(in: trimmed, keywords: crystallizeKeywords) {
            return .crystallize
        }
        if blazeKeywords.contains(lower) || containsAny(in: trimmed, keywords: blazeKeywords) {
            return .blaze
        }
        if neonKeywords.contains(lower) || containsAny(in: trimmed, keywords: neonKeywords) {
            return .neon
        }
        if digitalKeywords.contains(lower) || containsAny(in: trimmed, keywords: digitalKeywords) {
            return .digital
        }
        if impactKeywords.contains(lower) || containsAny(in: trimmed, keywords: impactKeywords) {
            return .impact
        }
        if shimmerKeywords.contains(lower) || containsAny(in: trimmed, keywords: shimmerKeywords) {
            return .shimmer
        }
        if swayKeywords.contains(lower) || containsAny(in: trimmed, keywords: swayKeywords) {
            return .sway
        }
        if vintageKeywords.contains(lower) || containsAny(in: trimmed, keywords: vintageKeywords) {
            return .vintage
        }
        if whisperKeywords.contains(lower) || containsAny(in: trimmed, keywords: whisperKeywords) {
            return .whisper
        }
        if floatingKeywords.contains(lower) || containsAny(in: trimmed, keywords: floatingKeywords) {
            return .floating
        }
        
        // 4. 重复叠词/回声判断 (e.g. "bye bye", "la la")
        if let lineText, hasRepeatPattern(word: trimmed, in: lineText) {
            return .ripple
        }
        
        return .none
    }
    
    // MARK: - Line Level Embellishment
    
    /// 分析整行歌词的主导微巧思风格
    static func embellishment(
        forLine text: String,
        lineIndex: Int = 0,
        isSecondary: Bool = false,
        aiScore: LyricEmbellishmentScore? = nil
    ) -> LyricEmbellishmentStyle {
        if isSecondary {
            return .whisper
        }
        if let aiScore,
           let aiStyle = aiScore.style(forLine: lineIndex, wordIndex: nil) {
            return aiStyle
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        
        if trimmed.contains("!") || trimmed.contains("！") {
            return .impact
        }
        if trimmed.contains("?") || trimmed.contains("？") {
            return .floating
        }
        if trimmed.contains("…") || trimmed.contains("...") {
            return .whisper
        }
        
        let lower = trimmed.lowercased()
        if containsAny(in: lower, keywords: heartbeatKeywords) { return .heartbeat }
        if containsAny(in: lower, keywords: crystallizeKeywords) { return .crystallize }
        if containsAny(in: lower, keywords: blazeKeywords) { return .blaze }
        if containsAny(in: lower, keywords: neonKeywords) { return .neon }
        if containsAny(in: lower, keywords: digitalKeywords) { return .digital }
        if containsAny(in: lower, keywords: shimmerKeywords) { return .shimmer }
        if containsAny(in: lower, keywords: impactKeywords) { return .impact }
        if containsAny(in: lower, keywords: swayKeywords) { return .sway }
        if containsAny(in: lower, keywords: vintageKeywords) { return .vintage }
        if containsAny(in: lower, keywords: whisperKeywords) { return .whisper }
        if containsAny(in: lower, keywords: floatingKeywords) { return .floating }
        
        return .none
    }
    
    // MARK: - Private Helpers
    
    private static func containsAny(in text: String, keywords: Set<String>) -> Bool {
        for kw in keywords {
            if text.contains(kw) {
                return true
            }
        }
        return false
    }
    
    private static func hasRepeatPattern(word: String, in line: String) -> Bool {
        let tokens = line.split { $0.isWhitespace || $0.isPunctuation }.map(String.init)
        guard tokens.count >= 2 else { return false }
        for i in 1..<tokens.count {
            if tokens[i].caseInsensitiveCompare(word) == .orderedSame &&
                tokens[i-1].caseInsensitiveCompare(word) == .orderedSame {
                return true
            }
        }
        return false
    }
}

// MARK: - SwiftUI Embellishment Modifier

struct LyricEmbellishmentModifier: ViewModifier {
    let style: LyricEmbellishmentStyle
    let state: LyricWordState
    let reduceMotion: Bool
    
    func body(content: Content) -> some View {
        content
            .fontDesign(fontDesign)
            .fontWeight(fontWeight)
            .tracking(tracking)
            .italic(isItalic)
            .scaleEffect(activeScale, anchor: .center)
            .offset(x: activeHorizontalOffset, y: activeVerticalOffset)
            .overlay {
                if isCurrent, !reduceMotion {
                    activeOverlay
                }
            }
            .background {
                if style == .ripple, isCurrentOrSung {
                    rippleBackground
                }
            }
            .shadow(color: glowColor, radius: glowRadius)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isCurrent)
    }
    
    // MARK: - Typography Nuances
    
    private var fontDesign: Font.Design {
        switch style {
        case .digital: return .monospaced
        case .whisper, .vintage: return .serif
        case .neon: return .rounded
        default: return .default
        }
    }
    
    private var fontWeight: Font.Weight? {
        switch style {
        case .whisper, .crystallize: return isCurrent ? .medium : .light
        case .impact: return isCurrent ? .black : .bold
        case .blaze, .neon: return isCurrent ? .heavy : .bold
        case .heartbeat: return isCurrent ? .bold : .semibold
        default: return nil
        }
    }
    
    private var tracking: CGFloat {
        switch style {
        case .whisper: return 1.2
        case .vintage: return 0.8
        case .impact: return -0.2
        case .digital: return 0.8
        case .sway: return 0.5
        case .crystallize: return 0.4
        default: return 0
        }
    }
    
    private var isItalic: Bool {
        style == .floating
    }
    
    // MARK: - Micro Motion Nuances
    
    private var isCurrent: Bool {
        if case .current = state { return true }
        return false
    }
    
    private var isCurrentOrSung: Bool {
        switch state {
        case .current, .sung: return true
        case .unsung: return false
        }
    }
    
    private var fillProgress: Double {
        LyricHighlightModel.fillProgress(for: state)
    }
    
    private var activeScale: CGFloat {
        guard !reduceMotion, isCurrent else { return 1.0 }
        let p = fillProgress
        switch style {
        case .impact:
            // 单次爆发微弹性 (1.0 -> 1.08 -> 1.0)
            let pop = p < 0.35 ? (p / 0.35) * 0.08 : (1.0 - (p - 0.35) / 0.65) * 0.08
            return 1.0 + CGFloat(pop)
        case .heartbeat:
            // 双阶段心跳脉冲
            let phase1 = p < 0.25 ? (p / 0.25) * 0.06 : (p < 0.5 ? (1.0 - (p - 0.25) / 0.25) * 0.06 : 0)
            let phase2 = (p >= 0.5 && p < 0.75) ? ((p - 0.5) / 0.25) * 0.03 : (p >= 0.75 ? (1.0 - (p - 0.75) / 0.25) * 0.03 : 0)
            return 1.0 + CGFloat(phase1 + phase2)
        default:
            return 1.0
        }
    }
    
    private var activeVerticalOffset: CGFloat {
        guard !reduceMotion, isCurrent else { return 0 }
        switch style {
        case .floating:
            // 浮游垂直正弦波 (±1.8pt)
            return CGFloat(sin(fillProgress * .pi * 2) * -1.8)
        default:
            return 0
        }
    }
    
    private var activeHorizontalOffset: CGFloat {
        guard !reduceMotion, isCurrent else { return 0 }
        switch style {
        case .sway:
            // 摇曳水平余弦波 (±1.5pt)
            return CGFloat(sin(fillProgress * .pi * 2) * 1.5)
        default:
            return 0
        }
    }
    
    // MARK: - Glow & Colors
    
    private var glowColor: Color {
        guard isCurrent else { return .clear }
        switch style {
        case .shimmer:
            return Color.white.opacity(0.45)
        case .neon:
            return Color.cyan.opacity(0.55)
        case .blaze:
            return Color.orange.opacity(0.50)
        case .crystallize:
            return Color.cyan.opacity(0.35)
        case .heartbeat:
            return Color.pink.opacity(0.40)
        case .impact:
            return Color.white.opacity(0.35)
        case .whisper, .vintage:
            return Color.white.opacity(0.15)
        default:
            return Color.white.opacity(0.20)
        }
    }
    
    private var glowRadius: CGFloat {
        guard isCurrent else { return 0 }
        switch style {
        case .neon: return 9
        case .shimmer, .blaze: return 8
        case .crystallize, .heartbeat, .impact: return 6
        case .whisper, .vintage: return 3
        default: return 4
        }
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    private var activeOverlay: some View {
        switch style {
        case .shimmer:
            shimmerOverlay
        case .crystallize:
            crystalGlintOverlay
        case .blaze:
            blazeOverlay
        case .neon:
            neonOverlay
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var shimmerOverlay: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let shimmerWidth = max(width * 0.6, 20)
            let offset = (width + shimmerWidth) * CGFloat(fillProgress) - shimmerWidth
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.70), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: shimmerWidth)
            .offset(x: offset)
            .blendMode(.plusLighter)
            .mask {
                Rectangle().frame(width: width)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    @ViewBuilder
    private var crystalGlintOverlay: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let p = fillProgress
            let flareOpacity = p < 0.5 ? (p / 0.5) : (1.0 - (p - 0.5) / 0.5)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(flareOpacity * 0.8))
                    .frame(width: 4, height: 4)
                Rectangle()
                    .fill(Color.white.opacity(flareOpacity * 0.6))
                    .frame(width: size * 0.8, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(flareOpacity * 0.6))
                    .frame(width: 1, height: size * 0.8)
            }
            .position(x: proxy.size.width * CGFloat(p), y: proxy.size.height * 0.4)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    @ViewBuilder
    private var blazeOverlay: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.35), Color.red.opacity(0.20)],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    @ViewBuilder
    private var neonOverlay: some View {
        LinearGradient(
            colors: [Color.cyan.opacity(0.35), Color.pink.opacity(0.25)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    @ViewBuilder
    private var rippleBackground: some View {
        if style == .ripple, !reduceMotion {
            Circle()
                .strokeBorder(Color.white.opacity(isCurrent ? 0.28 : 0.0), lineWidth: 1)
                .scaleEffect(isCurrent ? 1.45 : 0.8)
                .opacity(isCurrent ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.35), value: isCurrent)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func lyricEmbellishment(
        style: LyricEmbellishmentStyle,
        state: LyricWordState,
        reduceMotion: Bool = false
    ) -> some View {
        modifier(LyricEmbellishmentModifier(style: style, state: state, reduceMotion: reduceMotion))
    }
}
