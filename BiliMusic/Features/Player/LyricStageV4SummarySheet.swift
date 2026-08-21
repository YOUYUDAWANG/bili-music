import SwiftUI

struct LyricStageV4SummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: LyricStagePlanV4

    var body: some View {
        NavigationStack {
            List {
                Section("演出概念") {
                    LabeledContent("概念", value: plan.stageBible.concept)
                    LabeledContent("强度弧线", value: plan.stageBible.intensityArc)
                    LabeledContent("主母题", value: motifDescription(plan.stageBible.primaryMotif))
                    if let secondary = plan.stageBible.secondaryMotif {
                        LabeledContent("副母题", value: motifDescription(secondary))
                    }
                }

                Section("音频结构") {
                    LabeledContent("状态", value: plan.audioScore.availability.rawValue)
                    LabeledContent("结构地标", value: "\(plan.audioScore.moments.count)")
                    LabeledContent("结构段落", value: "\(plan.audioScore.sections.count)")
                    LabeledContent("逐行事实", value: "\(plan.audioScore.lineFacts.count)")
                }

                Section("Scene Recipe") {
                    LabeledContent("在线导演句", value: "\(plan.recipes.count)")
                    ForEach(LyricStageSceneFamilyV4.allCases, id: \.self) { family in
                        let count = plan.recipes.count { $0.family == family }
                        if count > 0 {
                            LabeledContent(familyTitle(family), value: "\(count)")
                        }
                    }
                }

                Section("执行边界") {
                    LabeledContent("来源", value: plan.source == .gemini ? "Gemini + 本地编译器" : "本地回退")
                    LabeledContent("歌词时轴", value: "保持原始逐行／逐字时间")
                    LabeledContent("基础舞台", value: "完整 V5.3 本地计划")
                }
            }
            .navigationTitle("V4 音频演出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func motifDescription(_ motif: LyricStageMotifV4) -> String {
        "\(motif.signature.rawValue) · \(motif.axis.rawValue) · \(motif.cadence.rawValue)"
    }

    private func familyTitle(_ family: LyricStageSceneFamilyV4) -> String {
        switch family {
        case .railHandoff: "文字接力"
        case .semanticLens: "语义镜头"
        case .chorusMemory: "副歌记忆"
        case .silenceAperture: "静默开门"
        }
    }
}
