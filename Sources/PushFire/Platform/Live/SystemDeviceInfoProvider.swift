import Foundation
import UIKit

/// Field values match the Flutter SDK so console data stays consistent across SDKs.
///
/// `model` is deliberately the generic `UIDevice` name (`"iPhone"`), not the hardware
/// identifier (`"iPhone16,2"`) — `device_info_plus` reports the generic name and devices
/// registered by both SDKs must look alike.
struct SystemDeviceInfoProvider: DeviceInfoProvider {
    func deviceInfo() async -> DeviceInfo {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return await MainActor.run {
            let device = UIDevice.current
            return DeviceInfo(
                os: "ios",
                osVersion: device.systemVersion,
                language: Locale.current.identifier,
                manufacturer: "Apple",
                model: device.model,
                appVersion: version ?? "unknown"
            )
        }
    }
}
