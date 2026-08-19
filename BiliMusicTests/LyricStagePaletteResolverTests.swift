import XCTest
@testable import BiliMusic

final class LyricStagePaletteResolverTests: XCTestCase {
    func testStrategiesStayCoverDerivedAndDistinct() {
        let analogous = LyricStagePaletteResolver.resolve(strategy: .coverAnalogous)
        let complementary = LyricStagePaletteResolver.resolve(strategy: .coverComplementary)
        let warm = LyricStagePaletteResolver.resolve(strategy: .warmClimax)
        let cool = LyricStagePaletteResolver.resolve(strategy: .coolClimax)
        XCTAssertNotEqual(analogous.accent, complementary.accent)
        XCTAssertNotEqual(warm.warm, cool.accent)
        XCTAssertEqual(
            LyricStagePaletteResolver.resolve(strategy: .coverMonochrome),
            LyricStagePaletteResolver.resolve(strategy: .coverMonochrome))
    }
}
