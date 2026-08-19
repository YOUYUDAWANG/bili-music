import SwiftUI
import UIKit

enum LyricStagePrototypeTimeline {
    static let duration = 18.0

    enum Scene: Int, CaseIterable {
        case assemble
        case gravity
        case duet
        case canvas
    }

    static func loopTime(elapsed: Double) -> Double {
        guard elapsed.isFinite else { return 0 }
        let value = elapsed.truncatingRemainder(dividingBy: duration)
        return value >= 0 ? value : value + duration
    }

    static func scene(at time: Double) -> Scene {
        switch loopTime(elapsed: time) {
        case ..<4.5: .assemble
        case ..<9: .gravity
        case ..<13.5: .duet
        default: .canvas
        }
    }

    static func progress(_ time: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }

    static func sceneOpacity(_ time: Double, start: Double, end: Double) -> Double {
        let fade = 0.42
        let entrance = progress(time, start: start, duration: fade)
        let exit = 1 - progress(time, start: end - fade, duration: fade)
        return min(entrance, exit)
    }

    static func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    static func backOut(_ value: Double) -> Double {
        let x = min(max(value, 0), 1) - 1
        let overshoot = 1.70158
        return 1 + (overshoot + 1) * x * x * x + overshoot * x * x
    }

    static func bounceOut(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
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

/// A deliberately local, hard-coded motion study. It validates the stage
/// language before the app accepts a larger Luna contract.
struct LyricStagePrototypeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool

    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let time = LyricStagePrototypeTimeline.loopTime(elapsed: elapsed)
            GeometryReader { proxy in
                ZStack {
                    assembleScene(time: time, size: proxy.size)
                    gravityScene(time: time, size: proxy.size)
                    duetScene(time: time, size: proxy.size)
                    canvasScene(time: time, size: proxy.size)

                    Text("V5 · KINETIC TYPE STUDY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(PlayerSurface.textTertiary.opacity(0.72))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .onAppear { startedAt = Date() }
        .onChange(of: isActive) { _, active in
            if active { startedAt = Date() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("动态文字舞台样片")
        .accessibilityValue(LyricStagePrototypeTimeline.scene(at: elapsedNow).accessibilityName)
        .accessibilityIdentifier("lyricStagePrototype")
    }

    private var elapsedNow: Double {
        LyricStagePrototypeTimeline.loopTime(elapsed: Date().timeIntervalSince(startedAt))
    }

    private func assembleScene(time: Double, size: CGSize) -> some View {
        let alpha = LyricStagePrototypeTimeline.sceneOpacity(time, start: 0, end: 4.5)
        let settle = easedProgress(time, start: 0.15, duration: 1.05, easing: LyricStagePrototypeTimeline.backOut)
        let camera = easedProgress(time, start: 2.35, duration: 1.5, easing: LyricStagePrototypeTimeline.smooth)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 1) {
                ForEach(Array("歌词不是字幕".enumerated()), id: \.offset) { index, character in
                    let glyph = easedProgress(
                        time,
                        start: 0.18 + Double(index) * 0.09,
                        duration: 0.72,
                        easing: LyricStagePrototypeTimeline.backOut)
                    Text(String(character))
                        .font(.system(size: index == 2 ? 39 : 34, weight: .black))
                        .foregroundStyle(index == 2 ? prototypeAccent : PlayerSurface.textPrimary)
                        .rotationEffect(.degrees((1 - glyph) * Double((index % 3) - 1) * 19))
                        .scaleEffect(0.35 + 0.65 * glyph)
                        .offset(
                            x: (1 - glyph) * CGFloat(((index * 37) % 7) - 3) * 18,
                            y: (1 - glyph) * CGFloat(index.isMultiple(of: 2) ? -82 : 76))
                        .opacity(glyph)
                }
            }
            Text("它应该占据空间")
                .font(.system(size: 18, weight: .semibold))
                .tracking(2.2 - 1.6 * settle)
                .foregroundStyle(PlayerSurface.textSecondary)
                .offset(x: 18 * (1 - settle))
                .blur(radius: 5 * (1 - settle))
                .opacity(settle)
        }
        .frame(maxWidth: size.width, alignment: .leading)
        .offset(x: -10 * camera, y: -8 - 14 * camera)
        .scaleEffect(1 + 0.045 * camera, anchor: .leading)
        .opacity(alpha)
    }

    private func gravityScene(time: Double, size: CGSize) -> some View {
        let alpha = LyricStagePrototypeTimeline.sceneOpacity(time, start: 4.5, end: 9)
        let local = time - 4.5
        let drift = easedProgress(local, start: 2.4, duration: 1.2, easing: LyricStagePrototypeTimeline.smooth)
        return ZStack {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                ForEach(Array("坠入声音里".enumerated()), id: \.offset) { index, character in
                    let drop = easedProgress(
                        local,
                        start: 0.12 + Double(index) * 0.13,
                        duration: 1.1,
                        easing: LyricStagePrototypeTimeline.bounceOut)
                    gravityGlyph(
                        character: character,
                        index: index,
                        drop: drop,
                        drift: drift)
                }
            }
            .offset(y: 9 + 18 * drift)

            Text("坠")
                .font(.system(size: 82, weight: .black))
                .foregroundStyle(prototypeWarm.opacity(0.11 * (1 - drift)))
                .scaleEffect(0.75 + drift * 0.7)
                .blur(radius: 1.5 + 4 * drift)
                .offset(y: 38 * drift)
        }
        .frame(width: size.width, height: size.height)
        .opacity(alpha)
    }

    private func duetScene(time: Double, size: CGSize) -> some View {
        let alpha = LyricStagePrototypeTimeline.sceneOpacity(time, start: 9, end: 13.5)
        let local = time - 9
        let enterA = easedProgress(local, start: 0.08, duration: 0.85, easing: LyricStagePrototypeTimeline.backOut)
        let enterB = easedProgress(local, start: 0.48, duration: 0.85, easing: LyricStagePrototypeTimeline.backOut)
        let merge = easedProgress(local, start: 2.0, duration: 1.05, easing: LyricStagePrototypeTimeline.smooth)
        let pulse = 1 + sin(max(0, local - 2.15) * 6.5) * 0.035 * merge
        return ZStack {
            prototypeDuetLine("你从左边唱", time: local, color: prototypeAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: -size.width * 0.62 * (1 - enterA), y: -27 + 14 * merge)

            prototypeDuetLine("我从右边回应", time: local - 0.35, color: prototypeWarm)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: size.width * 0.68 * (1 - enterB), y: 28 - 14 * merge)

            Text("一起")
                .font(.system(size: 43, weight: .black))
                .tracking(6 - 3.5 * merge)
                .foregroundStyle(PlayerSurface.textPrimary)
                .scaleEffect((0.3 + 0.7 * merge) * pulse)
                .opacity(merge)
                .shadow(color: .white.opacity(0.30 * merge), radius: 14)
        }
        .frame(width: size.width, height: size.height)
        .opacity(alpha)
    }

    private func canvasScene(time: Double, size: CGSize) -> some View {
        let alpha = LyricStagePrototypeTimeline.sceneOpacity(time, start: 13.5, end: 18)
        let local = time - 13.5
        let gather = easedProgress(local, start: 0.15, duration: 1.55, easing: LyricStagePrototypeTimeline.backOut)
        let reveal = easedProgress(local, start: 1.55, duration: 1.0, easing: LyricStagePrototypeTimeline.smooth)
        let breathe = 1 + sin(max(local - 2.2, 0) * 2.4) * 0.025 * reveal
        let characters = Array("每一个字")
        return ZStack {
            ForEach(characters.indices, id: \.self) { index in
                let angle = Double(index) / Double(characters.count) * .pi * 2 - .pi / 2
                let orbitX = cos(angle) * min(size.width * 0.36, 118)
                let orbitY = sin(angle) * min(size.height * 0.31, 56)
                let targetX = CGFloat(index) * 31 - CGFloat(characters.count - 1) * 15.5
                Text(String(characters[index]))
                    .font(.system(size: index == 3 ? 42 : 34, weight: .black))
                    .foregroundStyle(index == 3 ? prototypeAccent : PlayerSurface.textPrimary)
                    .rotationEffect(.degrees((1 - gather) * (Double(index) * 44 - 64)))
                    .scaleEffect((0.68 + gather * 0.32) * breathe)
                    .offset(
                        x: CGFloat(orbitX) * (1 - gather) + targetX * gather,
                        y: CGFloat(orbitY) * (1 - gather) - 20 * gather)
                    .opacity(0.3 + 0.7 * gather)
            }

            Text("都成为画面")
                .font(.system(size: 23, weight: .bold))
                .tracking(5 - 2.2 * reveal)
                .foregroundStyle(PlayerSurface.textSecondary)
                .offset(y: 34 + 12 * (1 - reveal))
                .blur(radius: 5 * (1 - reveal))
                .opacity(reveal)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(1 + 0.04 * reveal)
        .opacity(alpha)
    }

    private func prototypeDuetLine(_ text: String, time: Double, color: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                let reveal = easedProgress(
                    time,
                    start: Double(index) * 0.075,
                    duration: 0.45,
                    easing: LyricStagePrototypeTimeline.smooth)
                Text(String(character))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(color.opacity(0.64 + 0.36 * reveal))
                    .offset(y: CGFloat(sin(time * 3.6 + Double(index) * 0.75) * 3 * reveal))
                    .opacity(reveal)
            }
        }
    }

    private func gravityGlyph(
        character: Character,
        index: Int,
        drop: Double,
        drift: Double
    ) -> some View {
        let isImpact = index == 0
        let fontSize: CGFloat = isImpact ? 48 : 34
        let scaleX = isImpact ? 0.82 + 0.18 * drop : 1
        let scaleY = isImpact ? 1.18 - 0.18 * drop : 1
        let offsetX = CGFloat(index - 2) * 3 * CGFloat(drift)
        let offsetY = CGFloat(-145 * (1 - drop) + Double(index % 2) * 7 * drift)
        let foreground = isImpact ? prototypeWarm : PlayerSurface.textPrimary
        let shadow = isImpact ? prototypeWarm.opacity(0.42) : Color.clear
        return Text(String(character))
            .font(.system(size: fontSize, weight: .black))
            .foregroundStyle(foreground)
            .scaleEffect(x: scaleX, y: scaleY)
            .offset(x: offsetX, y: offsetY)
            .opacity(drop)
            .shadow(color: shadow, radius: 12)
    }

    private func easedProgress(
        _ time: Double,
        start: Double,
        duration: Double,
        easing: (Double) -> Double
    ) -> Double {
        let raw = LyricStagePrototypeTimeline.progress(time, start: start, duration: duration)
        return reduceMotion ? (raw > 0 ? 1 : 0) : easing(raw)
    }

    private var prototypeAccent: Color {
        Color(red: 0.39, green: 0.94, blue: 1.0)
    }

    private var prototypeWarm: Color {
        Color(red: 1.0, green: 0.45, blue: 0.58)
    }
}

enum YouAizuGoldenTimeline {
    static let targetBVID = "BV1XWdrBVEn3"
    static let startTime = 0.0
    static let endTime = 176.518

    enum Movement: String, Equatable {
        case instrumentalIntro
        case wakingSignal
        case tuningPulse
        case stepAndBreathe
        case doubleBlink
        case promiseWave
        case twoVoicesConverge
        case hookOne
        case hookTwo
        case hookThree
        case hookFinale
        case forwardDrive
        case conductingBreak
        case sundayArc
        case reprise
        case finalSignal
        case instrumentalOutro
        case outside
    }

    static func movement(at time: Double) -> Movement {
        switch time {
        case 0..<16.401: .instrumentalIntro
        case 16.401..<28.131: .wakingSignal
        case 28.131..<37.30: .tuningPulse
        case 37.30..<43.20: .stepAndBreathe
        case 43.20..<48.70: .doubleBlink
        case 48.70..<53.90: .promiseWave
        case 53.90..<57.70: .twoVoicesConverge
        case 57.70..<60.30: .hookOne
        case 60.30..<62.98: .hookTwo
        case 62.98..<65.68: .hookThree
        case 65.68..<67.85: .hookFinale
        case 67.85..<83.421: .forwardDrive
        case 83.421..<90.341: .conductingBreak
        case 90.341..<120.371: .sundayArc
        case 120.371..<141.721: .reprise
        case 141.721..<161.421: .finalSignal
        case 161.421...endTime: .instrumentalOutro
        default: .outside
        }
    }

    static func progress(_ time: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }

    static func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    static func backOut(_ value: Double) -> Double {
        let x = min(max(value, 0), 1) - 1
        let overshoot = 1.38
        return 1 + (overshoot + 1) * x * x * x + overshoot * x * x
    }
}

enum YouAizuAudioPerformanceMap {
    static let absoluteStart = 0.0
    static let duration = 176.518
    static let sampleRate = 21.533203125
    static let bpm = 178.206
    static let beatOrigin = 0.2438
    static let downbeatOrigin = 0.5805
    static let beatInterval = 60.0 / bpm
    static let downbeatInterval = beatInterval * 4

    private static let strongOnsets: [(time: Double, strength: Double)] = [
        (38.1525, 1), (38.4892, 1), (38.8259, 1), (39.6502, 0.914), (39.7663, 1),
        (40.1494, 1), (40.9854, 1), (41.4846, 0.949), (42.3437, 0.93), (42.843, 0.966),
        (42.959, 0.883), (43.1448, 0.91), (43.6789, 0.882), (44.1549, 1), (44.6889, 0.884),
        (45.4784, 1), (45.8151, 0.907), (46.3492, 0.984), (46.8136, 1), (47.4869, 0.92),
        (47.6843, 1), (48.1487, 1), (48.4854, 1), (48.6015, 0.882), (48.8221, 1),
        (49.1472, 1), (49.4839, 1), (50.3198, 1), (50.819, 1), (51.6781, 0.879),
        (52.1774, 1), (52.9901, 1), (53.141, 0.865), (53.5125, 0.924), (54.1162, 0.87),
        (54.3252, 1), (54.8128, 1), (55.4978, 1), (55.8113, 1), (56.1828, 1),
        (56.2989, 0.878), (57.4831, 1), (57.843, 1), (58.1449, 1), (58.4816, 1),
        (58.8183, 1), (59.1782, 1), (59.48, 1), (59.8632, 0.874), (60.1534, 1),
        (60.4785, 1), (60.8152, 1), (61.1519, 0.878), (61.2332, 0.899), (61.4886, 1),
        (61.8253, 1), (62.1503, 1), (62.4986, 1), (62.8702, 1), (63.172, 1),
        (63.4971, 1), (63.8222, 0.892), (63.9847, 0.89), (64.1473, 1), (64.4839, 1),
        (64.8206, 1), (65.1573, 1), (65.3315, 0.895), (65.494, 1), (65.8307, 1),
        (66.1674, 1), (66.4925, 1),
    ]

    private static let energy: [UInt8] = {
        let encoded = "AAAAAAAAAACbVAAAAAAAADwFGhEAADb558RYQSI0hHNYbmtvNBB3eLPvteO0IWFMexcLzefKpndtcaVNPiwTQwAAbURc6cm7q1+BWkJlrarj4va5Y2CHpktHUtBHV1iabHTpz8+1Wi5UioamvvjL3a6m1rDQfghGIBcIrpeOwf/m2KyDXGl2lmfD4NDrhnOOm2lVUEJ8aGxaSFqytL/Ua4qyqqt5JdLaxHYDAACGOlA4ZFZJDFFrO+rfy7gpRGRlgLOD8tfPkjgAA3I3H0IkAABWZm1K/9jMrjx+h4e4rNHu2eFeY42D8sXBqjFXD+OfupXGpK3MwsSXEDARveTbt4Kjc8eeo4iGf2mAnZ6PztXOr1AAAABkgWf63eurPys2mnWBilVMClKlTj//076eRABPADk1af/n8N7Fp7jHgwxhaLOZqYlYndy7tqtXAAAqJxW85NfFaXJGdkMAEAxUQ7uSJgS/7vG1onZwcnEAC+Xayc+ChnyBepufkoeMw9q/7cKVrbfct7rJfJV/29Lh2sa9p8kxGWO/AAAAAAAAAAAAABUAAAAAAFn/aH+WlXep/zmpcZZ/Z/8klnWAlGv43SB5loh448qrSaGLZsr/km11knbY/1WAYlt7iIXlgGp2dmX/eYZphHFp54e5c3OSVbnv0jeXc7LR24BYnIaLtv//bYOyhIzf3KJ1lZaK///JW36Sgv//oVWPkYv//4c8cFhAqsaTQVp2Vnn//xhRdre7/6g8mm1fZP//F4ixj4qy/zp5sZWE5/9wW3ODiLX/wwBPxqCS//+4drqAhP+xem+4gIf///FgkHaO/93VWXJrX1QAAAAAAAAAAAAAAAA="
        return Array(Data(base64Encoded: encoded) ?? Data())
    }()

    /// Full-song high-confidence spectral-flux peaks. Each record is a
    /// little-endian UInt16 in 20 ms ticks plus one normalized strength byte.
    private static let fullStrongOnsets: [(time: Double, strength: Double)] = {
        let encoded = "WQP9awP/ewP/jAP/nAP/rQP/vgP/zwP/3wP/8AP/AgT/EQT/IgT/MwT/QwT/VAT/ZAT/dQT/hgT/lgT/pwT/uAT/yAT/2QT/6gT/+gT/DAX/HAX/LQX/PgX/TgX/XwX/cAX/gAX/kQX/oQX/sgX/wgX/0wX/5QX/9AX/Bgb/Fgb/Jgb/Nwb/SAb/UQbZWQb/aQb/egb/igb/mwb/rAb/vQb/zQb/3gb/7wb//wb/EAf/IQf/Ugf/dAf/hAf/lgf/wAf8xAf/2Qf/AQj/Ggj/RAjuXgj1bQjeoAj/yQjv4gj/8wjrDQn/JQn/NQnsRgn/Twn/Zwn/eAn/fgn/iQn/kwnxmQn7rAn/1An/7Qn/FwrpMAr/NgrbWQr/Ygr2dArsgwrlnAr/tQr/1gr/4Ard5wr/+Qr/GAvaOwv/TAv/XAv/bAv/fgv/jwv/oAv/sQv4wQv/0gv/4gv/8wv9BAz/Ewz/Jgz/NQz/Rgz/Vgz/Zgz/eAz/fwzqiAz/mgz/qQz/ugz/wgz3ywz/2wz/7Az//Qz/Pw3/UQ3/Yg3/cg3/hA3vkw3/pA3/tQ3/xw3/1g3/5g3/9w3/CA7oGg7/KQ7/OQ7/Sg7/Ww7/aw7/fA7/ng7/rw7/wA7/zw7/2A7e3w7/8A7cZQ//dg//hg//lw/6ow//sw//uQ/4xA//5Q//6w///g//DBD/JxD/OBD/PhD/SRD/ThD0cRD/gRD/kRD/rhD/vhD/wxD/zxD/0xD/8BD/9hD/BhH/FhH/JxH/NBH/SRH/VRH/dRH/ehH/fxH/ixH/uBH/zRH/2hH/+hH//xH/EBL/MhL/PhL/QxLfThLrVBL/XxL/ZhLydBLvhRL/lhL/phL/whL/2RL/5RL/BRP/CxP/HBP/LBP/RxP/ThPefxPepRX/txX/xxX/2BX/6RX/+RX/Chb/GhbuKxb/PBb/TBb/XBb/bRb/fRb/jhb/oBb/sBb/wBb/0Rb/4Rbp6xbn8hb/Axf/FBfhJBf/NRf/Rhf/UBfuVxf/Xxf/aBf/cBf//hfmlRj/pBj/tRj/xRj/7xj8CBn/Mxn1ORnqSxnhWxnsaxn/dBn/jRnznxn/pRn/sBn/uBnsvxn70Rn/+hn/Exr/Ixr8PBr/VRr/Wxr/fxr/hxr/mRr/wRr/2xr/4Rr/+xr/ARvyDBv3FhvsHRv/NxvyYRv/ixv/kRvrpBv/zRv/5Rv/EBzwJxz/Uxz/ahz/lBz8rhz/vRzp0Bzn2Bz/8Rz4AB3tGh3/NB3/Qx3+Sh3gVR3/XR3/ZB3kdR3/fB32nh3/tx3/xR324R3//B3/AR7/JB7/Ph7/TR7paB7/bx7/gR7/hh7ukB7xoR7/px7oqx75sh7/vB71wh7/"
        let bytes = Array(Data(base64Encoded: encoded) ?? Data())
        guard bytes.count.isMultiple(of: 3) else { return [] }
        return stride(from: 0, to: bytes.count, by: 3).map { index in
            let ticks = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            return (Double(ticks) * 0.02, Double(bytes[index + 2]) / 255)
        }
    }()

    private static let fullEnergy: [UInt8] = {
        let encoded = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAL601sCovsS3t9DRqb27r7HN166ry7KmwdSsrqqjobXdtK3AtJyc2r6cusWbmNrOoaSmpqnMzbK4uK+hztutsc61r8LWt7e2qa2r4LqnwsSppNjCpKecnZvN0sC9zbKwzdKrpsiupMbTo5+hoqK82beyrJyJhN25o7qyqKDPxbyysKSk0tCnps6nn8rUrJ2XkIbC27+8xMOwttu5qsS8qanZxa6uq6yr1s+9ubWxr9bSvb3Jt7HK1KuzyLWuwt+1p6mmpKLYu6WopaWkZD0sHA4Hfciox8zCrHHWycPIz7g619jKxr7I0MP/+/nx9d5P+//y5+rgU/f/8uPv5n/q/fTe5eOg4vr23+vqx87//efw8uLL///t6fXu1vn/8+rw6sru/efp8OiU6/jl5OXltub54+Lr7M3M/Obl5eXWWPb14+3v3pT29uru8Oev+/Lt6unngfLy9ezy8czi/vDy8/Pn2v/q8vDu5sj/6fDu8u3P9u/x6u3pwPTz6vDz8NPq+Obz8/PZ2/vm8O/w4Lz74enw7tyl+/fp7PDpx/X67+rv6bDu+/np7e7S3/f75+ns383/+/Ln28/Q//Xt3MqrXP308ODWyJ33/umTuLa37f/35vXw2t7/++zp6tOx//7w7fLmzvj+9O3w7LH2//jr8u7K7vz77fDuv+b//vTw98zI/Pvm5+jRpP/y7PDw5871+u7x8uqo7/7s7/Lw1fD95eX09d7n9ffp7vnYvfj56fHz5ZL4+ej09fHC9Pbp6vTswfD08+/z6r7k7uno5ubF2Pff6Ors27j+3uvp6ejC+vDu7/Xtx/P16/H28sDv9ejw9fbZ4vfp8vHz3s3x59vNkEJS8t3TxqQdFcSuqq6um5u7qLqp2MvC4vPt1alsOL7Mw8bKz9Pj9uHOcy0YdOzi4+fh4dD++vj55+nm7vHs7PLs7Ono8vH8+Pz48evs7Ozm5P/7+PDw7vLy6ufm6eTX6O7s7f/2+fLu7ezo9Pb5/f369O7v9fDp7PX06urx8u/0/fn68+np7vL09f77/Pvw+/r69ebp6Ojd8fTz9P3+/Pnz7+3w9PDq//v9+u7w8vPu6+vt7+3t7Ovv+vX5+uf49/b16u79+Pjj5d/i9Onp6u3s5+Tt7/L9+vvv6ezu7Pb1+/j89+/i4e3l6+bs39fU8vDu9/36+PDt8fP09/P//fv26vDw+/r6+e/o5vL59/P49fn1+fj47ebm5P/7+/Pz8/H59/Ly8e/v8/P18v36+fPg1trd9O33/v387Ono6vP08fDt4uL27+n2/vn38OTk6+Dp5f3/+//4+Pb79Ojq8PD28/Xw7Pv59/b24+Dj6OXk//n89e/q6/Hg3OXt5+/27eXh//z89/Ls8e3p5e7+/P3x8PHv8vL19PHz8P76/fnx9fL/+Pb69vLz9P35/fj59/j13uz07KTN29Tc2tjNuN3c0dTVwJ//7Pjx9fDz+Pb37/Py7vv97+7w8vP1+/Xt8fXw7//l9PD17vD/7fjt8/Ht//v27Ozw8PL+8O3v8e76//nr7/Ls9fz27fHw8PD/9u7u8vfx/fH19PDx8P///u319PL99vrw8/L0/v3/7/Hw8/f//uzv8vLy//3g6vDs6f/y7Ozu7ev//+vo8PL5/f/t7/Dx8PX/+Orz9vPx///o8/Xy8f//4fHw8fL//+ze+PT1////7Pfy8/r/9uv19PL0///y8vD08P/19+3x6+3ihSivoRZEzMW5ssev2Nvk4d/e39zs+ePi6taGr//1/fz7+vr/8vv09fn4//v9+Pf5+fv/8/f3+Pn2//Tx9PTy+v/3+PX1+PT/9fr5/vn27//48vXz8f/7/vf1+vf5+P709vX2+f799PX1+fn/+fTz9/j0+//38/Xy8////PX39/f+//7y/v72+//59fLy8/r/9/j2+Pr4//T38vT3+P339/P29vb//+/x7/f09v/s9Pbz9Pv/9vX39Pf1//3x9/P18//86u399vH/+vDv7vr3+Pjz+Pb49ff07/Tx+Pn7+Pj79/j588+af5eUwN/U0NDO0L2C0dHGyMPm097f2dbPzMPz/uvs2dTK1Prz3s3Aucf55ujj6eTf6uLWzs3//e/t39XV9+Tu+/Lk4f349PTo5N3i8Ont6+jk9v3x/Pnu5eHjx/39687Q1NDt8Orp6ubZ4uDe08v/+vvw5trX9PPq/+/l2+zx8Pbt3b7AzrnZ183HxtTL+f/34M/W0Of/8c+loZ3W8+ro3+Lh3eDTy8Pt//3x7N3FtPzZ+f7u3OD/9fn16eDb5t/k7Orm5Pf/+P/39eXU1ar//OrY1dfA7+jp6+jl2O7f3NLU//v98eXc2uby8f/54Nfx+/Ty7ufp6+ro7+3t8+3/9/7+9u7t7u36/fTr6u/p7Orl5ubct+Lf2tfX7///9O3e2t738vj87NzW/Pj5+O/u7ebo7Pbu7/L9/vT/+vXw8/Lr+//x7O/v7PDo3cW8x8T19ebh3//57/Xo3N347PD/9OLZ9vj0+eru7ern5/nz8/Xw5uP/+vny7O7l+//y5ung4PL07/Lu7+/u7u7s7f///vPx6+vu+u7///Pu8fr78/Dm6u7t7Ozs6ujp+//9//f079jI6f/27eHYqsb05+nt7O3q2LCrq+7///Prwo5yVkTi18vHua6ikM65tKxoOnfhzcjS083I3NnT0MzHxM3JyMvGx7q+xsjIybm+wsfAwsvNw73Gs7GvpqK7y83C0dnSztDPx7/ayqTOzce+xsOp2N7X0NLMw8G7tLDPzMfBu8vCyMfFwMDDv7PTzMbXyca6xMGuvcO5uce1vsC2uLnOwLy/vL+9u7i0vcnJwsLBvcTEwMPBwry7xMTFxb+7vsC8t7e3qqnIyL65sbGvqaynpK+op6annKOwsamsr6mroaKjn8zHu62xr7e5vbGwrayuv7ixq7SxoqainKKqra6m0sW9t6+2qNLNx8nIw8PHyMbLwaKq2t7W19bR0ej9/+/s4uXl//3m2+Df3///6eXn6OP9/+rc4eng+P/t1ebY4vP/89jn5eLt//rR3erz8fv77fHn4N7//+jj6+Pk+/3h0+3g3/n/897s8ubv//XZ7PLm7P389/r8+Pf9+PH28/D1+Pr19/Tj3vr98vLx4+X1//Tl6uzp9f/45eTw6Oz//Orw8O/x/f7q8vfv5v//7O3p8e/6//fu9Ofu9f715Oro3uv99d7g4+Dg//ns7uPc2vv839fq4t/6/u3a//7k8Pvv3/z66ej29+3v7ufu08TIys7Ls+fjpXNTDw3K4czS3NfRy93X3+Hb2NfX1tTb08u7wcO+v8jHxb+/xtPQzJnb2czP0c7P5OLQ2NHAjNfZzsa2rKPCvri1vbWvqb+/xMLCwcDGrarW28O61tbRzs7NzMXLz83K28KVZ4ikpLK96///+9e3cc39/P/kp5nQ//7/776zt/76+vfs7O/v7Ojs9O3n7vTx7vv8/frm9vX38eTo//3+5ebg3/Xo5Ofo5OXk7urv//j59ert7ev59/X+/v7s3+Dr5+Pe5tve2fDr5vT///vx7O3u6/bx+v//++vs7/n+/f/w7efv//v7+fb29f359+zm5OH+//r77vDz9/Ty8O7v7+3z8vD//vvz3dDa3/Do8f////Lq6u307u/x7ebj9+vs9v////Dm6unf7d74//z/9fb2+fTt6Ozz9/L27uj8///69N7g5OXj4v3///nv6evw4tzg7urt8O/j3f7//vj16vHt59/s//7/8+zs7/Xt9fXy8vD9/f/88vX3+/b3+ff28/f+/P/5+fX49uPr8vKikuLX2NnZ1tvU1tLHxMSx9v37+uPn6Ovs5efr6+7s6fHv+/r/+fHm6O7r7N7+/f3v6Orp6eDa3uPe2t7l4+P///3z5+Xm6ez09Pr//Pbu6+/t5e/v8evu6+nq8P37/vPs5ufs8fL7/vj+8vX2+PHi4ern4evu6ej8///97eTo6/Pt7v3///zr7PD07Obp7O/s7+3r7f7+//3l9vbx8eXu//7/7uLe3u3V1drg29vh7uvv////8+7r6ur19/r++Prs3d3o6OHf49/c2O3m4vb///nu6efu7PT0+///++ny7fT7+fvt4OPv/v/++/378vr7/O3w6uX+/vv17vDw8u7v8e3u8evt7/D////24dXR3vH09P///+rg6O/w5unm4d3k5Onl7////+7j5+/t6ef7////9Pn6+/Ds6+/x+Pfy8Of6/f//7uLf4+fn5P7+//nr5+ju493j6efs8uDc1f35+/bz7+vr6OXv////9Ozo5fXv9PTx8e78/f/79Pb1//b3+fb39Pr///74+PX39d/p9OebsObRz9HVxabe2srQ1r2Lz83EyNq7Z8jUu7HezLTFyaqgwajFuuLLxrymkou0UyGwghWR0rGyvr6zlbeONCohN4XLxLW5uaJgKCceGRgXFRMPEAsKCQkHBwYEBAQEAwMCAgICAQEBAQEBAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        return Array(Data(base64Encoded: encoded) ?? Data())
    }()

    static func energy(at time: Double) -> Double {
        guard !fullEnergy.isEmpty, time >= absoluteStart, time <= absoluteStart + duration else { return 0 }
        let position = (time - absoluteStart) * sampleRate
        let lower = min(max(0, Int(position.rounded(.down))), fullEnergy.count - 1)
        let upper = min(lower + 1, fullEnergy.count - 1)
        let fraction = position - Double(lower)
        return (Double(fullEnergy[lower]) * (1 - fraction) + Double(fullEnergy[upper]) * fraction) / 255
    }

    static func beatPulse(at time: Double) -> Double {
        periodicPulse(at: time, origin: beatOrigin, interval: beatInterval, falloff: 17)
    }

    static func downbeatPulse(at time: Double) -> Double {
        periodicPulse(at: time, origin: downbeatOrigin, interval: downbeatInterval, falloff: 11)
    }

    static func onsetPulse(at time: Double) -> Double {
        guard time >= absoluteStart, time <= absoluteStart + duration else { return 0 }
        var best = 0.0
        var index = lowerBoundOnset(at: time - 0.18)
        while index < fullStrongOnsets.count {
            let onset = fullStrongOnsets[index]
            if onset.time > time + 0.001 { break }
            let delta = time - onset.time
            if delta >= -0.001, delta <= 0.18 {
                best = max(best, onset.strength * exp(-max(0, delta) * 16))
            }
            index += 1
        }
        return best
    }

    static func snappedTrigger(after lyricTime: Double, maximumDelay: Double = 0.20) -> Double {
        let onsetIndex = lowerBoundOnset(at: lyricTime)
        if fullStrongOnsets.indices.contains(onsetIndex),
           fullStrongOnsets[onsetIndex].time - lyricTime <= maximumDelay {
            let onset = fullStrongOnsets[onsetIndex]
            return onset.time
        }
        let beatNumber = ceil((lyricTime - beatOrigin) / beatInterval)
        let beat = beatOrigin + max(0, beatNumber) * beatInterval
        if beat >= lyricTime, beat - lyricTime <= maximumDelay {
            return beat
        }
        return lyricTime
    }

    static func landingPulse(at time: Double, lyricTime: Double) -> Double {
        let trigger = accentTrigger(near: lyricTime)
        let delta = time - trigger
        guard delta >= 0, delta <= 0.28 else { return 0 }
        return exp(-delta * 12)
    }

    /// Precise lyrics keep ownership of reveal time. Audio can accent the word
    /// around that instant, but it may not delay the word to a later beat.
    static func accentTrigger(near lyricTime: Double, tolerance: Double = 0.09) -> Double {
        let insertion = lowerBoundOnset(at: lyricTime)
        let candidates = [insertion - 1, insertion]
            .filter { fullStrongOnsets.indices.contains($0) }
            .map { fullStrongOnsets[$0] }
        if let onset = candidates.min(by: {
            abs($0.time - lyricTime) < abs($1.time - lyricTime)
        }), abs(onset.time - lyricTime) <= tolerance {
            return onset.time
        }
        let beatNumber = ((lyricTime - beatOrigin) / beatInterval).rounded()
        let beat = beatOrigin + max(0, beatNumber) * beatInterval
        return abs(beat - lyricTime) <= tolerance ? beat : lyricTime
    }

    private static func lowerBoundOnset(at time: Double) -> Int {
        var lower = 0
        var upper = fullStrongOnsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if fullStrongOnsets[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func periodicPulse(
        at time: Double,
        origin: Double,
        interval: Double,
        falloff: Double
    ) -> Double {
        guard time >= absoluteStart, time <= absoluteStart + duration else { return 0 }
        let phase = (time - origin).truncatingRemainder(dividingBy: interval)
        let distance = min(abs(phase), abs(interval - phase))
        return exp(-distance * falloff)
    }
}

/// A song-specific V5.2 full-song study. This deliberately bypasses the generic
/// V5.1 verb grammar so we can judge real glyph choreography before widening
/// the director contract.
struct YouAizuGoldenSampleView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: scenePhase != .active)) { tick in
            let time = playbackTime(at: tick.date)
            GeometryReader { proxy in
                Canvas { context, size in
                    draw(in: context, size: size, time: time)
                }
                .frame(width: min(340, proxy.size.width), height: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You and 合図 V5.2 全曲音频舞台")
        .accessibilityValue(YouAizuGoldenTimeline.movement(at: currentPlaybackTime).rawValue)
        .accessibilityIdentifier("youAizuGoldenStage")
    }

    private var frameInterval: TimeInterval {
        guard !reduceMotion else { return 0.20 }
        return isActive ? 1.0 / 60.0 : 1.0 / 30.0
    }

    private var currentPlaybackTime: Double {
        let value = engine.avPlayer?.currentTime().seconds ?? engine.currentTime
        return (value.isFinite ? value : engine.currentTime) + Double(engine.lyricOffsetMilliseconds) / 1_000
    }

    private func playbackTime(at tickDate: Date) -> Double {
        _ = tickDate.timeIntervalSinceReferenceDate
        return currentPlaybackTime
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        guard engine.current?.bvid == YouAizuGoldenTimeline.targetBVID,
              engine.lyrics.count >= 14 else {
            drawLabel("请先播放 You & 合図", at: CGPoint(x: size.width / 2, y: size.height / 2), size: 22, color: .white.opacity(0.72), in: context)
            return
        }

        drawSoundField(in: context, size: size, time: time)

        let movement = YouAizuGoldenTimeline.movement(at: time)
        switch movement {
        case .instrumentalIntro:
            drawInterlude(title: "You & 合図", subtitle: "AUDIO / TYPE", in: context, size: size, time: time, fadingOut: false)
        case .wakingSignal, .tuningPulse, .forwardDrive, .conductingBreak, .sundayArc:
            drawCurrentSongLine(movement: movement, in: context, size: size, time: time)
        case .stepAndBreathe:
            drawStepAndBreathe(engine.lyrics[6], in: context, size: size, time: time)
        case .doubleBlink:
            drawDoubleBlink(engine.lyrics[7], in: context, size: size, time: time)
        case .promiseWave:
            drawPromiseWave(engine.lyrics[8], in: context, size: size, time: time)
        case .twoVoicesConverge:
            drawConvergence(engine.lyrics[9], in: context, size: size, time: time)
        case .hookOne:
            drawHook(engine.lyrics[10], repetition: 0, in: context, size: size, time: time)
        case .hookTwo:
            drawHook(engine.lyrics[11], repetition: 1, in: context, size: size, time: time)
        case .hookThree:
            drawHook(engine.lyrics[12], repetition: 2, in: context, size: size, time: time)
        case .hookFinale:
            drawHook(engine.lyrics[13], repetition: 3, in: context, size: size, time: time)
        case .reprise:
            guard let index = activeLineIndex(at: time) else { return }
            switch index {
            case 31: drawStepAndBreathe(engine.lyrics[index], in: context, size: size, time: time)
            case 32: drawDoubleBlink(engine.lyrics[index], in: context, size: size, time: time)
            case 33: drawPromiseWave(engine.lyrics[index], in: context, size: size, time: time)
            case 34: drawConvergence(engine.lyrics[index], in: context, size: size, time: time)
            default: drawAdaptiveSongLine(engine.lyrics[index], index: index, movement: movement, in: context, size: size, time: time)
            }
        case .finalSignal:
            guard let index = activeLineIndex(at: time) else { return }
            if index == 39 {
                drawHook(engine.lyrics[index], repetition: 3, in: context, size: size, time: time)
            } else {
                drawAdaptiveSongLine(engine.lyrics[index], index: index, movement: movement, in: context, size: size, time: time)
            }
        case .instrumentalOutro:
            drawInterlude(title: "You & 合図", subtitle: "SIGNAL COMPLETE", in: context, size: size, time: time, fadingOut: true)
        case .outside:
            drawLabel("V5.2 · FULL SONG", at: CGPoint(x: size.width / 2, y: size.height / 2), size: 13, color: .white.opacity(0.42), tracking: 2.4, in: context)
        }
    }

    private func drawSoundField(in context: GraphicsContext, size: CGSize, time: Double) {
        let energy = YouAizuAudioPerformanceMap.energy(at: time)
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)
        let downbeat = YouAizuAudioPerformanceMap.downbeatPulse(at: time)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)

        let field = Path(ellipseIn: CGRect(
            x: size.width * 0.5 - 54 - 72 * downbeat,
            y: size.height * 0.5 - 54 - 72 * downbeat,
            width: 108 + 144 * downbeat,
            height: 108 + 144 * downbeat))
        context.stroke(
            field,
            with: .color(goldenAccent.opacity(0.025 + 0.11 * downbeat)),
            lineWidth: 0.8 + 1.4 * onset)

        for rail in 0..<3 {
            let phase = Double(rail) * 1.7
            let y = size.height * (0.31 + Double(rail) * 0.19)
                + CGFloat(sin(time * 1.35 + phase) * (2 + 8 * energy))
            let inset = CGFloat(18 + rail * 12) - CGFloat(10 * beat)
            var path = Path()
            path.move(to: CGPoint(x: inset, y: y))
            path.addCurve(
                to: CGPoint(x: size.width - inset, y: y),
                control1: CGPoint(x: size.width * 0.33, y: y - CGFloat(8 * onset)),
                control2: CGPoint(x: size.width * 0.67, y: y + CGFloat(8 * onset)))
            context.stroke(
                path,
                with: .color(.white.opacity(0.025 + energy * 0.055 + beat * 0.04)),
                lineWidth: 0.6 + 0.7 * beat)
        }

        if onset > 0.12 {
            var slash = Path()
            let x = size.width * (0.15 + 0.70 * CGFloat((time * 0.618).truncatingRemainder(dividingBy: 1)))
            slash.move(to: CGPoint(x: x - 12, y: size.height * 0.25))
            slash.addLine(to: CGPoint(x: x + 12, y: size.height * 0.75))
            context.stroke(
                slash,
                with: .color(goldenWarm.opacity(0.04 + 0.12 * onset)),
                lineWidth: 0.7 + 1.8 * onset)
        }
    }

    private func activeLineIndex(at time: Double) -> Int? {
        engine.lyrics.lastIndex(where: { $0.from <= time })
    }

    private func drawCurrentSongLine(
        movement: YouAizuGoldenTimeline.Movement,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        guard let index = activeLineIndex(at: time), engine.lyrics.indices.contains(index) else { return }
        drawAdaptiveSongLine(
            engine.lyrics[index],
            index: index,
            movement: movement,
            in: context,
            size: size,
            time: time)
    }

    private func drawInterlude(
        title: String,
        subtitle: String,
        in context: GraphicsContext,
        size: CGSize,
        time: Double,
        fadingOut: Bool
    ) {
        let energy = YouAizuAudioPerformanceMap.energy(at: time)
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)
        let downbeat = YouAizuAudioPerformanceMap.downbeatPulse(at: time)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)
        let outroFade = fadingOut
            ? 1 - YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: 168.0, duration: 8.0))
            : YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: 3.0, duration: 6.0))
        drawLabel(
            title,
            at: CGPoint(x: size.width / 2, y: size.height * 0.48),
            size: 44,
            color: .white.opacity(0.35 + 0.65 * outroFade),
            tracking: 1.5 + 5 * (1 - energy),
            rotation: -2 * onset,
            scale: (0.94 + 0.04 * beat + 0.07 * downbeat) * (0.92 + 0.08 * outroFade),
            shadow: goldenAccent.opacity(0.28 * onset),
            in: context)
        drawLabel(
            subtitle,
            at: CGPoint(x: size.width / 2, y: size.height * 0.64),
            size: 10,
            color: goldenAccent.opacity(0.24 + 0.42 * outroFade),
            tracking: 4.2,
            in: context)
    }

    private struct PositionedGoldenUnit {
        let unit: GoldenGlyphUnit
        let index: Int
        let point: CGPoint
    }

    private func layoutGlyphUnits(
        _ units: [GoldenGlyphUnit],
        fontSize: CGFloat,
        in size: CGSize
    ) -> [PositionedGoldenUnit] {
        let spacing: CGFloat = 1.4
        let maxWidth = size.width - 28
        var rows: [[(GoldenGlyphUnit, Int, CGFloat)]] = [[]]
        var rowWidth: CGFloat = 0

        for (index, unit) in units.enumerated() {
            let width = measuredWidth(unit.text, fontSize: fontSize, weight: .black)
            let proposed = rowWidth + (rows[rows.count - 1].isEmpty ? 0 : spacing) + width
            if proposed > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append((unit, index, width))
            rowWidth += (rows[rows.count - 1].count == 1 ? 0 : spacing) + width
        }

        let rowHeight = fontSize * 1.18
        let firstY = size.height / 2 - CGFloat(rows.count - 1) * rowHeight / 2
        var result: [PositionedGoldenUnit] = []
        for (rowIndex, row) in rows.enumerated() {
            let width = row.map(\.2).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            var cursor = (size.width - width) / 2
            for item in row {
                result.append(PositionedGoldenUnit(
                    unit: item.0,
                    index: item.1,
                    point: CGPoint(x: cursor + item.2 / 2, y: firstY + CGFloat(rowIndex) * rowHeight)))
                cursor += item.2 + spacing
            }
        }
        return result
    }

    private func drawAdaptiveSongLine(
        _ line: PlayerEngine.LyricLine,
        index: Int,
        movement: YouAizuGoldenTimeline.Movement,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let units = glyphUnits(for: line)
        let preferred: CGFloat = movement == .finalSignal ? 34 : (units.count > 14 ? 25 : 30)
        let layout = layoutGlyphUnits(units, fontSize: preferred, in: size)
        let energy = YouAizuAudioPerformanceMap.energy(at: time)
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)
        let downbeat = YouAizuAudioPerformanceMap.downbeatPulse(at: time)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)
        let lineFade = 1 - YouAizuGoldenTimeline.smooth(
            YouAizuGoldenTimeline.progress(time, start: max(line.from, line.to - 0.16), duration: 0.46))
        let local = max(0, time - line.from)

        for item in layout {
            let reveal = easedWordProgress(item.unit, time: time)
            let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: item.unit.from)
            let alternating: CGFloat = item.index.isMultiple(of: 2) ? -1 : 1
            var offset = CGSize.zero
            var rotation = 0.0
            var scale = 0.78 + 0.22 * reveal

            switch movement {
            case .wakingSignal:
                offset.height = 30 * (1 - reveal) + CGFloat(sin(local * 2.0 + Double(item.index) * 0.55) * 2.5 * energy)
                rotation = Double(alternating) * 5 * (1 - reveal)
            case .tuningPulse:
                offset.width = alternating * 34 * (1 - reveal)
                offset.height = CGFloat(sin(Double(item.index) * 0.72 + time * 3.2) * (2 + 5 * energy))
                rotation = Double(alternating) * (8 * onset)
            case .forwardDrive:
                offset.width = -44 * (1 - reveal)
                offset.height = CGFloat(sin(Double(item.index) * 0.85 - local * 5.0) * (3 + 7 * energy))
                rotation = Double(alternating) * 7 * (1 - reveal)
            case .conductingBreak:
                offset.height = alternating * CGFloat(12 * downbeat) - 22 * (1 - reveal)
                rotation = Double(alternating) * (9 + 10 * onset)
                scale += 0.10 * downbeat
            case .sundayArc:
                let normalizedX = Double(item.point.x / max(size.width, 1))
                offset.height = -CGFloat(sin(normalizedX * .pi) * (8 + 14 * energy))
                offset.width = alternating * 18 * (1 - reveal)
                rotation = (normalizedX - 0.5) * 10
            case .reprise:
                offset.width = alternating * 42 * (1 - reveal)
                offset.height = CGFloat(sin(local * 3.2 + Double(item.index)) * 3 * energy)
            case .finalSignal:
                offset.height = CGFloat((item.index % 3) - 1) * 18 * (1 - reveal)
                rotation = Double((item.index % 3) - 1) * 8 * (1 - reveal)
                scale += 0.08 * downbeat
            default:
                break
            }

            scale += 0.035 * beat + 0.045 * onset + 0.10 * landing
            let isSignal = item.unit.text.localizedCaseInsensitiveContains("You")
                || item.unit.text.contains("合")
                || item.unit.text.contains("図")
                || (movement == .finalSignal && item.index >= max(0, units.count - 3))
            drawGlyph(
                item.unit.text,
                at: item.point,
                fontSize: isSignal ? preferred + 2 : preferred,
                color: isSignal ? goldenAccent : .white,
                opacity: reveal * lineFade,
                offset: offset,
                scale: scale,
                rotation: rotation,
                shadow: isSignal ? goldenAccent.opacity(0.20 * onset + 0.18 * landing) : .clear,
                in: context)
        }

        if onset > 0.52 {
            var impact = Path()
            impact.move(to: CGPoint(x: 22, y: size.height * 0.76))
            impact.addLine(to: CGPoint(x: 22 + (size.width - 44) * CGFloat(min(1, 0.22 + energy)), y: size.height * 0.76))
            context.stroke(impact, with: .color(goldenWarm.opacity(0.16 + 0.28 * onset)), lineWidth: 1 + 2 * downbeat)
        }
    }

    private func drawStepAndBreathe(
        _ line: PlayerEngine.LyricLine,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let units = glyphUnits(for: line)
        let fontSize: CGFloat = 29
        let spacing: CGFloat = 1.5
        let widths = units.map { measuredWidth($0.text, fontSize: fontSize, weight: .black) }
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, units.count - 1))
        var cursor = (size.width - total) / 2
        let breathStart = units.dropFirst(max(0, units.count - 3)).first?.from ?? (line.to - 1.4)
        let breath = YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: breathStart, duration: max(0.5, line.to - breathStart)))
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)

        var rail = Path()
        rail.move(to: CGPoint(x: 16, y: size.height * 0.72))
        rail.addLine(to: CGPoint(x: 16 + (size.width - 32) * YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: line.from, duration: 1.15)), y: size.height * 0.72))
        context.stroke(rail, with: .color(goldenAccent.opacity(0.38)), lineWidth: 1.2)

        for (index, unit) in units.enumerated() {
            let reveal = easedWordProgress(unit, time: time)
            let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: unit.from)
            let isBreath = index >= max(0, units.count - 3)
            let extraSpacing = isBreath ? CGFloat(breath * 4.5 * Double(index - max(0, units.count - 3))) : 0
            let point = CGPoint(
                x: cursor + widths[index] / 2 + extraSpacing,
                y: size.height * 0.48 + CGFloat(sin(Double(index) * 0.72 + time * 2.2) * 2.2 * breath))
            drawGlyph(
                unit.text,
                at: point,
                fontSize: isBreath ? 31 : fontSize,
                color: isBreath ? goldenAccent : .white,
                opacity: reveal,
                offset: CGSize(width: -34 * (1 - reveal), height: CGFloat(index.isMultiple(of: 2) ? -18 : 18) * (1 - reveal)),
                scale: 0.82 + 0.18 * reveal + 0.045 * beat + 0.035 * onset + 0.10 * landing + (isBreath ? 0.035 * sin(time * 3.1) * breath : 0),
                rotation: Double(index % 3 - 1) * 7 * (1 - reveal),
                in: context)
            cursor += widths[index] + spacing
        }
    }

    private func drawDoubleBlink(
        _ line: PlayerEngine.LyricLine,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let units = glyphUnits(for: line)
        let blinkLocal = max(0, time - line.from)
        let blink = max(
            exp(-pow((blinkLocal - 2.30) / 0.11, 2)),
            exp(-pow((blinkLocal - 2.72) / 0.11, 2)))
        let open = reduceMotion ? 1 : max(0.08, 1 - blink)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)
        let fontSize: CGFloat = 30
        let widths = units.map { measuredWidth($0.text, fontSize: fontSize, weight: .black) }
        let total = widths.reduce(0, +) + CGFloat(max(0, units.count - 1))
        var cursor = (size.width - total) / 2

        for (index, unit) in units.enumerated() {
            let reveal = easedWordProgress(unit, time: time)
            let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: unit.from)
            drawGlyph(
                unit.text,
                at: CGPoint(x: cursor + widths[index] / 2, y: size.height * 0.50),
                fontSize: fontSize,
                color: index >= max(0, units.count - 3) ? goldenWarm : .white,
                opacity: reveal * (0.18 + 0.82 * open),
                offset: CGSize(width: 0, height: CGFloat(8 * (1 - open))),
                scaleX: 1 + 0.055 * onset + 0.08 * landing,
                scaleY: 0.14 + 0.86 * open,
                blur: 3.2 * (1 - open),
                in: context)
            cursor += widths[index] + 1
        }

        let lidY = size.height * 0.50
        var upper = Path()
        upper.move(to: CGPoint(x: 24, y: lidY - 24 * open))
        upper.addQuadCurve(to: CGPoint(x: size.width - 24, y: lidY - 24 * open), control: CGPoint(x: size.width / 2, y: lidY - 38 * open))
        context.stroke(upper, with: .color(.white.opacity(0.13 * revealForLine(line, time: time))), lineWidth: 1)
    }

    private func drawPromiseWave(
        _ line: PlayerEngine.LyricLine,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let units = glyphUnits(for: line)
        let fontSize: CGFloat = 29
        let widths = units.map { measuredWidth($0.text, fontSize: fontSize, weight: .black) }
        let total = widths.reduce(0, +) + CGFloat(max(0, units.count - 1)) * 1.5
        var cursor = (size.width - total) / 2
        let local = max(0, time - line.from)
        let energy = YouAizuAudioPerformanceMap.energy(at: time)
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)

        for (index, unit) in units.enumerated() {
            let reveal = easedWordProgress(unit, time: time)
            let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: unit.from)
            let wave = sin(Double(index) * 0.72 - local * 3.4) * (7 + 8 * energy) * reveal
            let isPromise = index >= max(0, units.count - 4)
            drawGlyph(
                unit.text,
                at: CGPoint(x: cursor + widths[index] / 2, y: size.height * 0.50 + CGFloat(wave)),
                fontSize: isPromise ? 31 : fontSize,
                color: isPromise ? goldenAccent : .white,
                opacity: reveal,
                offset: CGSize(width: 0, height: 26 * (1 - reveal)),
                scale: 0.72 + 0.28 * YouAizuGoldenTimeline.backOut(reveal) + 0.045 * beat + 0.09 * landing,
                rotation: wave * 0.32,
                in: context)
            cursor += widths[index] + 1.5
        }
    }

    private func drawConvergence(
        _ line: PlayerEngine.LyricLine,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let units = glyphUnits(for: line)
        let fontSize: CGFloat = 31
        let widths = units.map { measuredWidth($0.text, fontSize: fontSize, weight: .black) }
        let total = widths.reduce(0, +) + CGFloat(max(0, units.count - 1)) * 2
        var cursor = (size.width - total) / 2
        let converge = YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: line.from + 1.25, duration: 1.65))
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)

        for (index, unit) in units.enumerated() {
            let reveal = easedWordProgress(unit, time: time)
            let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: unit.from)
            let targetX = cursor + widths[index] / 2
            let side: CGFloat = index < units.count / 2 ? -1 : 1
            let sourceX = size.width / 2 + side * (size.width * 0.47 + CGFloat(index) * 5)
            let x = sourceX + (targetX - sourceX) * CGFloat(converge)
            let isSignal = index >= max(0, units.count - 2)
            drawGlyph(
                unit.text,
                at: CGPoint(x: x, y: size.height * 0.50 + side * 18 * (1 - converge)),
                fontSize: isSignal ? 40 : fontSize,
                color: isSignal ? goldenWarm : (side < 0 ? goldenAccent : .white),
                opacity: reveal,
                scale: 0.72 + 0.28 * converge + 0.05 * beat + 0.04 * onset + 0.11 * landing + (isSignal ? 0.08 * sin(time * 5.2) * converge : 0),
                rotation: Double(side) * 12 * (1 - converge),
                shadow: isSignal ? goldenWarm.opacity(0.32 * converge) : .clear,
                in: context)
            cursor += widths[index] + 2
        }
    }

    private func drawHook(
        _ line: PlayerEngine.LyricLine,
        repetition: Int,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let units = glyphUnits(for: line)
        let local = max(0, time - line.from)
        let hookTrigger = line.from
        let progress = YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: hookTrigger, duration: max(0.35, line.to - hookTrigger)))
        let fade = 1 - YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: line.to - 0.22, duration: 0.42))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let beat = YouAizuAudioPerformanceMap.beatPulse(at: time)
        let downbeat = YouAizuAudioPerformanceMap.downbeatPulse(at: time)
        let onset = YouAizuAudioPerformanceMap.onsetPulse(at: time)
        let audioScale = 1 + 0.065 * beat + 0.12 * downbeat + 0.075 * onset

        switch repetition {
        case 0:
            for (index, unit) in units.enumerated() {
                let reveal = easedWordProgress(unit, time: time)
                let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: unit.from)
                let sourceX: CGFloat = index == 0 ? -80 : size.width + 50 + CGFloat(index * 22)
                let targetX = center.x + CGFloat(index - 1) * 72
                drawGlyph(
                    unit.text,
                    at: CGPoint(x: sourceX + (targetX - sourceX) * CGFloat(YouAizuGoldenTimeline.backOut(reveal)), y: center.y),
                    fontSize: index == 0 ? 44 : 48,
                    color: index == 0 ? .white : goldenAccent,
                    opacity: reveal * fade,
                    scale: (0.72 + 0.28 * reveal + 0.13 * landing) * audioScale,
                    rotation: Double(index - 1) * 16 * (1 - reveal),
                    in: context)
            }
        case 1:
            for layer in 0..<3 {
                let delay = Double(layer) * 0.075
                for (index, unit) in units.enumerated() {
                    let trigger = unit.from
                    let reveal = YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: trigger + delay, duration: max(0.18, unit.to - trigger)))
                    let landing = YouAizuAudioPerformanceMap.landingPulse(at: time, lyricTime: unit.from)
                    drawGlyph(
                        unit.text,
                        at: CGPoint(x: center.x + CGFloat(index - 1) * 76 + CGFloat(layer * 7), y: center.y + CGFloat(layer * 5 - 5)),
                        fontSize: index == 0 ? 43 : 48,
                        color: layer == 0 ? .white : goldenAccent.opacity(0.26),
                        opacity: reveal * fade * (layer == 0 ? 1 : 0.55),
                        scale: (0.80 + 0.20 * reveal + 0.11 * landing) * audioScale,
                        in: context)
                }
            }
        case 2:
            let impact = YouAizuGoldenTimeline.backOut(progress)
            drawLabel(
                units.first?.text ?? line.text,
                at: CGPoint(x: center.x - 76, y: center.y - 8),
                size: 64,
                color: .white.opacity(fade),
                rotation: -5 + 5 * impact,
                scale: (1.35 - 0.35 * impact) * audioScale,
                in: context)
            let suffix = units.dropFirst().map(\.text).joined()
            drawLabel(
                suffix,
                at: CGPoint(x: center.x + 92, y: center.y + 17),
                size: 54,
                color: goldenWarm.opacity(fade),
                rotation: 7 - 7 * impact,
                scale: (0.62 + 0.38 * impact) * audioScale,
                shadow: goldenWarm.opacity(0.38),
                in: context)
        default:
            let settle = YouAizuGoldenTimeline.backOut(YouAizuGoldenTimeline.progress(local, start: 0, duration: 0.72))
            let stamp = units.map(\.text).joined()
            for layer in stride(from: 3, through: 0, by: -1) {
                drawLabel(
                    stamp,
                    at: CGPoint(x: center.x + CGFloat(layer * 3), y: center.y + CGFloat(layer * 2)),
                    size: 58,
                    color: layer == 0 ? .white.opacity(fade) : goldenAccent.opacity(0.12 * fade),
                    tracking: 7 - 4.5 * settle,
                    rotation: Double(layer) * 1.5 * (1 - settle),
                    scale: (0.58 + 0.42 * settle) * (1 + sin(time * 3.0) * 0.018) * audioScale,
                    shadow: layer == 0 ? goldenAccent.opacity(0.30) : .clear,
                    in: context)
            }
        }
    }

    private struct GoldenGlyphUnit {
        let text: String
        let from: Double
        let to: Double
    }

    private func glyphUnits(for line: PlayerEngine.LyricLine) -> [GoldenGlyphUnit] {
        if !line.words.isEmpty {
            return line.words.map { GoldenGlyphUnit(text: $0.text, from: $0.from, to: $0.to) }
        }
        let characters = Array(line.text)
        let duration = max(0.12, line.to - line.from)
        return characters.enumerated().map { index, character in
            let from = line.from + duration * Double(index) / Double(max(1, characters.count))
            let to = line.from + duration * Double(index + 1) / Double(max(1, characters.count))
            return GoldenGlyphUnit(text: String(character), from: from, to: to)
        }
    }

    private func easedWordProgress(_ unit: GoldenGlyphUnit, time: Double) -> Double {
        let duration = min(0.30, max(0.08, unit.to - unit.from))
        let raw = YouAizuGoldenTimeline.progress(time, start: unit.from, duration: duration)
        return reduceMotion ? (raw > 0 ? 1 : 0) : YouAizuGoldenTimeline.backOut(raw)
    }

    private func revealForLine(_ line: PlayerEngine.LyricLine, time: Double) -> Double {
        YouAizuGoldenTimeline.smooth(YouAizuGoldenTimeline.progress(time, start: line.from, duration: 0.45))
    }

    private func measuredWidth(_ text: String, fontSize: CGFloat, weight: UIFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: weight)]).width
    }

    private func drawGlyph(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        color: Color,
        opacity: Double,
        offset: CGSize = .zero,
        scale: Double = 1,
        scaleX: Double? = nil,
        scaleY: Double? = nil,
        rotation: Double = 0,
        blur: Double = 0,
        shadow: Color = .clear,
        in context: GraphicsContext
    ) {
        var local = context
        local.opacity = min(max(opacity, 0), 1)
        local.translateBy(x: point.x + offset.width, y: point.y + offset.height)
        local.rotate(by: .degrees(rotation))
        local.scaleBy(x: scaleX ?? scale, y: scaleY ?? scale)
        if blur > 0 { local.addFilter(.blur(radius: blur)) }
        if shadow != .clear { local.addFilter(.shadow(color: shadow, radius: 10)) }
        local.draw(
            Text(text)
                .font(.system(size: fontSize, weight: .black))
                .foregroundStyle(color),
            at: .zero,
            anchor: .center)
    }

    private func drawLabel(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        color: Color,
        tracking: CGFloat = 0,
        rotation: Double = 0,
        scale: Double = 1,
        shadow: Color = .clear,
        in context: GraphicsContext
    ) {
        var local = context
        local.translateBy(x: point.x, y: point.y)
        local.rotate(by: .degrees(rotation))
        local.scaleBy(x: scale, y: scale)
        if shadow != .clear { local.addFilter(.shadow(color: shadow, radius: 12)) }
        local.draw(
            Text(text)
                .font(.system(size: size, weight: .black))
                .tracking(tracking)
                .foregroundStyle(color),
            at: .zero,
            anchor: .center)
    }

    private var goldenAccent: Color {
        Color(red: 0.67, green: 0.92, blue: 1.0)
    }

    private var goldenWarm: Color {
        Color(red: 1.0, green: 0.76, blue: 0.66)
    }
}

// MARK: - V5.3 generic full-song choreography

enum LyricStageV53Composition: String, Equatable, Sendable {
    case stillness
    case leadingAnchor
    case trailingAnchor
    case dialogue
    case stack
    case arc
    case hero
    case hookCall
    case hookEcho
    case hookConverge
    case hookLock
}

struct LyricStageV53Scene: Equatable, Sendable {
    let lineIndex: Int
    let sectionIndex: Int
    let composition: LyricStageV53Composition
    let companionLineIndices: [Int]
    let repetitionIndex: Int?
    let repetitionCount: Int
    let isSectionStart: Bool
}

struct LyricStageV53Plan: Equatable, Sendable {
    let scenes: [LyricStageV53Scene]

    static func compile(lines: [PlayerEngine.LyricLine]) -> LyricStageV53Plan {
        guard !lines.isEmpty else { return LyricStageV53Plan(scenes: []) }

        let keys = lines.map { normalizedRepeatKey($0.text) }
        var occurrences: [String: [Int]] = [:]
        for (index, key) in keys.enumerated() where key.count >= 2 {
            occurrences[key, default: []].append(index)
        }

        var sectionIndex = 0
        var localIndex = 0
        var scenes: [LyricStageV53Scene] = []
        for index in lines.indices {
            let previous = index > 0 ? lines[index - 1] : nil
            let gap = previous.map { lines[index].from - $0.to } ?? .infinity
            let repeated = (occurrences[keys[index]]?.count ?? 0) >= 2
            let previousRepeated = index > 0 && (occurrences[keys[index - 1]]?.count ?? 0) >= 2
            let entersHook = repeated && (index == 0 || keys[index - 1] != keys[index])
            let leavesHook = !repeated && previousRepeated
            let sectionStart = index == 0 || gap > 1.35 || entersHook || leavesHook
            if index > 0, sectionStart {
                sectionIndex += 1
                localIndex = 0
            }

            let globalRepeatedIndices = occurrences[keys[index]] ?? []
            let localRepeatedIndices = contiguousRepeatCluster(
                containing: index,
                key: keys[index],
                keys: keys,
                lines: lines)
            let repeatedIndices = localRepeatedIndices.count >= 2
                ? localRepeatedIndices
                : globalRepeatedIndices
            let repetitionIndex = repeatedIndices.firstIndex(of: index)
            let composition: LyricStageV53Composition
            if let repetitionIndex, repeatedIndices.count >= 2 {
                composition = hookComposition(
                    occurrence: repetitionIndex,
                    count: repeatedIndices.count)
            } else if lines[index].overlapGroup != nil {
                composition = .dialogue
            } else {
                let glyphCount = lines[index].text.filter { !$0.isWhitespace }.count
                if glyphCount <= 4 {
                    composition = .hero
                } else if sectionStart {
                    composition = sectionIndex.isMultiple(of: 2) ? .stack : .stillness
                } else {
                    let grammar: [LyricStageV53Composition] = [
                        .leadingAnchor, .dialogue, .trailingAnchor, .arc, .stillness,
                    ]
                    composition = grammar[(localIndex + sectionIndex) % grammar.count]
                }
            }

            let companions = companionIndices(
                for: index,
                composition: composition,
                lines: lines)
            scenes.append(LyricStageV53Scene(
                lineIndex: index,
                sectionIndex: sectionIndex,
                composition: composition,
                companionLineIndices: companions,
                repetitionIndex: repetitionIndex,
                repetitionCount: repeatedIndices.count,
                isSectionStart: sectionStart))
            localIndex += 1
        }
        return LyricStageV53Plan(scenes: scenes)
    }

    func scene(for lineIndex: Int) -> LyricStageV53Scene? {
        scenes.first { $0.lineIndex == lineIndex }
    }

    func scene(at time: Double, lines: [PlayerEngine.LyricLine]) -> LyricStageV53Scene? {
        let active = LyricHighlightModel.activeLineIndices(lines: lines, at: time)
        if let lead = active.first(where: { lines[$0].voiceRole == .lead || lines[$0].voiceRole == .together }) {
            return scene(for: lead)
        }
        if let first = active.first { return scene(for: first) }
        if let latest = lines.indices.last(where: { lines[$0].from <= time }) {
            return scene(for: latest)
        }
        return scenes.first
    }

    private static func hookComposition(occurrence: Int, count: Int) -> LyricStageV53Composition {
        if occurrence == 0 { return .hookCall }
        if occurrence == count - 1 { return .hookLock }
        if occurrence == 1 { return .hookEcho }
        return .hookConverge
    }

    private static func companionIndices(
        for index: Int,
        composition: LyricStageV53Composition,
        lines: [PlayerEngine.LyricLine]
    ) -> [Int] {
        if let group = lines[index].overlapGroup {
            return lines.indices.filter { $0 != index && lines[$0].overlapGroup == group }
        }
        switch composition {
        case .dialogue:
            if index > 0 { return [index - 1] }
            return lines.indices.contains(index + 1) ? [index + 1] : []
        case .stack:
            return [index - 1, index + 1].filter { lines.indices.contains($0) }
        default:
            return []
        }
    }

    private static func contiguousRepeatCluster(
        containing index: Int,
        key: String,
        keys: [String],
        lines: [PlayerEngine.LyricLine]
    ) -> [Int] {
        guard !key.isEmpty else { return [] }
        var lower = index
        while lower > 0,
              keys[lower - 1] == key,
              lines[lower].from - lines[lower - 1].to <= 1.35 {
            lower -= 1
        }
        var upper = index
        while upper + 1 < lines.count,
              keys[upper + 1] == key,
              lines[upper + 1].from - lines[upper].to <= 1.35 {
            upper += 1
        }
        return Array(lower...upper)
    }

    private static func normalizedRepeatKey(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

/// A track-agnostic stage used to improve the reusable grammar with one stable
/// benchmark song. It deliberately has no BVID, title, line-index, or absolute
/// song-time branches: all choreography comes from lyric structure and timing.
struct LyricStageV53View: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isActive: Bool
    let onOpenLyrics: () -> Void

    var body: some View {
        let lines = engine.lyrics
        let plan = LyricStageV53Plan.compile(lines: lines)
        TimelineView(.animation(minimumInterval: frameInterval, paused: scenePhase != .active)) { tick in
            let time = playbackTime(at: tick.date)
            GeometryReader { proxy in
                Canvas { context, size in
                    draw(
                        plan: plan,
                        lines: lines,
                        in: context,
                        size: size,
                        time: time)
                }
                .frame(width: min(340, proxy.size.width), height: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenLyrics)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("V5.3 通用全曲编舞")
        .accessibilityValue(plan.scene(at: currentPlaybackTime, lines: lines)?.composition.rawValue ?? "interlude")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("lyricStageV53")
    }

    private var frameInterval: TimeInterval {
        guard !reduceMotion else { return 0.20 }
        return isActive ? 1.0 / 60.0 : 1.0 / 30.0
    }

    private var currentPlaybackTime: Double {
        let value = engine.avPlayer?.currentTime().seconds ?? engine.currentTime
        return (value.isFinite ? value : engine.currentTime) + Double(engine.lyricOffsetMilliseconds) / 1_000
    }

    private func playbackTime(at tickDate: Date) -> Double {
        _ = tickDate.timeIntervalSinceReferenceDate
        return currentPlaybackTime
    }

    private func draw(
        plan: LyricStageV53Plan,
        lines: [PlayerEngine.LyricLine],
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        guard let first = lines.first, let last = lines.last else { return }
        let palette = LyricStagePaletteResolver.resolve(
            strategy: .coverAnalogous,
            cover: engine.currentArtworkPalette)
        let primary = Color(uiColor: palette.primary.uiColor)
        let secondary = Color(uiColor: palette.secondary.uiColor)
        let accent = Color(uiColor: palette.accent.uiColor)
        let warm = Color(uiColor: palette.warm.uiColor)

        if time < first.from {
            drawInterlude(
                title: engine.current?.title ?? "",
                subtitle: engine.current?.artist ?? "",
                progress: smooth(progress(
                    time,
                    start: min(1, max(0, first.from * 0.08)),
                    duration: 2.2)),
                primary: primary,
                accent: accent,
                in: context,
                size: size)
            return
        }
        if time > last.to + 0.35 {
            drawInterlude(
                title: engine.current?.title ?? "",
                subtitle: "END",
                progress: 1 - smooth(progress(time, start: last.to + 0.35, duration: 3.5)),
                primary: primary,
                accent: accent,
                in: context,
                size: size)
            return
        }
        guard let scene = plan.scene(at: time, lines: lines),
              lines.indices.contains(scene.lineIndex) else { return }
        let line = lines[scene.lineIndex]
        drawSectionTransition(
            scene: scene,
            line: line,
            time: time,
            accent: accent,
            in: context,
            size: size)

        switch scene.composition {
        case .stillness:
            drawAnchor(
                line: line,
                alignment: .center,
                fontSize: 27,
                entrance: .zero,
                primary: primary,
                accent: accent,
                in: context,
                size: size,
                time: time)
        case .leadingAnchor:
            drawAnchor(
                line: line,
                alignment: .leading,
                fontSize: 31,
                entrance: CGSize(width: -46, height: 0),
                primary: primary,
                accent: accent,
                in: context,
                size: size,
                time: time)
        case .trailingAnchor:
            drawAnchor(
                line: line,
                alignment: .trailing,
                fontSize: 31,
                entrance: CGSize(width: 46, height: 0),
                primary: primary,
                accent: warm,
                in: context,
                size: size,
                time: time)
        case .dialogue:
            drawDialogue(
                scene: scene,
                line: line,
                lines: lines,
                primary: primary,
                secondary: secondary,
                accent: accent,
                warm: warm,
                in: context,
                size: size,
                time: time)
        case .stack:
            drawStack(
                scene: scene,
                line: line,
                lines: lines,
                primary: primary,
                secondary: secondary,
                accent: accent,
                in: context,
                size: size,
                time: time)
        case .arc:
            drawArc(
                line: line,
                primary: primary,
                accent: accent,
                in: context,
                size: size,
                time: time)
        case .hero:
            drawHero(
                line: line,
                primary: primary,
                accent: warm,
                in: context,
                size: size,
                time: time)
        case .hookCall, .hookEcho, .hookConverge, .hookLock:
            drawHook(
                scene: scene,
                line: line,
                primary: primary,
                accent: accent,
                warm: warm,
                in: context,
                size: size,
                time: time)
        }
    }

    private enum TextAlignment {
        case leading
        case center
        case trailing
    }

    private struct PositionedGlyph {
        let glyph: LyricStageGlyph
        let index: Int
        let point: CGPoint
    }

    private func drawAnchor(
        line: PlayerEngine.LyricLine,
        alignment: TextAlignment,
        fontSize: CGFloat,
        entrance: CGSize,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let glyphs = LyricStageCompiler.glyphs(for: line)
        let layout = layoutGlyphs(
            glyphs,
            fontSize: fontSize,
            alignment: alignment,
            centerY: size.height * 0.50,
            in: size)
        let lineProgress = smooth(progress(time, start: line.from, duration: 0.56))
        for item in layout {
            let reveal = reveal(item.glyph, time: time)
            let emphasized = item.index == layout.count - 1 && layout.count <= 10
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: emphasized ? fontSize + 2 : fontSize,
                color: emphasized ? accent : primary,
                opacity: 0.12 + 0.88 * reveal,
                offset: CGSize(
                    width: entrance.width * (1 - CGFloat(lineProgress)),
                    height: entrance.height * (1 - CGFloat(lineProgress))),
                scale: 0.94 + 0.06 * lineProgress,
                in: context)
        }

        if alignment != .center {
            let width = size.width * CGFloat(0.20 + 0.55 * lineProgress)
            let leading = alignment == .leading
            let x = leading ? 10 : size.width - 10 - width
            var rail = Path()
            rail.move(to: CGPoint(x: x, y: size.height * 0.78))
            rail.addLine(to: CGPoint(x: x + width, y: size.height * 0.78))
            context.stroke(rail, with: .color(accent.opacity(0.28)), lineWidth: 1.2)
        }
    }

    private func drawDialogue(
        scene: LyricStageV53Scene,
        line: PlayerEngine.LyricLine,
        lines: [PlayerEngine.LyricLine],
        primary: Color,
        secondary: Color,
        accent: Color,
        warm: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let currentOnLeading = scene.sectionIndex.isMultiple(of: 2)
        let currentAlignment: TextAlignment = currentOnLeading ? .leading : .trailing
        drawAnchor(
            line: line,
            alignment: currentAlignment,
            fontSize: 30,
            entrance: CGSize(width: currentOnLeading ? -42 : 42, height: 0),
            primary: primary,
            accent: currentOnLeading ? accent : warm,
            in: context,
            size: CGSize(width: size.width, height: size.height * 0.82),
            time: time)

        guard let companionIndex = scene.companionLineIndices.last,
              lines.indices.contains(companionIndex) else { return }
        let companion = lines[companionIndex]
        let companionAlignment: TextAlignment = currentOnLeading ? .trailing : .leading
        let glyphs = LyricStageCompiler.glyphs(for: companion)
        let layout = layoutGlyphs(
            glyphs,
            fontSize: 19,
            alignment: companionAlignment,
            centerY: size.height * 0.76,
            in: size)
        let residue = max(0, 1 - progress(time, start: max(companion.to, line.from), duration: 1.8))
        for item in layout {
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: 19,
                color: secondary,
                opacity: 0.10 + 0.36 * residue,
                offset: CGSize(width: currentOnLeading ? 12 : -12, height: 0),
                in: context)
        }
    }

    private func drawStack(
        scene: LyricStageV53Scene,
        line: PlayerEngine.LyricLine,
        lines: [PlayerEngine.LyricLine],
        primary: Color,
        secondary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let entries = (scene.companionLineIndices + [scene.lineIndex])
            .filter { lines.indices.contains($0) }
            .sorted()
        let currentPosition = entries.firstIndex(of: scene.lineIndex) ?? 0
        let startY = size.height * 0.28
        for (position, index) in entries.enumerated() {
            let isCurrent = index == scene.lineIndex
            let y = startY + CGFloat(position) * min(56, size.height * 0.22)
            let glyphs = LyricStageCompiler.glyphs(for: lines[index])
            let fontSize: CGFloat = isCurrent ? 34 : 20
            let layout = layoutGlyphs(
                glyphs,
                fontSize: fontSize,
                alignment: isCurrent ? .leading : .trailing,
                centerY: y,
                in: size)
            for item in layout {
                let opacity = isCurrent ? 0.15 + 0.85 * reveal(item.glyph, time: time) : 0.14
                drawGlyph(
                    item.glyph.text,
                    at: item.point,
                    fontSize: fontSize,
                    color: isCurrent ? (position == currentPosition ? accent : primary) : secondary,
                    opacity: opacity,
                    offset: CGSize(width: isCurrent ? -30 * (1 - CGFloat(smooth(progress(time, start: line.from, duration: 0.55)))) : 0, height: 0),
                    in: context)
            }
        }
    }

    private func drawArc(
        line: PlayerEngine.LyricLine,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let glyphs = LyricStageCompiler.glyphs(for: line)
        let count = max(1, glyphs.count)
        let usableWidth = size.width - 38
        for (index, glyph) in glyphs.enumerated() {
            let normalized = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let x = 19 + usableWidth * CGFloat(normalized)
            let y = size.height * 0.57 - CGFloat(sin(normalized * .pi) * 54)
            let reveal = reveal(glyph, time: time)
            drawGlyph(
                glyph.text,
                at: CGPoint(x: x, y: y),
                fontSize: glyphs.count > 16 ? 23 : 29,
                color: index == count / 2 ? accent : primary,
                opacity: 0.10 + 0.90 * reveal,
                offset: CGSize(width: 0, height: 34 * (1 - CGFloat(reveal))),
                scale: 0.76 + 0.24 * reveal,
                rotation: (normalized - 0.5) * 18,
                in: context)
        }
    }

    private func drawHero(
        line: PlayerEngine.LyricLine,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let glyphs = LyricStageCompiler.glyphs(for: line)
        let layout = layoutGlyphs(
            glyphs,
            fontSize: glyphs.count <= 2 ? 64 : 52,
            alignment: .center,
            centerY: size.height * 0.50,
            in: size)
        let arrival = backOut(progress(time, start: line.from, duration: 0.62))
        for item in layout {
            let reveal = reveal(item.glyph, time: time)
            let side: CGFloat = item.index.isMultiple(of: 2) ? -1 : 1
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: glyphs.count <= 2 ? 64 : 52,
                color: item.index == layout.count - 1 ? accent : primary,
                opacity: reveal,
                offset: CGSize(width: side * 94 * (1 - CGFloat(arrival)), height: CGFloat(item.index % 3 - 1) * 24 * (1 - CGFloat(arrival))),
                scale: 1.28 - 0.28 * arrival,
                rotation: Double(side) * 12 * (1 - arrival),
                in: context)
        }
    }

    private func drawHook(
        scene: LyricStageV53Scene,
        line: PlayerEngine.LyricLine,
        primary: Color,
        accent: Color,
        warm: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let glyphs = LyricStageCompiler.glyphs(for: line)
        let fontSize: CGFloat = glyphs.count > 14 ? 35 : 48
        let layout = layoutGlyphs(
            glyphs,
            fontSize: fontSize,
            alignment: .center,
            centerY: size.height * 0.50,
            in: size)
        let lineProgress = backOut(progress(time, start: line.from, duration: 0.66))

        switch scene.composition {
        case .hookCall:
            for item in layout {
                let reveal = reveal(item.glyph, time: time)
                let side: CGFloat = item.index < layout.count / 2 ? -1 : 1
                drawGlyph(
                    item.glyph.text,
                    at: item.point,
                    fontSize: fontSize,
                    color: side < 0 ? primary : accent,
                    opacity: reveal,
                    offset: CGSize(width: side * 120 * (1 - CGFloat(reveal)), height: 0),
                    scale: 0.76 + 0.24 * reveal,
                    in: context)
            }
        case .hookEcho:
            for layer in stride(from: 3, through: 0, by: -1) {
                for item in layout {
                    let reveal = reveal(item.glyph, time: time, delay: Double(layer) * 0.055)
                    drawGlyph(
                        item.glyph.text,
                        at: item.point,
                        fontSize: fontSize,
                        color: layer == 0 ? primary : accent,
                        opacity: reveal * (layer == 0 ? 1 : 0.13),
                        offset: CGSize(width: CGFloat(layer * 9), height: CGFloat(layer * 5)),
                        scale: 0.82 + 0.18 * reveal,
                        in: context)
                }
            }
        case .hookConverge:
            for item in layout {
                let reveal = reveal(item.glyph, time: time)
                let side: CGFloat = item.index < layout.count / 2 ? -1 : 1
                let source = size.width / 2 + side * (size.width * 0.72 + CGFloat(item.index) * 7)
                let x = source + (item.point.x - source) * CGFloat(lineProgress)
                drawGlyph(
                    item.glyph.text,
                    at: CGPoint(x: x, y: item.point.y + side * 18 * (1 - CGFloat(lineProgress))),
                    fontSize: fontSize,
                    color: side < 0 ? accent : warm,
                    opacity: reveal,
                    scale: 0.70 + 0.30 * lineProgress,
                    rotation: Double(side) * 14 * (1 - lineProgress),
                    in: context)
            }
        case .hookLock:
            let stampScale = 0.52 + 0.48 * lineProgress
            for layer in stride(from: 3, through: 0, by: -1) {
                for item in layout {
                    let reveal = reveal(item.glyph, time: time)
                    drawGlyph(
                        item.glyph.text,
                        at: item.point,
                        fontSize: min(62, fontSize + 8),
                        color: layer == 0 ? primary : accent,
                        opacity: reveal * (layer == 0 ? 1 : 0.10),
                        offset: CGSize(width: CGFloat(layer * 4), height: CGFloat(layer * 3)),
                        scale: stampScale,
                        rotation: Double(layer) * 1.2 * (1 - lineProgress),
                        in: context)
                }
            }
            var lockRail = Path()
            let railWidth = (size.width - 36) * CGFloat(lineProgress)
            lockRail.move(to: CGPoint(x: (size.width - railWidth) / 2, y: size.height * 0.76))
            lockRail.addLine(to: CGPoint(x: (size.width + railWidth) / 2, y: size.height * 0.76))
            context.stroke(lockRail, with: .color(warm.opacity(0.52)), lineWidth: 2)
        default:
            break
        }
    }

    private func drawSectionTransition(
        scene: LyricStageV53Scene,
        line: PlayerEngine.LyricLine,
        time: Double,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard scene.isSectionStart else { return }
        let phase = 1 - smooth(progress(time, start: line.from, duration: 0.72))
        guard phase > 0.001 else { return }
        let width = (size.width - 24) * CGFloat(phase)
        var cut = Path()
        cut.move(to: CGPoint(x: size.width - 12 - width, y: size.height * 0.18))
        cut.addLine(to: CGPoint(x: size.width - 12, y: size.height * 0.18))
        context.stroke(cut, with: .color(accent.opacity(0.42 * phase)), lineWidth: 1.4)
    }

    private func drawInterlude(
        title: String,
        subtitle: String,
        progress: Double,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize
    ) {
        let safeTitle = title.isEmpty ? "MUSIC" : title
        let fontSize: CGFloat = safeTitle.count > 18 ? 30 : 44
        let glyphs = syntheticGlyphs(for: safeTitle)
        let layout = layoutGlyphs(
            glyphs,
            fontSize: fontSize,
            alignment: .leading,
            centerY: size.height * 0.48,
            in: size)
        for item in layout {
            let stagger = min(1, max(0, progress * 1.35 - Double(item.index) * 0.035))
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: fontSize,
                color: item.index.isMultiple(of: 5) ? accent : primary,
                opacity: stagger,
                offset: CGSize(width: -56 * (1 - CGFloat(stagger)), height: 0),
                scale: 0.90 + 0.10 * stagger,
                in: context)
        }
        if !subtitle.isEmpty {
            drawLabel(
                subtitle,
                at: CGPoint(x: 18, y: size.height * 0.72),
                size: 11,
                color: accent.opacity(0.52 * progress),
                tracking: 2.4,
                anchor: .leading,
                in: context)
        }
    }

    private func layoutGlyphs(
        _ glyphs: [LyricStageGlyph],
        fontSize: CGFloat,
        alignment: TextAlignment,
        centerY: CGFloat,
        in size: CGSize
    ) -> [PositionedGlyph] {
        guard !glyphs.isEmpty else { return [] }
        let spacing: CGFloat = fontSize >= 44 ? 0.6 : 0.35
        let maxWidth = max(100, size.width - 30)
        var rows: [[(LyricStageGlyph, Int, CGFloat)]] = [[]]
        var rowWidth: CGFloat = 0
        for (index, glyph) in glyphs.enumerated() {
            let width = max(1, measuredWidth(glyph.text, fontSize: fontSize, weight: .black))
            let proposed = rowWidth + (rows[rows.count - 1].isEmpty ? 0 : spacing) + width
            if proposed > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append((glyph, index, width))
            rowWidth += (rows[rows.count - 1].count == 1 ? 0 : spacing) + width
        }

        let rowHeight = fontSize * 1.12
        let firstY = centerY - CGFloat(rows.count - 1) * rowHeight / 2
        var result: [PositionedGlyph] = []
        for (rowIndex, row) in rows.enumerated() {
            let width = row.map(\.2).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            var cursor: CGFloat
            switch alignment {
            case .leading: cursor = 15
            case .center: cursor = (size.width - width) / 2
            case .trailing: cursor = size.width - 15 - width
            }
            for item in row {
                result.append(PositionedGlyph(
                    glyph: item.0,
                    index: item.1,
                    point: CGPoint(
                        x: cursor + item.2 / 2,
                        y: firstY + CGFloat(rowIndex) * rowHeight)))
                cursor += item.2 + spacing
            }
        }
        return result
    }

    private func syntheticGlyphs(for text: String) -> [LyricStageGlyph] {
        let characters = Array(text)
        return characters.enumerated().map { index, character in
            LyricStageGlyph(
                id: index,
                text: String(character),
                from: 0,
                to: 1,
                hasRealWordTiming: false,
                wordIndex: nil,
                performanceFrom: 0,
                performanceTo: 1)
        }
    }

    private func reveal(_ glyph: LyricStageGlyph, time: Double, delay: Double = 0) -> Double {
        let start = (glyph.hasRealWordTiming ? glyph.from : glyph.performanceFrom) + delay
        let raw = progress(time, start: start, duration: min(0.34, max(0.10, glyph.to - glyph.from)))
        return reduceMotion ? (raw > 0 ? 1 : 0) : backOut(raw)
    }

    private func progress(_ time: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }

    private func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func backOut(_ value: Double) -> Double {
        let x = min(max(value, 0), 1) - 1
        let overshoot = 1.22
        return 1 + (overshoot + 1) * x * x * x + overshoot * x * x
    }

    private func measuredWidth(_ text: String, fontSize: CGFloat, weight: UIFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: weight)]).width
    }

    private func drawGlyph(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        color: Color,
        opacity: Double,
        offset: CGSize = .zero,
        scale: Double = 1,
        rotation: Double = 0,
        in context: GraphicsContext
    ) {
        var local = context
        local.opacity = min(max(opacity, 0), 1)
        local.translateBy(x: point.x + offset.width, y: point.y + offset.height)
        local.rotate(by: .degrees(rotation))
        local.scaleBy(x: scale, y: scale)
        local.draw(
            Text(text)
                .font(.system(size: fontSize, weight: .black))
                .foregroundStyle(color),
            at: .zero,
            anchor: .center)
    }

    private func drawLabel(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        color: Color,
        tracking: CGFloat,
        anchor: UnitPoint,
        in context: GraphicsContext
    ) {
        context.draw(
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .tracking(tracking)
                .foregroundStyle(color),
            at: point,
            anchor: anchor)
    }
}

private extension LyricStagePrototypeTimeline.Scene {
    var accessibilityName: String {
        switch self {
        case .assemble: "逐字聚合"
        case .gravity: "重力坠落"
        case .duet: "双声部交汇"
        case .canvas: "文字成为画面"
        }
    }
}
