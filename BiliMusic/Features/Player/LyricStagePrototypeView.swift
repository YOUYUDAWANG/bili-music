import OSLog
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

enum LyricStageV4PreparedFamily: String, Equatable, Sendable {
    case railHandoff
    case semanticLens
    case chorusMemory
    case silenceAperture
}

enum LyricStageV4PreparedDriver: String, Equatable, Sendable {
    case lyricReveal
    case wordReveal
    case structuralMoment
    case sectionEdge
}

struct LyricStageV4PreparedBudget: Equatable, Sendable {
    let transformedGlyphCount: Int
    let echoLayerCount: Int
    let estimatedTextDrawCount: Int
    let usesWrappedFallback: Bool
}

struct LyricStageV4PreparedRail: Equatable, Sendable {
    let points: [CGPoint]
    let entryOffset: CGSize
}

struct LyricStageV4PreparedAperture: Equatable, Sendable {
    let center: CGPoint
    let closedHalfGap: CGFloat
    let openHalfGap: CGFloat
    let halfLength: CGFloat
}

struct LyricStageV4PreparedTextRun: Equatable, Sendable {
    let text: String
    let point: CGPoint
    let from: Double
    let to: Double
    let hasRealWordTiming: Bool
}

struct LyricStageV4PreparedPreludeRuntime: Sendable {
    struct Window: Equatable, Sendable {
        let lineIndex: Int
        let audioFrom: Double
        let lyricTo: Double
    }

    private let windows: [Window]

    init(windows: [Window]) {
        let sorted = windows
            .filter { $0.lineIndex >= 0 && $0.audioFrom.isFinite && $0.lyricTo.isFinite }
            .sorted { lhs, rhs in
                lhs.audioFrom == rhs.audioFrom
                    ? lhs.lineIndex < rhs.lineIndex
                    : lhs.audioFrom < rhs.audioFrom
            }
        self.windows = sorted
    }

    /// Structural landmarks are in the raw audio clock while lyric boundaries
    /// are in the offset lyric clock. Keeping both inputs explicit prevents a
    /// user lyric offset from shifting beat/silence landmarks.
    func lineIndex(lyricTime: Double, audioTime: Double) -> Int? {
        guard lyricTime.isFinite, audioTime.isFinite, !windows.isEmpty else { return nil }
        var lower = 0
        var upper = windows.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if windows[middle].audioFrom <= audioTime {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        let window = windows[lower - 1]
        return lyricTime < window.lyricTo ? window.lineIndex : nil
    }
}

/// Pure preparation helpers shared by the renderer and focused tests. Everything
/// here runs when the prepared stage identity changes, never from the frame loop.
enum LyricStageV4RendererPreparation {
    static let maximumTransformedGlyphs = 48
    static let maximumTextDraws = 96
    static let maximumEchoLayers = 2

    static func budget(
        glyphCount: Int,
        requestedEchoLayers: Int
    ) -> LyricStageV4PreparedBudget {
        let safeGlyphCount = max(0, glyphCount)
        guard safeGlyphCount > 0 else {
            return LyricStageV4PreparedBudget(
                transformedGlyphCount: 0,
                echoLayerCount: 0,
                estimatedTextDrawCount: 0,
                usesWrappedFallback: true)
        }
        guard safeGlyphCount <= maximumTransformedGlyphs else {
            return LyricStageV4PreparedBudget(
                transformedGlyphCount: 0,
                echoLayerCount: 0,
                estimatedTextDrawCount: min(safeGlyphCount, maximumTextDraws),
                usesWrappedFallback: true)
        }
        let affordableEchoes = max(0, maximumTextDraws / safeGlyphCount - 1)
        let echoes = min(max(0, requestedEchoLayers), maximumEchoLayers, affordableEchoes)
        return LyricStageV4PreparedBudget(
            transformedGlyphCount: safeGlyphCount,
            echoLayerCount: echoes,
            estimatedTextDrawCount: safeGlyphCount * (1 + echoes),
            usesWrappedFallback: false)
    }

    static func driverClockTime(
        driver: LyricStageV4PreparedDriver,
        lyricTime: Double,
        audioTime: Double
    ) -> Double {
        switch driver {
        case .structuralMoment, .sectionEdge:
            return audioTime
        case .lyricReveal, .wordReveal:
            return lyricTime
        }
    }

    static func revealedTextOpacity(_ reveal: Double) -> Double {
        min(max(reveal, 0), 1)
    }

    static func focusGlyphRange(
        tokens: [StageToken],
        startTokenIndex: Int,
        endTokenIndex: Int
    ) -> ClosedRange<Int>? {
        guard startTokenIndex >= 0,
              endTokenIndex >= startTokenIndex,
              tokens.indices.contains(startTokenIndex),
              tokens.indices.contains(endTokenIndex) else { return nil }
        let selected = tokens[startTokenIndex...endTokenIndex]
        guard selected.allSatisfy({ !$0.glyphRange.isEmpty }),
              zip(selected, selected.dropFirst()).allSatisfy({ pair in
                  pair.0.glyphRange.upperBound == pair.1.glyphRange.lowerBound
              }) else {
            return nil
        }
        let lower = selected.first?.glyphRange.lowerBound ?? 0
        let upper = (selected.last?.glyphRange.upperBound ?? lower) - 1
        guard upper >= lower else { return nil }
        return lower...upper
    }

    static func semanticLensPoints(
        points: [CGPoint],
        widths: [CGFloat],
        focusGlyphRange: ClosedRange<Int>,
        scale: CGFloat = 1.12
    ) -> [CGPoint] {
        guard points.count == widths.count,
              !points.isEmpty,
              points.indices.contains(focusGlyphRange.lowerBound),
              points.indices.contains(focusGlyphRange.upperBound) else { return points }
        let safeScale = min(max(scale, 1), 1.18)
        var result = points
        var rowStart = 0
        while rowStart < points.count {
            var rowEnd = rowStart
            while rowEnd + 1 < points.count,
                  abs(points[rowEnd + 1].y - points[rowStart].y) < 0.5 {
                rowEnd += 1
            }
            let rowRange = rowStart...rowEnd
            let focused = rowRange.filter { focusGlyphRange.contains($0) }
            let totalExtra = focused.reduce(CGFloat(0)) { partial, index in
                partial + widths[index] * (safeScale - 1)
            }
            var accumulatedExtra: CGFloat = 0
            for index in rowRange {
                let ownExtra = focusGlyphRange.contains(index)
                    ? widths[index] * (safeScale - 1)
                    : 0
                result[index].x += accumulatedExtra + ownExtra / 2 - totalExtra / 2
                accumulatedExtra += ownExtra
            }
            rowStart = rowEnd + 1
        }
        return result
    }

    static func rail(
        previousBounds: CGRect?,
        currentBounds: CGRect,
        canvasSize: CGSize
    ) -> LyricStageV4PreparedRail {
        let safeCurrent = currentBounds.isNull
            ? CGRect(x: 18, y: canvasSize.height * 0.45, width: canvasSize.width - 36, height: 1)
            : currentBounds
        let source: CGPoint
        if let previousBounds, !previousBounds.isNull {
            source = CGPoint(x: previousBounds.maxX, y: previousBounds.maxY + 8)
        } else {
            source = CGPoint(x: 18, y: safeCurrent.minY - 20)
        }
        let destination = CGPoint(x: safeCurrent.minX, y: safeCurrent.maxY + 9)
        let bend = CGPoint(x: source.x, y: destination.y)
        return LyricStageV4PreparedRail(
            points: [source, bend, destination, CGPoint(x: safeCurrent.maxX, y: destination.y)],
            entryOffset: CGSize(
                width: source.x - destination.x,
                height: source.y - destination.y))
    }

    static func aperture(
        textBounds: CGRect,
        canvasSize: CGSize
    ) -> LyricStageV4PreparedAperture {
        let safeBounds = textBounds.isNull
            ? CGRect(x: 18, y: canvasSize.height * 0.42, width: canvasSize.width - 36, height: 44)
            : textBounds
        return LyricStageV4PreparedAperture(
            center: CGPoint(x: safeBounds.midX, y: safeBounds.maxY + 12),
            closedHalfGap: 3,
            openHalfGap: min(34, max(14, safeBounds.width * 0.12)),
            halfLength: min(canvasSize.width * 0.36, max(42, safeBounds.width * 0.42)))
    }
}

#if DEBUG
private final class LyricStageV53PerformanceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let logger = Logger(
        subsystem: "com.fubuki.BiliMusic",
        category: "lyric-stage-v53-performance")
    private var frameDurationsMilliseconds: [Double] = []
    private var didReportFrames = false

    func recordFrame(startNanoseconds: UInt64) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1_000_000

        lock.lock()
        guard !didReportFrames else {
            lock.unlock()
            return
        }
        frameDurationsMilliseconds.append(elapsed)
        guard frameDurationsMilliseconds.count >= 240 else {
            lock.unlock()
            return
        }

        let sorted = frameDurationsMilliseconds.sorted()
        didReportFrames = true
        lock.unlock()

        func percentile(_ fraction: Double) -> Double {
            let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded(.up)))
            return sorted[index]
        }

        let overBudget = sorted.filter { $0 > 16.67 }.count
        logger.notice(
            "V53_FRAME_SUMMARY count=\(sorted.count, privacy: .public) p50_ms=\(percentile(0.50), privacy: .public) p95_ms=\(percentile(0.95), privacy: .public) p99_ms=\(percentile(0.99), privacy: .public) max_ms=\((sorted.last ?? 0), privacy: .public) over_16_67_ms=\(overBudget, privacy: .public)")
    }

    func recordCompile(startNanoseconds: UInt64) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1_000_000
        logger.notice("V53_COMPILE duration_ms=\(elapsed, privacy: .public)")
    }
}
#endif

/// A track-agnostic stage used to improve the reusable grammar with one stable
/// benchmark song. It deliberately has no BVID, title, line-index, or absolute
/// song-time branches: all choreography comes from lyric structure and timing.
struct LyricStageV53View: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isActive: Bool
    let plan: LyricStagePlanV3
    let audioMap: AudioPerformanceMapV2?
    let v4Plan: LyricStagePlanV4?
    let onOpenLyrics: () -> Void
    @State private var layoutCache = LayoutCache()

    init(
        isActive: Bool,
        plan: LyricStagePlanV3,
        audioMap: AudioPerformanceMapV2?,
        v4Plan: LyricStagePlanV4? = nil,
        onOpenLyrics: @escaping () -> Void
    ) {
        self.isActive = isActive
        self.plan = plan
        self.audioMap = audioMap
        self.v4Plan = v4Plan
        self.onOpenLyrics = onOpenLyrics
    }

#if DEBUG
    private static let performanceSignposter = OSSignposter(
        subsystem: "com.fubuki.BiliMusic",
        category: "lyric-stage-v53-performance")
    private static let performanceSignpostsEnabled =
        ProcessInfo.processInfo.environment["BILIMUSIC_V53_PERF_SIGNPOSTS"] == "1"
    private static let performanceRecorder = LyricStageV53PerformanceRecorder()
#endif

    var body: some View {
        let lines = engine.lyrics
        let activeV4Plan = validatedV4Plan
        let v4RecipesByLineIndex = activeV4Plan?.recipeByLineIndex
        let v4Identity = activeV4Plan.map { plan in
            [
                plan.compilerVersion,
                LyricStageFingerprintV3.digest(plan.recipes),
                LyricStageFingerprintV3.digest(plan.landmarkByID),
            ].joined(separator: "/")
        } ?? "v3-visual"
        GeometryReader { proxy in
            let canvasSize = CGSize(width: min(340, proxy.size.width), height: proxy.size.height)
            let layoutIdentity = [
                plan.compilerVersion,
                plan.lyricsHash,
                LyricStageFingerprintV3.digest(plan),
                v4Identity,
                engine.current?.title ?? "",
                engine.current?.artist ?? "",
                String(format: "%.1fx%.1f", canvasSize.width, canvasSize.height),
            ].joined(separator: "/")
            let preparedStage = layoutCache.prepare(identity: layoutIdentity) {
                makePreparedStage(
                    plan: plan,
                    lines: lines,
                    title: engine.current?.title ?? "",
                    artist: engine.current?.artist ?? "",
                    size: canvasSize,
                    v4RecipesByLineIndex: v4RecipesByLineIndex,
                    v4LandmarkByID: activeV4Plan?.landmarkByID)
            }
            let resolvedPalette = LyricStagePaletteResolver.resolve(
                strategy: .coverAnalogous,
                cover: engine.currentArtworkPalette)
            let primary = Color(uiColor: resolvedPalette.primary.uiColor)
            let secondary = Color(uiColor: resolvedPalette.secondary.uiColor)
            let accent = Color(uiColor: resolvedPalette.accent.uiColor)
            let warm = Color(uiColor: resolvedPalette.warm.uiColor)
            TimelineView(.animation(minimumInterval: frameInterval, paused: !shouldAnimate)) { tick in
                let times = playbackTimes(at: tick.date)
                Canvas { context, size in
                    draw(
                        stage: preparedStage,
                        in: context,
                        size: size,
                        time: times.lyric,
                        audioTime: times.audio,
                        primary: primary,
                        secondary: secondary,
                        accent: accent,
                        warm: warm)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenLyrics)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("V5.3 通用全曲编舞")
        .accessibilityValue(currentAccessibilityValue(lines: lines))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("lyricStageV53")
    }

    private var frameInterval: TimeInterval {
        guard !reduceMotion else { return 0.20 }
        return isActive ? 1.0 / 60.0 : 1.0 / 30.0
    }

    private func currentAccessibilityValue(lines: [PlayerEngine.LyricLine]) -> String {
        guard let scene = plan.scene(at: currentPlaybackTime, lines: lines) else { return "interlude" }
#if DEBUG
        if UITestFixtures.usesStageV4PerformanceFixture,
           let recipe = validatedV4Plan?.recipe(for: scene.lineIndex) {
            return "v4:\(recipe.family.rawValue)"
        }
#endif
        return scene.composition.rawValue
    }

    private var validatedV4Plan: LyricStagePlanV4? {
        guard let v4Plan,
              v4Plan.version == LyricStagePlanV4Version.current,
              v4Plan.grammarVersion == LyricStagePlanV4Version.grammar,
              v4Plan.compilerVersion == LyricStagePlanV4Version.compiler,
              v4Plan.trackID == plan.trackID,
              v4Plan.lyricsHash == plan.lyricsHash,
              v4Plan.basePlan == plan,
              v4Plan.basePlan.trackID == plan.trackID,
              v4Plan.basePlan.lyricsHash == plan.lyricsHash,
              v4Plan.basePlan.audioSummaryHash == plan.audioSummaryHash,
              v4Plan.audioScoreHash == v4Plan.audioScore.fingerprint,
              v4Plan.audioScore.validated(lineCount: engine.lyrics.count) != nil else { return nil }
        return v4Plan
    }

    private var shouldAnimate: Bool {
        scenePhase == .active && isActive && engine.state == .playing
    }

    private var currentPlaybackTime: Double {
        currentAudioPlaybackTime + Double(engine.lyricOffsetMilliseconds) / 1_000
    }

    private var currentAudioPlaybackTime: Double {
        let value = engine.avPlayer?.currentTime().seconds ?? engine.currentTime
        return value.isFinite ? value : engine.currentTime
    }

    private func playbackTimes(at tickDate: Date) -> (lyric: Double, audio: Double) {
        var audio = currentAudioPlaybackTime
#if DEBUG
        // The performance fixture has no AVPlayer, so its playback time is otherwise
        // constant and SwiftUI can legitimately reuse the Canvas. A sub-microsecond
        // nudge keeps the selected lyric scene stable while exercising the real draw path.
        if Self.performanceSignpostsEnabled, engine.avPlayer == nil {
            audio += tickDate.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1) / 1_000_000
        }
#endif
        return (audio + Double(engine.lyricOffsetMilliseconds) / 1_000, audio)
    }

    private func draw(
        stage: PreparedStage,
        in context: GraphicsContext,
        size: CGSize,
        time: Double,
        audioTime: Double,
        primary: Color,
        secondary: Color,
        accent: Color,
        warm: Color
    ) {
#if DEBUG
        let frameStartNanoseconds = Self.performanceSignpostsEnabled
            ? DispatchTime.now().uptimeNanoseconds
            : nil
        let frameInterval = Self.performanceSignpostsEnabled
            ? Self.performanceSignposter.beginInterval("V53 Frame")
            : nil
        defer {
            if let frameInterval {
                Self.performanceSignposter.endInterval("V53 Frame", frameInterval)
            }
            if let frameStartNanoseconds {
                Self.performanceRecorder.recordFrame(startNanoseconds: frameStartNanoseconds)
            }
        }
#endif
        guard let first = stage.firstLine, let last = stage.lastLine else { return }
        let v4PreludeLineIndex = stage.v4PreludeRuntime.lineIndex(
            lyricTime: time,
            audioTime: audioTime)

        if time < first.from, v4PreludeLineIndex == nil {
            drawInterlude(
                layout: stage.interludeLayout,
                subtitle: stage.artist,
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
                layout: stage.interludeLayout,
                subtitle: "END",
                progress: 1 - smooth(progress(time, start: last.to + 0.35, duration: 3.5)),
                primary: primary,
                accent: accent,
                in: context,
                size: size)
            return
        }
        guard let sample = stage.runtime.sample(at: time) else { return }
        let selectedLineIndex = v4PreludeLineIndex ?? sample.scene.lineIndex
        guard let visual = stage.visualsByLineIndex[selectedLineIndex] else { return }
        let scene = visual.scene
        let line = visual.line
        let motifPhase = sample.motifPhase
        let audioAccent = audioAccentPulse(
            audioTime: audioTime,
            lyricTime: time,
            line: line,
            scene: scene,
            motifPhase: motifPhase)
        var stageContext = context
        if !reduceMotion {
            let entrance = time >= line.from
                ? max(0, 1 - (time - line.from) / 0.42)
                : 0
            let directiveResponse = 0.006 * entrance * scene.intensity.clamped(to: 0...1)
            let scale = 1 + CGFloat(directiveResponse)
            stageContext.translateBy(x: size.width / 2, y: size.height / 2)
            stageContext.scaleBy(x: scale, y: scale)
            stageContext.translateBy(x: -size.width / 2, y: -size.height / 2)
        }
        if let v4 = visual.v4 {
            drawV4(
                visual: v4,
                line: line,
                primary: primary,
                secondary: secondary,
                accent: accent,
                warm: warm,
                in: stageContext,
                size: size,
                lyricTime: time,
                audioTime: audioTime)
            return
        }
        drawSectionTransition(
            scene: scene,
            line: line,
            time: time,
            accent: accent,
            motifPhase: motifPhase,
            audioAccent: audioAccent,
            in: stageContext,
            size: size)

        switch scene.composition {
        case .stillness:
            drawAnchor(
                prepared: visual.primary,
                entrance: .zero,
                primary: primary,
                accent: accent,
                in: stageContext,
                size: size,
                time: time)
        case .leadingAnchor:
            drawAnchor(
                prepared: visual.primary,
                entrance: CGSize(width: -46, height: 0),
                primary: primary,
                accent: accent,
                in: stageContext,
                size: size,
                time: time)
        case .trailingAnchor:
            drawAnchor(
                prepared: visual.primary,
                entrance: CGSize(width: 46, height: 0),
                primary: primary,
                accent: warm,
                in: stageContext,
                size: size,
                time: time)
        case .dialogue:
            drawDialogue(
                visual: visual,
                primary: primary,
                secondary: secondary,
                accent: accent,
                warm: warm,
                in: stageContext,
                size: size,
                time: time)
        case .stack:
            drawStack(
                visual: visual,
                primary: primary,
                secondary: secondary,
                accent: accent,
                in: stageContext,
                size: size,
                time: time)
        case .arc:
            drawArc(
                visual: visual,
                primary: primary,
                accent: accent,
                in: stageContext,
                size: size,
                time: time)
        case .hero:
            drawHero(
                visual: visual,
                primary: primary,
                accent: warm,
                in: stageContext,
                size: size,
                time: time)
        case .hookCall, .hookEcho, .hookConverge, .hookLock:
            drawHook(
                visual: visual,
                primary: primary,
                accent: accent,
                warm: warm,
                in: stageContext,
                size: size,
                time: time)
        }
    }

    private enum TextAlignment {
        case leading
        case center
        case trailing

        var cacheKey: String {
            switch self {
            case .leading: "leading"
            case .center: "center"
            case .trailing: "trailing"
            }
        }
    }

    private struct PositionedGlyph {
        let glyph: LyricStageGlyph
        let index: Int
        let point: CGPoint
        let size: CGSize
    }

    private struct PreparedLineLayout {
        let lineIndex: Int
        let line: PlayerEngine.LyricLine
        let fontSize: CGFloat
        let alignment: TextAlignment
        let canvasSize: CGSize
        let glyphs: [LyricStageGlyph]
        let positioned: [PositionedGlyph]
    }

    private struct PreparedArcGlyph {
        let glyph: LyricStageGlyph
        let index: Int
        let point: CGPoint
        let fontSize: CGFloat
        let rotation: Double
    }

    private struct PreparedSceneVisual {
        let scene: LyricStageV53Scene
        let line: PlayerEngine.LyricLine
        let primary: PreparedLineLayout
        let auxiliary: [PreparedLineLayout]
        let arcGlyphs: [PreparedArcGlyph]
        let v4: PreparedV4SceneVisual?
    }

    private struct PreparedInterludeLayout {
        let fontSize: CGFloat
        let positioned: [PositionedGlyph]
    }

    private struct PreparedV4SceneVisual {
        let family: LyricStageV4PreparedFamily
        let driver: LyricStageV4PreparedDriver
        let topology: String
        let entrance: String
        let sustain: String
        let continuity: String
        let motifPhase: String
        let intensity: Double
        let primary: PreparedLineLayout
        let focusGlyphRange: ClosedRange<Int>?
        let lensPoints: [CGPoint]
        let focusRail: LyricStageV4PreparedRail?
        let handoffRail: LyricStageV4PreparedRail?
        let residueOffsets: [CGSize]
        let aperture: LyricStageV4PreparedAperture?
        let driverStartTime: Double
        let hasRealWordTiming: Bool
        let wrappedRuns: [LyricStageV4PreparedTextRun]
        let budget: LyricStageV4PreparedBudget

        var isHighMotion: Bool {
            family == .chorusMemory
                || family == .silenceAperture
                || ["gather", "interleave", "aperture"].contains(entrance)
        }
    }

    private struct PreparedStage {
        let runtime: LyricStagePreparedRuntimeV3
        let v4PreludeRuntime: LyricStageV4PreparedPreludeRuntime
        let visualsByLineIndex: [Int: PreparedSceneVisual]
        let firstLine: PlayerEngine.LyricLine?
        let lastLine: PlayerEngine.LyricLine?
        let interludeLayout: PreparedInterludeLayout
        let artist: String
    }

    @MainActor
    private final class LayoutCache {
        private var identity: String?
        private var stage: PreparedStage?

        func prepare(identity: String, build: () -> PreparedStage) -> PreparedStage {
            if self.identity == identity, let stage { return stage }
            self.identity = identity
            let resolved = build()
            stage = resolved
            return resolved
        }
    }

    private func makePreparedStage(
        plan: LyricStagePlanV3,
        lines: [PlayerEngine.LyricLine],
        title: String,
        artist: String,
        size: CGSize,
        v4RecipesByLineIndex: [Int: LyricStageSceneRecipeV4]?,
        v4LandmarkByID: [String: LyricStageResolvedLandmarkV4]?
    ) -> PreparedStage {
#if DEBUG
        let compileStartNanoseconds = Self.performanceSignpostsEnabled
            ? DispatchTime.now().uptimeNanoseconds
            : nil
        let compileInterval = Self.performanceSignpostsEnabled
            ? Self.performanceSignposter.beginInterval("V53 Compile")
            : nil
        defer {
            if let compileInterval {
                Self.performanceSignposter.endInterval("V53 Compile", compileInterval)
            }
            if let compileStartNanoseconds {
                Self.performanceRecorder.recordCompile(startNanoseconds: compileStartNanoseconds)
            }
        }
#endif
        var glyphsByLineID: [UUID: [LyricStageGlyph]] = [:]
        glyphsByLineID.reserveCapacity(lines.count)

        func glyphs(for line: PlayerEngine.LyricLine) -> [LyricStageGlyph] {
            if let cached = glyphsByLineID[line.id] { return cached }
            let compiled = LyricStageCompiler.glyphs(for: line)
            glyphsByLineID[line.id] = compiled
            return compiled
        }

        func preparedLayout(
            lineIndex: Int,
            proposedFontSize: CGFloat,
            alignment: TextAlignment,
            centerY: CGFloat,
            canvasSize: CGSize
        ) -> PreparedLineLayout {
            let line = lines[lineIndex]
            let compiled = glyphs(for: line)
            let fontSize = fittedFontSize(
                glyphCount: compiled.count,
                proposed: proposedFontSize,
                in: canvasSize)
            return PreparedLineLayout(
                lineIndex: lineIndex,
                line: line,
                fontSize: fontSize,
                alignment: alignment,
                canvasSize: canvasSize,
                glyphs: compiled,
                positioned: makeGlyphLayout(
                    compiled,
                    fontSize: fontSize,
                    alignment: alignment,
                    centerY: centerY,
                    in: canvasSize))
        }

        func preparedWrappedRuns(
            for layout: PreparedLineLayout
        ) -> [LyricStageV4PreparedTextRun] {
            guard !layout.positioned.isEmpty else { return [] }

            func sharesTiming(_ lhs: PositionedGlyph, _ rhs: PositionedGlyph) -> Bool {
                guard lhs.glyph.hasRealWordTiming == rhs.glyph.hasRealWordTiming else { return false }
                guard lhs.glyph.hasRealWordTiming else { return true }
                return abs(lhs.glyph.from - rhs.glyph.from) < 0.000_1
                    && abs(lhs.glyph.to - rhs.glyph.to) < 0.000_1
            }

            func makeRun(
                _ items: ArraySlice<PositionedGlyph>,
                preserveRowBreaks: Bool = false
            ) -> LyricStageV4PreparedTextRun {
                let bounds = positionedBounds(Array(items))
                let hasRealWordTiming = items.allSatisfy { $0.glyph.hasRealWordTiming }
                var text = ""
                var previousY: CGFloat?
                for item in items {
                    if preserveRowBreaks,
                       let previousY,
                       abs(previousY - item.point.y) >= 0.5 {
                        text.append("\n")
                    }
                    text.append(contentsOf: item.glyph.text)
                    previousY = item.point.y
                }
                return LyricStageV4PreparedTextRun(
                    text: text,
                    point: CGPoint(x: bounds.midX, y: bounds.midY),
                    from: hasRealWordTiming ? (items.map(\.glyph.from).min() ?? layout.line.from) : layout.line.from,
                    to: hasRealWordTiming ? (items.map(\.glyph.to).max() ?? layout.line.to) : layout.line.to,
                    hasRealWordTiming: hasRealWordTiming)
            }

            var ranges: [Range<Int>] = []
            var start = 0
            for index in layout.positioned.indices.dropFirst() {
                let previous = layout.positioned[index - 1]
                let current = layout.positioned[index]
                let sameRow = abs(previous.point.y - current.point.y) < 0.5
                if !sameRow || !sharesTiming(previous, current) {
                    ranges.append(start..<index)
                    start = index
                }
            }
            ranges.append(start..<layout.positioned.count)
            if ranges.count <= LyricStageV4RendererPreparation.maximumTextDraws {
                return ranges.map { makeRun(layout.positioned[$0]) }
            }

            // Pathological word-dense text falls back one step further to row
            // transforms. The complete string remains present and draw count is
            // bounded independently of character count.
            ranges.removeAll(keepingCapacity: true)
            start = 0
            for index in layout.positioned.indices.dropFirst() {
                if abs(layout.positioned[index - 1].point.y - layout.positioned[index].point.y) >= 0.5 {
                    ranges.append(start..<index)
                    start = index
                }
            }
            ranges.append(start..<layout.positioned.count)
            if ranges.count <= LyricStageV4RendererPreparation.maximumTextDraws {
                return ranges.map { makeRun(layout.positioned[$0]) }
            }

            let rowsPerRun = Int(ceil(
                Double(ranges.count) / Double(LyricStageV4RendererPreparation.maximumTextDraws)))
            return stride(from: 0, to: ranges.count, by: rowsPerRun).map { rowStart in
                let rowEnd = min(ranges.count, rowStart + rowsPerRun)
                let glyphStart = ranges[rowStart].lowerBound
                let glyphEnd = ranges[rowEnd - 1].upperBound
                return makeRun(
                    layout.positioned[glyphStart..<glyphEnd],
                    preserveRowBreaks: true)
            }
        }

        func preparedV4Visual(
            recipe: LyricStageSceneRecipeV4,
            scene: LyricStageV53Scene
        ) -> PreparedV4SceneVisual? {
            let lineIndex = scene.lineIndex
            guard lines.indices.contains(lineIndex),
                  recipe.lineIndex == lineIndex,
                  let family = LyricStageV4PreparedFamily(rawValue: recipe.family.rawValue) else {
                return nil
            }
            let topology = recipe.topology.rawValue
            let entrance = recipe.entrance.rawValue
            let focus = recipe.focus.rawValue
            let sustain = recipe.sustain.rawValue
            let continuity = recipe.continuity.rawValue
            let requestedDriver = LyricStageV4PreparedDriver(rawValue: recipe.driver.rawValue)
                ?? .lyricReveal
            let line = lines[lineIndex]
            let compiledGlyphs = glyphs(for: line)
            let requestedEchoLayers: Int

            switch family {
            case .railHandoff:
                guard ["anchor", "relay"].contains(topology),
                      ["settle", "slide", "gather"].contains(entrance),
                      focus == "wholeLine",
                      ["none", "railTravel", "trackingBreath"].contains(sustain),
                      ["handoff", "residue"].contains(continuity),
                      [.lyricReveal, .structuralMoment, .sectionEdge].contains(requestedDriver) else {
                    return nil
                }
                requestedEchoLayers = 0
            case .semanticLens:
                guard ["anchor", "lockup"].contains(topology),
                      ["settle", "gather"].contains(entrance),
                      focus == "tokenRange",
                      ["weightBloom", "sweep", "trackingBreath"].contains(sustain),
                      ["clear", "residue"].contains(continuity),
                      [.lyricReveal, .wordReveal].contains(requestedDriver),
                      recipe.tokenRange != nil else { return nil }
                requestedEchoLayers = 0
            case .chorusMemory:
                guard ["stack", "relay", "lockup"].contains(topology),
                      ["gather", "interleave", "settle"].contains(entrance),
                      focus == "wholeLine",
                      sustain == "echo",
                      ["residue", "accumulate"].contains(continuity),
                      [.lyricReveal, .structuralMoment, .sectionEdge].contains(requestedDriver),
                      scene.repetitionCount >= 2 else { return nil }
                requestedEchoLayers = continuity == "accumulate" ? 2 : 1
            case .silenceAperture:
                guard ["anchor", "split"].contains(topology),
                      entrance == "aperture",
                      focus == "wholeLine",
                      ["none", "weightBloom"].contains(sustain),
                      continuity == "clear",
                      [.structuralMoment, .sectionEdge].contains(requestedDriver),
                      !recipe.landmarkIDs.isEmpty else { return nil }
                requestedEchoLayers = 0
            }

            let budget = LyricStageV4RendererPreparation.budget(
                glyphCount: compiledGlyphs.count,
                requestedEchoLayers: requestedEchoLayers)

            let alignment: TextAlignment
            let proposedFontSize: CGFloat
            switch family {
            case .railHandoff:
                if topology == "relay" {
                    alignment = scene.sectionIndex.isMultiple(of: 2) ? .leading : .trailing
                } else {
                    alignment = .leading
                }
                proposedFontSize = 31
            case .semanticLens:
                alignment = topology == "lockup" ? .center : .leading
                proposedFontSize = 32
            case .chorusMemory:
                alignment = .center
                proposedFontSize = compiledGlyphs.count > 14 ? 35 : 48
            case .silenceAperture:
                alignment = .center
                proposedFontSize = 34
            }
            let primary = preparedLayout(
                lineIndex: lineIndex,
                proposedFontSize: proposedFontSize,
                alignment: alignment,
                centerY: size.height * 0.50,
                canvasSize: size)
            let wrappedRuns = budget.usesWrappedFallback
                ? preparedWrappedRuns(for: primary)
                : []
            let resolvedBudget = budget.usesWrappedFallback
                ? LyricStageV4PreparedBudget(
                    transformedGlyphCount: 0,
                    echoLayerCount: 0,
                    estimatedTextDrawCount: wrappedRuns.count,
                    usesWrappedFallback: true)
                : budget

            let focusGlyphRange: ClosedRange<Int>?
            if family == .semanticLens, let tokenRange = recipe.tokenRange {
                focusGlyphRange = LyricStageV4RendererPreparation.focusGlyphRange(
                    tokens: LyricStageTokenizer.tokens(for: line),
                    startTokenIndex: tokenRange.startTokenIndex,
                    endTokenIndex: tokenRange.endTokenIndex)
                guard let focusGlyphRange,
                      primary.positioned.indices.contains(focusGlyphRange.lowerBound),
                      primary.positioned.indices.contains(focusGlyphRange.upperBound) else { return nil }
            } else {
                focusGlyphRange = nil
            }

            let lensPoints: [CGPoint]
            let focusRail: LyricStageV4PreparedRail?
            if let focusGlyphRange {
                lensPoints = LyricStageV4RendererPreparation.semanticLensPoints(
                    points: primary.positioned.map(\.point),
                    widths: primary.positioned.map { $0.size.width },
                    focusGlyphRange: focusGlyphRange)
                let focusBounds = positionedBounds(
                    Array(primary.positioned[focusGlyphRange]))
                let y = focusBounds.maxY + 8
                focusRail = LyricStageV4PreparedRail(
                    points: [
                        CGPoint(x: focusBounds.minX, y: y),
                        CGPoint(x: focusBounds.maxX, y: y),
                    ],
                    entryOffset: .zero)
            } else {
                lensPoints = primary.positioned.map(\.point)
                focusRail = nil
            }

            let handoffRail: LyricStageV4PreparedRail?
            if family == .railHandoff {
                let candidate = recipe.companionLineIndices.first
                    ?? (lineIndex > 0 ? lineIndex - 1 : -1)
                let previousBounds: CGRect?
                if lines.indices.contains(candidate) {
                    let previous = preparedLayout(
                        lineIndex: candidate,
                        proposedFontSize: 19,
                        alignment: alignment == .leading ? .trailing : .leading,
                        centerY: size.height * 0.34,
                        canvasSize: size)
                    previousBounds = positionedBounds(previous.positioned)
                } else {
                    previousBounds = nil
                }
                handoffRail = LyricStageV4RendererPreparation.rail(
                    previousBounds: previousBounds,
                    currentBounds: positionedBounds(primary.positioned),
                    canvasSize: size)
            } else {
                handoffRail = nil
            }

            var resolvedLandmark: LyricStageResolvedLandmarkV4?
            for landmarkID in recipe.landmarkIDs {
                guard let candidate = v4LandmarkByID?[landmarkID],
                      candidate.confidence >= 0.20 else { continue }
                resolvedLandmark = candidate
                break
            }
            if family == .silenceAperture {
                guard let resolvedLandmark,
                      ["sectionStart", "silenceExit"].contains(resolvedLandmark.kind.rawValue) else {
                    return nil
                }
            }

            let hasRealWordTiming = !primary.glyphs.isEmpty
                && primary.glyphs.allSatisfy { $0.hasRealWordTiming }
            let focusHasRealWordTiming = focusGlyphRange.map { range in
                primary.glyphs[range].allSatisfy { $0.hasRealWordTiming }
            } ?? hasRealWordTiming
            let driver: LyricStageV4PreparedDriver
            let driverStartTime: Double
            switch requestedDriver {
            case .wordReveal where focusHasRealWordTiming:
                driver = .wordReveal
                if let focusGlyphRange {
                    driverStartTime = primary.glyphs[focusGlyphRange]
                        .map(\.from)
                        .min() ?? line.from
                } else {
                    driverStartTime = line.from
                }
            case .structuralMoment where resolvedLandmark != nil:
                driver = .structuralMoment
                driverStartTime = resolvedLandmark?.from ?? line.from
            case .sectionEdge where resolvedLandmark?.kind.rawValue == "sectionStart":
                driver = .sectionEdge
                driverStartTime = resolvedLandmark?.from ?? line.from
            default:
                if family == .silenceAperture { return nil }
                driver = .lyricReveal
                driverStartTime = line.from
            }

            let residueOffsets: [CGSize]
            if family == .chorusMemory {
                let candidates: [CGSize]
                switch topology {
                case "stack":
                    candidates = [CGSize(width: 0, height: 7), CGSize(width: 0, height: 14)]
                case "lockup":
                    candidates = [CGSize(width: -6, height: 4), CGSize(width: 6, height: -4)]
                default:
                    candidates = recipe.motifPhase.rawValue == "transform"
                        ? [CGSize(width: -10, height: 5), CGSize(width: 10, height: -4)]
                        : [CGSize(width: 8, height: 4), CGSize(width: 15, height: 7)]
                }
                residueOffsets = Array(candidates.prefix(resolvedBudget.echoLayerCount))
            } else {
                residueOffsets = []
            }

            let aperture = family == .silenceAperture
                ? LyricStageV4RendererPreparation.aperture(
                    textBounds: positionedBounds(primary.positioned),
                    canvasSize: size)
                : nil
            return PreparedV4SceneVisual(
                family: family,
                driver: driver,
                topology: topology,
                entrance: entrance,
                sustain: sustain,
                continuity: continuity,
                motifPhase: recipe.motifPhase.rawValue,
                intensity: recipe.intensity.clamped(to: 0.25...1),
                primary: primary,
                focusGlyphRange: focusGlyphRange,
                lensPoints: lensPoints,
                focusRail: focusRail,
                handoffRail: handoffRail,
                residueOffsets: residueOffsets,
                aperture: aperture,
                driverStartTime: driverStartTime,
                hasRealWordTiming: hasRealWordTiming,
                wrappedRuns: wrappedRuns,
                budget: resolvedBudget)
        }

        var visuals: [Int: PreparedSceneVisual] = [:]
        visuals.reserveCapacity(plan.scenes.count)
        var consecutiveHighMotionScenes = 0
        for scene in plan.scenes where lines.indices.contains(scene.lineIndex) {
            let lineIndex = scene.lineIndex
            let line = lines[lineIndex]
            let primary: PreparedLineLayout
            var auxiliary: [PreparedLineLayout] = []
            var arcGlyphs: [PreparedArcGlyph] = []

            switch scene.composition {
            case .stillness:
                primary = preparedLayout(
                    lineIndex: lineIndex,
                    proposedFontSize: 27,
                    alignment: .center,
                    centerY: size.height * 0.50,
                    canvasSize: size)
            case .leadingAnchor:
                primary = preparedLayout(
                    lineIndex: lineIndex,
                    proposedFontSize: 31,
                    alignment: .leading,
                    centerY: size.height * 0.50,
                    canvasSize: size)
            case .trailingAnchor:
                primary = preparedLayout(
                    lineIndex: lineIndex,
                    proposedFontSize: 31,
                    alignment: .trailing,
                    centerY: size.height * 0.50,
                    canvasSize: size)
            case .dialogue:
                let currentOnLeading = scene.sectionIndex.isMultiple(of: 2)
                let anchorSize = CGSize(width: size.width, height: size.height * 0.82)
                primary = preparedLayout(
                    lineIndex: lineIndex,
                    proposedFontSize: 30,
                    alignment: currentOnLeading ? .leading : .trailing,
                    centerY: anchorSize.height * 0.50,
                    canvasSize: anchorSize)
                if let companion = scene.companionLineIndices.last,
                   lines.indices.contains(companion) {
                    auxiliary = [preparedLayout(
                        lineIndex: companion,
                        proposedFontSize: 19,
                        alignment: currentOnLeading ? .trailing : .leading,
                        centerY: size.height * 0.76,
                        canvasSize: size)]
                }
            case .stack:
                let entries = (scene.companionLineIndices + [lineIndex])
                    .filter { lines.indices.contains($0) }
                    .sorted()
                let startY = size.height * 0.28
                auxiliary = entries.enumerated().map { position, index in
                    preparedLayout(
                        lineIndex: index,
                        proposedFontSize: index == lineIndex ? 34 : 20,
                        alignment: index == lineIndex ? .leading : .trailing,
                        centerY: startY + CGFloat(position) * min(56, size.height * 0.22),
                        canvasSize: CGSize(width: size.width, height: size.height * 0.55))
                }
                primary = auxiliary.first(where: { $0.lineIndex == lineIndex })
                    ?? preparedLayout(
                        lineIndex: lineIndex,
                        proposedFontSize: 34,
                        alignment: .leading,
                        centerY: startY,
                        canvasSize: CGSize(width: size.width, height: size.height * 0.55))
            case .arc:
                let compiled = glyphs(for: line)
                let count = max(1, compiled.count)
                let usableWidth = size.width - 38
                arcGlyphs = compiled.enumerated().map { index, glyph in
                    let normalized = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                    return PreparedArcGlyph(
                        glyph: glyph,
                        index: index,
                        point: CGPoint(
                            x: 19 + usableWidth * CGFloat(normalized),
                            y: size.height * 0.57 - CGFloat(sin(normalized * .pi) * 54)),
                        fontSize: compiled.count > 16 ? 23 : 29,
                        rotation: (normalized - 0.5) * 18)
                }
                primary = PreparedLineLayout(
                    lineIndex: lineIndex,
                    line: line,
                    fontSize: compiled.count > 16 ? 23 : 29,
                    alignment: .center,
                    canvasSize: size,
                    glyphs: compiled,
                    positioned: [])
            case .hero:
                let count = glyphs(for: line).count
                primary = preparedLayout(
                    lineIndex: lineIndex,
                    proposedFontSize: count <= 2 ? 64 : 52,
                    alignment: .center,
                    centerY: size.height * 0.50,
                    canvasSize: size)
            case .hookCall, .hookEcho, .hookConverge, .hookLock:
                let count = glyphs(for: line).count
                primary = preparedLayout(
                    lineIndex: lineIndex,
                    proposedFontSize: count > 14 ? 35 : 48,
                    alignment: .center,
                    centerY: size.height * 0.50,
                    canvasSize: size)
            }

            var v4 = v4RecipesByLineIndex?[lineIndex].flatMap { recipe in
                preparedV4Visual(recipe: recipe, scene: scene)
            }
            if v4?.isHighMotion == true {
                if consecutiveHighMotionScenes >= 2 {
                    v4 = nil
                    consecutiveHighMotionScenes = 0
                } else {
                    consecutiveHighMotionScenes += 1
                }
            } else {
                consecutiveHighMotionScenes = 0
            }
            visuals[lineIndex] = PreparedSceneVisual(
                scene: scene,
                line: line,
                primary: primary,
                auxiliary: auxiliary,
                arcGlyphs: arcGlyphs,
                v4: v4)
        }

        let safeTitle = title.isEmpty ? "MUSIC" : title
        let titleFontSize: CGFloat = safeTitle.count > 18 ? 30 : 44
        let titleGlyphs = syntheticGlyphs(for: safeTitle)
        let interlude = PreparedInterludeLayout(
            fontSize: titleFontSize,
            positioned: makeGlyphLayout(
                titleGlyphs,
                fontSize: titleFontSize,
                alignment: .leading,
                centerY: size.height * 0.48,
                in: size))
        let preludeWindows = visuals.values.compactMap { visual -> LyricStageV4PreparedPreludeRuntime.Window? in
            guard let v4 = visual.v4,
                  v4.family == .silenceAperture,
                  !v4.budget.usesWrappedFallback else { return nil }
            return LyricStageV4PreparedPreludeRuntime.Window(
                lineIndex: visual.scene.lineIndex,
                audioFrom: v4.driverStartTime,
                lyricTo: visual.line.from)
        }
        return PreparedStage(
            runtime: LyricStagePreparedRuntimeV3(plan: plan, lines: lines),
            v4PreludeRuntime: LyricStageV4PreparedPreludeRuntime(windows: preludeWindows),
            visualsByLineIndex: visuals,
            firstLine: lines.first,
            lastLine: lines.last,
            interludeLayout: interlude,
            artist: artist)
    }

    private func drawV4(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        primary: Color,
        secondary: Color,
        accent: Color,
        warm: Color,
        in context: GraphicsContext,
        size: CGSize,
        lyricTime: Double,
        audioTime: Double
    ) {
        if visual.budget.usesWrappedFallback {
            drawV4WrappedFallback(
                visual: visual,
                line: line,
                primary: primary,
                accent: accent,
                in: context,
                lyricTime: lyricTime)
            return
        }
        switch visual.family {
        case .railHandoff:
            drawV4RailHandoff(
                visual: visual,
                line: line,
                primary: primary,
                accent: accent,
                in: context,
                lyricTime: lyricTime,
                audioTime: audioTime)
        case .semanticLens:
            drawV4SemanticLens(
                visual: visual,
                line: line,
                primary: primary,
                secondary: secondary,
                accent: accent,
                in: context,
                lyricTime: lyricTime,
                audioTime: audioTime)
        case .chorusMemory:
            drawV4ChorusMemory(
                visual: visual,
                line: line,
                primary: primary,
                accent: accent,
                warm: warm,
                in: context,
                lyricTime: lyricTime,
                audioTime: audioTime)
        case .silenceAperture:
            drawV4SilenceAperture(
                visual: visual,
                line: line,
                primary: primary,
                secondary: secondary,
                accent: accent,
                in: context,
                size: size,
                lyricTime: lyricTime,
                audioTime: audioTime)
        }
    }

    private func drawV4WrappedFallback(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        lyricTime: Double
    ) {
        let linePhase = smooth(progress(lyricTime, start: line.from, duration: 0.42))
        for run in visual.wrappedRuns {
            let raw = progress(
                lyricTime,
                start: run.hasRealWordTiming ? run.from : line.from,
                duration: min(0.34, max(0.10, run.to - run.from)))
            let reveal = reduceMotion ? (raw > 0 ? 1 : 0) : backOut(raw)
            guard reveal > 0.001 else { continue }
            let offset = reduceMotion
                ? CGSize.zero
                : CGSize(width: -18 * (1 - CGFloat(linePhase)), height: 0)
            drawGlyph(
                run.text,
                at: run.point,
                fontSize: visual.primary.fontSize,
                color: primary,
                opacity: LyricStageV4RendererPreparation.revealedTextOpacity(reveal),
                offset: offset,
                scale: 1,
                weight: .bold,
                in: context)
        }
        guard linePhase > 0.001,
              let first = visual.wrappedRuns.first,
              let last = visual.wrappedRuns.last else { return }
        var rail = Path()
        let railY = max(first.point.y, last.point.y) + visual.primary.fontSize * 0.72
        rail.move(to: CGPoint(x: 16, y: railY))
        rail.addLine(to: CGPoint(x: 16 + 54 * CGFloat(linePhase), y: railY))
        context.stroke(
            rail,
            with: .color(accent.opacity(0.32 * linePhase)),
            lineWidth: 1.1)
    }

    private func drawV4RailHandoff(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        lyricTime: Double,
        audioTime: Double
    ) {
        let phase = v4Phase(
            visual: visual,
            line: line,
            lyricTime: lyricTime,
            audioTime: audioTime,
            duration: 0.58)
        if let rail = visual.handoffRail {
            drawV4Rail(
                rail,
                progress: reduceMotion ? (lyricTime >= line.from ? 1 : 0) : phase,
                color: accent.opacity(0.24 + 0.30 * phase),
                lineWidth: 1.2 + visual.intensity * 0.8,
                in: context)
        }
        let travel = reduceMotion ? 1 : phase
        let entry = visual.handoffRail?.entryOffset ?? .zero
        for item in visual.primary.positioned {
            let glyphReveal = v4GlyphReveal(
                item.glyph,
                visual: visual,
                line: line,
                lyricTime: lyricTime)
            let isRevealed = glyphReveal > 0.001
            var offset = CGSize(
                width: entry.width * (1 - CGFloat(travel)),
                height: entry.height * (1 - CGFloat(travel)))
            if visual.entrance == "gather", !reduceMotion {
                let side: CGFloat = item.index < visual.primary.positioned.count / 2 ? -1 : 1
                offset.width += side * 26 * (1 - CGFloat(phase))
            } else if visual.entrance == "settle", !reduceMotion {
                offset.height += 10 * (1 - CGFloat(phase))
            }
            if visual.sustain == "trackingBreath", !reduceMotion, isRevealed {
                let direction: CGFloat = item.index.isMultiple(of: 2) ? -1 : 1
                offset.width += direction
                    * 1.1
                    * CGFloat(LyricStageCalmMotion.oneShotPulse(phase))
            }
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: visual.primary.fontSize,
                color: item.index == visual.primary.positioned.count - 1 ? accent : primary,
                opacity: LyricStageV4RendererPreparation.revealedTextOpacity(glyphReveal),
                offset: offset,
                scale: 1,
                in: context)
        }
    }

    private func drawV4SemanticLens(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        primary: Color,
        secondary: Color,
        accent: Color,
        in context: GraphicsContext,
        lyricTime: Double,
        audioTime: Double
    ) {
        guard let focus = visual.focusGlyphRange else { return }
        let phase = v4Phase(
            visual: visual,
            line: line,
            lyricTime: lyricTime,
            audioTime: audioTime,
            duration: 0.50)
        for item in visual.primary.positioned {
            let glyphReveal = v4GlyphReveal(
                item.glyph,
                visual: visual,
                line: line,
                lyricTime: lyricTime)
            let focused = focus.contains(item.index)
            let focusPhase = visual.driver == .wordReveal && focused
                ? glyphReveal
                : phase
            let layoutPhase = reduceMotion ? (focusPhase > 0 ? 1 : 0) : focusPhase
            let target = visual.lensPoints[item.index]
            let position = CGPoint(
                x: item.point.x + (target.x - item.point.x) * CGFloat(layoutPhase),
                y: item.point.y + (target.y - item.point.y) * CGFloat(layoutPhase))
            var offset = CGSize.zero
            if visual.sustain == "trackingBreath", focused, !reduceMotion, glyphReveal > 0 {
                offset.height = -1.2 * CGFloat(LyricStageCalmMotion.oneShotPulse(focusPhase))
            }
            let bloom = focused ? focusPhase : 0
            let scale = reduceMotion
                ? 1
                : 1 + (visual.sustain == "weightBloom" ? 0.12 : 0.06) * bloom
            let color: Color
            if focused {
                if visual.sustain == "sweep" {
                    let span = max(1, focus.upperBound - focus.lowerBound)
                    let localPosition = Double(item.index - focus.lowerBound) / Double(span)
                    let sweep = min(max(phase * 1.35 - localPosition * 0.35, 0), 1)
                    color = sweep >= 0.35 ? accent : primary
                } else {
                    color = accent
                }
            } else {
                color = phase > 0.35 ? secondary.opacity(0.82) : primary
            }
            drawGlyph(
                item.glyph.text,
                at: position,
                fontSize: visual.primary.fontSize,
                color: color,
                opacity: LyricStageV4RendererPreparation.revealedTextOpacity(glyphReveal),
                offset: offset,
                scale: scale,
                weight: focused ? .black : .semibold,
                in: context)
        }
        if let rail = visual.focusRail {
            drawV4Rail(
                rail,
                progress: reduceMotion ? (lyricTime >= line.from ? 1 : 0) : phase,
                color: accent.opacity(0.18 + 0.46 * phase),
                lineWidth: 1.1 + visual.intensity * 0.9,
                in: context)
        }
    }

    private func drawV4ChorusMemory(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        primary: Color,
        accent: Color,
        warm: Color,
        in context: GraphicsContext,
        lyricTime: Double,
        audioTime: Double
    ) {
        let phase = v4Phase(
            visual: visual,
            line: line,
            lyricTime: lyricTime,
            audioTime: audioTime,
            duration: 0.64)
        if !reduceMotion {
            for (layer, residueOffset) in visual.residueOffsets.enumerated() {
                for item in visual.primary.positioned {
                    let glyphReveal = v4GlyphReveal(
                        item.glyph,
                        visual: visual,
                        line: line,
                        lyricTime: lyricTime,
                        delay: Double(layer + 1) * 0.045)
                    guard glyphReveal > 0.001 else { continue }
                    drawGlyph(
                        item.glyph.text,
                        at: item.point,
                        fontSize: visual.primary.fontSize,
                        color: layer.isMultiple(of: 2) ? accent : warm,
                        opacity: LyricStageV4RendererPreparation.revealedTextOpacity(glyphReveal)
                            * (layer == 0 ? 0.16 : 0.09),
                        offset: residueOffset,
                        scale: 0.98 + 0.02 * phase,
                        in: context)
                }
            }
        }
        for item in visual.primary.positioned {
            let glyphReveal = v4GlyphReveal(
                item.glyph,
                visual: visual,
                line: line,
                lyricTime: lyricTime)
            let side: CGFloat = item.index < visual.primary.positioned.count / 2 ? -1 : 1
            var offset = CGSize.zero
            if !reduceMotion {
                switch visual.entrance {
                case "gather":
                    offset.width = side * 62 * (1 - CGFloat(phase))
                case "interleave":
                    offset.height = (item.index.isMultiple(of: 2) ? -22 : 22) * (1 - CGFloat(phase))
                default:
                    offset.height = 9 * (1 - CGFloat(phase))
                }
            }
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: visual.primary.fontSize,
                color: visual.motifPhase == "resolve" ? warm : primary,
                opacity: LyricStageV4RendererPreparation.revealedTextOpacity(glyphReveal),
                offset: offset,
                scale: reduceMotion ? 1 : 0.94 + 0.06 * phase,
                in: context)
        }
    }

    private func drawV4SilenceAperture(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        primary: Color,
        secondary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        lyricTime: Double,
        audioTime: Double
    ) {
        let aperturePhase = smooth(progress(
            audioTime,
            start: visual.driverStartTime,
            duration: 0.62))
        if let aperture = visual.aperture {
            drawV4Aperture(
                aperture,
                progress: reduceMotion
                    ? (audioTime >= visual.driverStartTime ? 1 : 0)
                    : aperturePhase,
                color: accent.opacity(0.18 + 0.44 * aperturePhase),
                lineWidth: 1.0 + visual.intensity * 0.9,
                in: context)
        }
        guard lyricTime >= line.from else { return }
        let linePhase = smooth(progress(lyricTime, start: line.from, duration: 0.48))
        for item in visual.primary.positioned {
            let glyphReveal = v4GlyphReveal(
                item.glyph,
                visual: visual,
                line: line,
                lyricTime: lyricTime)
            let bloom = visual.sustain == "weightBloom" ? linePhase : 0
            let splitOffset: CGSize
            if visual.topology == "split", !reduceMotion {
                let side: CGFloat = item.index < visual.primary.positioned.count / 2 ? -1 : 1
                splitOffset = CGSize(width: side * 22 * (1 - CGFloat(linePhase)), height: 0)
            } else {
                splitOffset = .zero
            }
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: visual.primary.fontSize,
                color: glyphReveal > 0 ? primary : secondary,
                opacity: LyricStageV4RendererPreparation.revealedTextOpacity(glyphReveal),
                offset: splitOffset,
                scale: reduceMotion || glyphReveal <= 0
                    ? 1
                    : 0.97 + 0.03 * linePhase + 0.018 * bloom,
                in: context)
        }
        _ = size
    }

    private func v4Phase(
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        lyricTime: Double,
        audioTime: Double,
        duration: Double
    ) -> Double {
        let start = visual.driver == .wordReveal
            ? max(line.from, visual.driverStartTime)
            : visual.driverStartTime
        let clockTime = LyricStageV4RendererPreparation.driverClockTime(
            driver: visual.driver,
            lyricTime: lyricTime,
            audioTime: audioTime)
        return smooth(progress(clockTime, start: start, duration: duration))
    }

    private func v4GlyphReveal(
        _ glyph: LyricStageGlyph,
        visual: PreparedV4SceneVisual,
        line: PlayerEngine.LyricLine,
        lyricTime: Double,
        delay: Double = 0
    ) -> Double {
        guard !visual.hasRealWordTiming else {
            return reveal(glyph, time: lyricTime, delay: delay)
        }
        let raw = progress(
            lyricTime,
            start: line.from + delay,
            duration: min(0.34, max(0.16, line.to - line.from)))
        return reduceMotion ? (raw > 0 ? 1 : 0) : backOut(raw)
    }

    private func drawV4Rail(
        _ rail: LyricStageV4PreparedRail,
        progress: Double,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext
    ) {
        guard rail.points.count >= 2 else { return }
        let segmentCount = rail.points.count - 1
        for index in 0..<segmentCount {
            let local = min(max(progress * Double(segmentCount) - Double(index), 0), 1)
            guard local > 0.001 else { continue }
            let start = rail.points[index]
            let end = rail.points[index + 1]
            var path = Path()
            path.move(to: start)
            path.addLine(to: CGPoint(
                x: start.x + (end.x - start.x) * CGFloat(local),
                y: start.y + (end.y - start.y) * CGFloat(local)))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func drawV4Aperture(
        _ aperture: LyricStageV4PreparedAperture,
        progress: Double,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext
    ) {
        let phase = CGFloat(min(max(progress, 0), 1))
        let gap = aperture.closedHalfGap
            + (aperture.openHalfGap - aperture.closedHalfGap) * phase
        let length = aperture.halfLength * (0.55 + 0.45 * phase)
        var path = Path()
        path.move(to: CGPoint(x: aperture.center.x - gap - length, y: aperture.center.y))
        path.addLine(to: CGPoint(x: aperture.center.x - gap, y: aperture.center.y))
        path.move(to: CGPoint(x: aperture.center.x + gap, y: aperture.center.y))
        path.addLine(to: CGPoint(x: aperture.center.x + gap + length, y: aperture.center.y))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawAnchor(
        prepared: PreparedLineLayout,
        entrance: CGSize,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let line = prepared.line
        let layout = prepared.positioned
        let resolvedFontSize = prepared.fontSize
        let lineProgress = smooth(progress(time, start: line.from, duration: 0.56))
        for item in layout {
            let reveal = reveal(item.glyph, time: time)
            let emphasized = item.index == layout.count - 1 && layout.count <= 10
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: emphasized ? resolvedFontSize + 2 : resolvedFontSize,
                color: emphasized ? accent : primary,
                opacity: 0.12 + 0.88 * reveal,
                offset: CGSize(
                    width: entrance.width * (1 - CGFloat(lineProgress)),
                    height: entrance.height * (1 - CGFloat(lineProgress))),
                scale: 0.94 + 0.06 * lineProgress,
                in: context)
        }

        if prepared.alignment != .center {
            let railSize = prepared.canvasSize
            let width = railSize.width * CGFloat(0.20 + 0.55 * lineProgress)
            let leading = prepared.alignment == .leading
            let x = leading ? 10 : railSize.width - 10 - width
            var rail = Path()
            rail.move(to: CGPoint(x: x, y: railSize.height * 0.78))
            rail.addLine(to: CGPoint(x: x + width, y: railSize.height * 0.78))
            context.stroke(rail, with: .color(accent.opacity(0.28)), lineWidth: 1.2)
        }
    }

    private func drawDialogue(
        visual: PreparedSceneVisual,
        primary: Color,
        secondary: Color,
        accent: Color,
        warm: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let scene = visual.scene
        let line = visual.line
        let currentOnLeading = scene.sectionIndex.isMultiple(of: 2)
        drawAnchor(
            prepared: visual.primary,
            entrance: CGSize(width: currentOnLeading ? -42 : 42, height: 0),
            primary: primary,
            accent: currentOnLeading ? accent : warm,
            in: context,
            size: CGSize(width: size.width, height: size.height * 0.82),
            time: time)

        guard let companionLayout = visual.auxiliary.last else { return }
        let companion = companionLayout.line
        let residue = max(0, 1 - progress(time, start: max(companion.to, line.from), duration: 1.8))
        for item in companionLayout.positioned {
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: companionLayout.fontSize,
                color: secondary,
                opacity: 0.10 + 0.36 * residue,
                offset: CGSize(width: currentOnLeading ? 12 : -12, height: 0),
                in: context)
        }
    }

    private func drawStack(
        visual: PreparedSceneVisual,
        primary: Color,
        secondary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let scene = visual.scene
        let line = visual.line
        let currentPosition = visual.auxiliary.firstIndex { $0.lineIndex == scene.lineIndex } ?? 0
        for (position, prepared) in visual.auxiliary.enumerated() {
            let isCurrent = prepared.lineIndex == scene.lineIndex
            for item in prepared.positioned {
                let opacity = isCurrent ? 0.15 + 0.85 * reveal(item.glyph, time: time) : 0.14
                drawGlyph(
                    item.glyph.text,
                    at: item.point,
                    fontSize: prepared.fontSize,
                    color: isCurrent ? (position == currentPosition ? accent : primary) : secondary,
                    opacity: opacity,
                    offset: CGSize(width: isCurrent ? -30 * (1 - CGFloat(smooth(progress(time, start: line.from, duration: 0.55)))) : 0, height: 0),
                    in: context)
            }
        }
    }

    private func drawArc(
        visual: PreparedSceneVisual,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let count = max(1, visual.arcGlyphs.count)
        for prepared in visual.arcGlyphs {
            let reveal = reveal(prepared.glyph, time: time)
            drawGlyph(
                prepared.glyph.text,
                at: prepared.point,
                fontSize: prepared.fontSize,
                color: prepared.index == count / 2 ? accent : primary,
                opacity: 0.10 + 0.90 * reveal,
                offset: CGSize(width: 0, height: 34 * (1 - CGFloat(reveal))),
                scale: 0.76 + 0.24 * reveal,
                rotation: prepared.rotation,
                in: context)
        }
    }

    private func drawHero(
        visual: PreparedSceneVisual,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let line = visual.line
        let fontSize = visual.primary.fontSize
        let layout = visual.primary.positioned
        let arrival = backOut(progress(time, start: line.from, duration: 0.62))
        for item in layout {
            let reveal = reveal(item.glyph, time: time)
            let side: CGFloat = item.index.isMultiple(of: 2) ? -1 : 1
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: fontSize,
                color: item.index == layout.count - 1 ? accent : primary,
                opacity: reveal,
                offset: CGSize(width: side * 94 * (1 - CGFloat(arrival)), height: CGFloat(item.index % 3 - 1) * 24 * (1 - CGFloat(arrival))),
                scale: 1.28 - 0.28 * arrival,
                rotation: Double(side) * 12 * (1 - arrival),
                in: context)
        }
    }

    private func drawHook(
        visual: PreparedSceneVisual,
        primary: Color,
        accent: Color,
        warm: Color,
        in context: GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let scene = visual.scene
        let line = visual.line
        let fontSize = visual.primary.fontSize
        let layout = visual.primary.positioned
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
        motifPhase: LyricStageMotifPhaseV3,
        audioAccent: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard scene.isSectionStart else { return }
        let duration: Double = motifPhase == .transform ? 0.56 : 0.72
        let phase = 1 - smooth(progress(time, start: line.from, duration: duration))
        guard phase > 0.001 else { return }
        let width = (size.width - 24) * CGFloat(phase)
        var cut = Path()
        cut.move(to: CGPoint(x: size.width - 12 - width, y: size.height * 0.18))
        cut.addLine(to: CGPoint(x: size.width - 12, y: size.height * 0.18))
        let phaseWeight: Double = switch motifPhase {
        case .introduce: 0.30
        case .develop: 0.38
        case .transform: 0.54
        case .resolve: 0.34
        }
        context.stroke(
            cut,
            with: .color(accent.opacity(
                (phaseWeight + scene.intensity.clamped(to: 0...1) * 0.10 + audioAccent * 0.12) * phase)),
            lineWidth: (motifPhase == .transform ? 1.8 : 1.2) + 0.3 * scene.intensity.clamped(to: 0...1))
    }

    /// Audio may brighten a section-edge decoration after lyric reveal. It never
    /// moves/scales text or changes lyric timing and scene ownership.
    private func audioAccentPulse(
        audioTime: Double,
        lyricTime: Double,
        line: PlayerEngine.LyricLine,
        scene: LyricStageV53Scene,
        motifPhase: LyricStageMotifPhaseV3
    ) -> Double {
        guard scene.isSectionStart,
              let audioMap,
              lyricTime >= line.from,
              lyricTime <= line.to + 0.35 else { return 0 }
        var onsetPulse = 0.0
        if let onset = audioMap.nearestOnset(to: audioTime, tolerance: 0.14) {
            let elapsed = audioTime - onset.time
            if onset.strength >= 0.72, elapsed >= 0, elapsed <= 0.14 {
                onsetPulse = (1 - elapsed / 0.14) * onset.strength
            }
        }
        let energy = audioMap.envelope(.energy, at: audioTime) ?? 0
        let downbeatPulse = energy >= 0.62
            ? trailingPulse(audioMap.downbeats, at: audioTime, window: 0.12)
            : 0
        let phaseWeight: Double = switch motifPhase {
        case .introduce: 0.72
        case .develop: 0.88
        case .transform: 1.0
        case .resolve: 0.64
        }
        return min(
            1,
            max(onsetPulse, downbeatPulse * 0.72)
                * (0.55 + energy * 0.45)
                * phaseWeight
                * scene.intensity.clamped(to: 0...1))
    }

    private func trailingPulse(_ events: [Double], at time: Double, window: Double) -> Double {
        guard !events.isEmpty else { return 0 }
        var lower = 0
        var upper = events.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if events[middle] <= time { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return 0 }
        let elapsed = time - events[lower - 1]
        guard elapsed >= 0, elapsed <= window else { return 0 }
        return 1 - elapsed / window
    }

    private func drawInterlude(
        layout: PreparedInterludeLayout,
        subtitle: String,
        progress: Double,
        primary: Color,
        accent: Color,
        in context: GraphicsContext,
        size: CGSize
    ) {
        for item in layout.positioned {
            let stagger = min(1, max(0, progress * 1.35 - Double(item.index) * 0.035))
            drawGlyph(
                item.glyph.text,
                at: item.point,
                fontSize: layout.fontSize,
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

    private func fittedFontSize(
        glyphCount: Int,
        proposed: CGFloat,
        in size: CGSize
    ) -> CGFloat {
        guard glyphCount > 0 else { return proposed }
        var candidate = proposed
        while candidate > 14 {
            let averageGlyphWidth = max(6, candidate * 0.62)
            let perRow = max(1, Int((size.width - 30) / averageGlyphWidth))
            let rows = Int(ceil(Double(glyphCount) / Double(perRow)))
            if CGFloat(rows) * candidate * 1.12 <= size.height * 0.84 {
                return candidate
            }
            candidate -= 2
        }
        return 14
    }

    private func makeGlyphLayout(
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
                        y: firstY + CGFloat(rowIndex) * rowHeight),
                    size: CGSize(width: item.2, height: rowHeight)))
                cursor += item.2 + spacing
            }
        }
        return result
    }

    private func positionedBounds(_ glyphs: [PositionedGlyph]) -> CGRect {
        glyphs.reduce(into: CGRect.null) { bounds, item in
            bounds = bounds.union(CGRect(
                x: item.point.x - item.size.width / 2,
                y: item.point.y - item.size.height / 2,
                width: item.size.width,
                height: item.size.height))
        }
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
        weight: Font.Weight = .black,
        in context: GraphicsContext
    ) {
        var local = context
        local.opacity = min(max(opacity, 0), 1)
        local.translateBy(x: point.x + offset.width, y: point.y + offset.height)
        local.rotate(by: .degrees(rotation))
        local.scaleBy(x: scale, y: scale)
        local.draw(
            Text(text)
                .font(.system(size: fontSize, weight: weight))
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

struct LyricStageV3SummarySheet: View {
    let summary: LyricStagePlanV3Summary

    var body: some View {
        NavigationStack {
            List {
                Section("导演") {
                    Text(summary.concept)
                    LabeledContent("母题", value: summary.motif)
                    LabeledContent("强弱弧线", value: summary.intensityArc)
                    LabeledContent("来源", value: summary.source == .luna ? "Luna V3 + 本地补齐" : "本地完整规划")
                    if summary.partial {
                        Label("线上分段仅部分成功，其余使用本地规划", systemImage: "exclamationmark.triangle")
                    }
                }
                if !summary.sections.isEmpty {
                    Section("段落") {
                        ForEach(summary.sections, id: \.self, content: Text.init)
                    }
                }
                if !summary.compositions.isEmpty {
                    Section("构图预算") {
                        ForEach(summary.compositions, id: \.self, content: Text.init)
                    }
                }
            }
            .navigationTitle("V5.3 演出摘要")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("lyricStageV3SummarySheet")
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
