import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isWiFi = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "BiliMusic.NetworkMonitor")

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
