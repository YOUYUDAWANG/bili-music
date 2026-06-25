import Foundation

enum UITestFixtures {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["BILIMUSIC_UITEST_FIXTURE"] == "1"
    }

    static let homeTracks: [Track] = [
        Track(typeID: 3, bvid: "BVUITEST001", cid: 1001, title: "Fixture Song One", artist: "UI Test", coverURL: nil, duration: 211),
        Track(typeID: 3, bvid: "BVUITEST002", cid: 1002, title: "Fixture Song Two", artist: "UI Test", coverURL: nil, duration: 197),
        Track(typeID: 193, bvid: "BVUITEST003", cid: 1003, title: "Fixture MV Three", artist: "UI Test", coverURL: nil, duration: 243),
        Track(typeID: 3, bvid: "BVUITEST004", cid: 1004, title: "Fixture Song Four", artist: "UI Test", coverURL: nil, duration: 188),
        Track(typeID: 3, bvid: "BVUITEST005", cid: 1005, title: "Fixture Song Five", artist: "UI Test", coverURL: nil, duration: 224),
        Track(typeID: 3, bvid: "BVUITEST006", cid: 1006, title: "Fixture Song Six", artist: "UI Test", coverURL: nil, duration: 205),
        Track(typeID: 3, bvid: "BVUITEST007", cid: 1007, title: "Fixture Song Seven", artist: "UI Test", coverURL: nil, duration: 199),
        Track(typeID: 3, bvid: "BVUITEST008", cid: 1008, title: "Fixture Song Eight", artist: "UI Test", coverURL: nil, duration: 231),
        Track(typeID: 3, bvid: "BVUITEST009", cid: 1009, title: "Fixture Song Nine", artist: "UI Test", coverURL: nil, duration: 214),
        Track(typeID: 3, bvid: "BVUITEST010", cid: 1010, title: "Fixture Song Ten", artist: "UI Test", coverURL: nil, duration: 202)
    ]
}
