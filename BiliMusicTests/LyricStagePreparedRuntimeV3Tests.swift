import XCTest
@testable import BiliMusic

final class LyricStagePreparedRuntimeV3Tests: XCTestCase {
    func testPreparedRuntimeMatchesPlanSelectionAcrossBoundariesOverlapsAndGaps() {
        let lines = [
            PlayerEngine.LyricLine(from: 1.0, to: 3.0, text: "backing", voiceRole: .backing),
            PlayerEngine.LyricLine(from: 1.5, to: 2.5, text: "lead", voiceRole: .lead),
            PlayerEngine.LyricLine(from: 4.0, to: 5.0, text: "after gap"),
            PlayerEngine.LyricLine(from: 5.0, to: 7.0, text: "together", voiceRole: .together),
        ]
        let plan = LyricStageDirectorV3.localPlan(
            trackID: "runtime-overlap-fixture",
            lines: lines,
            audioSummary: .empty(duration: 8))
        let runtime = LyricStagePreparedRuntimeV3(plan: plan, lines: lines)
        let probes = [0, 1, 1.25, 1.5, 2.499, 2.5, 2.999, 3, 3.9, 4, 4.999, 5, 6.9, 7, 8]

        for time in probes {
            XCTAssertEqual(
                runtime.sample(at: time)?.scene,
                plan.scene(at: time, lines: lines),
                "selection changed at \(time)")
        }
    }

    func testPreparedRuntimeSamplesTenThousandFramesFromBoundedChangeIndex() {
        let lines = (0..<240).map { index in
            PlayerEngine.LyricLine(
                from: Double(index) * 1.25,
                to: Double(index) * 1.25 + 1.05,
                text: "runtime line \(index)")
        }
        let plan = LyricStageDirectorV3.localPlan(
            trackID: "runtime-scale-fixture",
            lines: lines,
            audioSummary: .empty(duration: 302))
        let runtime = LyricStagePreparedRuntimeV3(plan: plan, lines: lines)

        XCTAssertLessThanOrEqual(runtime.changeCount, lines.count * 2)
        var checksum = 0
        for frame in 0..<10_000 {
            checksum &+= runtime.sample(at: Double(frame) * 0.031)?.scene.lineIndex ?? -1
        }
        XCTAssertGreaterThan(checksum, 0)
        XCTAssertEqual(runtime.sample(at: 150)?.scene, plan.scene(at: 150, lines: lines))
    }
}
