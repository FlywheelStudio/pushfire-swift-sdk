import Foundation

/// Device attributes sent with every registration.
struct DeviceInfo: Sendable, Equatable {
    let os: String
    let osVersion: String
    let language: String
    let manufacturer: String
    let model: String
    let appVersion: String
}

/// Supplies device attributes.
protocol DeviceInfoProvider: Sendable {
    func deviceInfo() async -> DeviceInfo
}
