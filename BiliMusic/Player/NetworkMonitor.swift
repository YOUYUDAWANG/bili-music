import Foundation
import Network
import Observation

/// 监测网络可达性与是否处于 Wi-Fi，供「Wi-Fi 优先 MV」等策略判断。
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isWiFi = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "BiliMusic.NetworkMonitor")

    /// 启动路径监测，回到主线程更新 `isWiFi`。
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            let usesWiFi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self?.isWiFi = isSatisfied && usesWiFi
            }
        }
        monitor.start(queue: queue)
    }
}
