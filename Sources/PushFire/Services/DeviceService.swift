import Foundation

/// A duration in milliseconds for the APNs poll loop.
///
/// `Duration` (Swift's standard type) requires iOS 16, but this package's floor is
/// iOS 15 to match FirebaseMessaging's own requirement (see Package.swift). This is a
/// minimal stand-in exposing only the `.milliseconds(_:)` factory the poll loop needs,
/// so call sites read the same as they would with `Duration`.
struct PollInterval: Sendable {
    fileprivate let nanoseconds: UInt64

    static func milliseconds(_ value: Int) -> PollInterval {
        PollInterval(nanoseconds: UInt64(value) * 1_000_000)
    }
}

/// Registers this device with PushFire and keeps its notification state in sync.
actor DeviceService {
    private let apiClient: APIClient
    private let config: PushFireConfiguration
    private let store: any KeyValueStore
    private let deviceInfo: any DeviceInfoProvider
    private let permissions: any NotificationPermissionProvider
    private let tokens: any PushTokenProvider
    private let logger: PushFireLogger
    private let apnsPollInterval: PollInterval
    private let apnsPollAttempts: Int

    init(
        apiClient: APIClient,
        config: PushFireConfiguration,
        store: any KeyValueStore,
        deviceInfo: any DeviceInfoProvider,
        permissions: any NotificationPermissionProvider,
        tokens: any PushTokenProvider,
        logger: PushFireLogger,
        apnsPollInterval: PollInterval = .milliseconds(500),
        apnsPollAttempts: Int = 10
    ) {
        self.apiClient = apiClient
        self.config = config
        self.store = store
        self.deviceInfo = deviceInfo
        self.permissions = permissions
        self.tokens = tokens
        self.logger = logger
        self.apnsPollInterval = apnsPollInterval
        self.apnsPollAttempts = apnsPollAttempts
    }

    /// Registers the device, or updates it if something changed.
    ///
    /// Returns nil when no push token is available yet. This is not an error: on iOS the
    /// APNs token arrives asynchronously, and the token-refresh stream re-drives
    /// registration once it lands.
    @discardableResult
    func registerDevice() async throws -> Device? {
        logger.info("Starting device registration")

        guard let fcmToken = await resolveToken() else {
            logger.warning(
                "No push token available - skipping registration. "
                    + "The device will register once the token arrives."
            )
            return nil
        }

        let info = await deviceInfo.deviceInfo()
        let osPermission = await permissions.authorizationStatus().isEnabled
        let savedPreference = store.bool(forKey: StorageKey.notificationPreference)
        let effectiveEnabled = osPermission && (savedPreference ?? true)

        let device = Device(
            fcmToken: fcmToken,
            os: info.os,
            osVersion: info.osVersion,
            language: info.language,
            manufacturer: info.manufacturer,
            model: info.model,
            appVersion: info.appVersion,
            pushNotificationEnabled: effectiveEnabled
        )

        let existingId = store.string(forKey: StorageKey.deviceId)
        let lastToken = store.string(forKey: StorageKey.fcmToken)
        let lastPermission = store.bool(forKey: StorageKey.lastPermissionStatus)

        let registered: Device
        if let existingId {
            if lastToken == fcmToken {
                // Compare raw OS permission against raw OS permission. The Dart compares
                // the saved raw value against the *effective* value, so a device whose
                // developer turned notifications off PATCHes on every launch forever.
                if let lastPermission, lastPermission != osPermission {
                    logger.info("Permission status changed - updating device \(existingId)")
                    registered = try await update(device.with(id: existingId))
                } else {
                    logger.info("Device already registered with id \(existingId)")
                    registered = device.with(id: existingId)
                }
            } else {
                logger.info("Push token changed - updating device \(existingId)")
                registered = try await update(device.with(id: existingId))
            }
        } else {
            logger.info("Registering new device")
            registered = try await create(device)
            store.setBool(true, forKey: StorageKey.notificationPreference)
        }

        guard let id = registered.id else {
            throw PushFireError.device("Device registration returned no device id")
        }

        store.setString(id, forKey: StorageKey.deviceId)
        store.setString(fcmToken, forKey: StorageKey.fcmToken)
        // The raw OS permission, not the effective value.
        store.setBool(osPermission, forKey: StorageKey.lastPermissionStatus)

        logger.info("Device registration completed: \(id)")
        return registered
    }

    /// The stored device id, if this device has been registered.
    func deviceId() -> String? {
        store.string(forKey: StorageKey.deviceId)
    }

    /// Clears all device state from local storage.
    func clearDeviceData() {
        store.remove(forKey: StorageKey.deviceId)
        store.remove(forKey: StorageKey.fcmToken)
        store.remove(forKey: StorageKey.lastPermissionStatus)
        store.remove(forKey: StorageKey.notificationPreference)
        logger.info("Device data cleared")
    }

    // MARK: - Server calls

    private func create(_ device: Device) async throws -> Device {
        let response: IdentifierResponse = try await apiClient.send(
            .registerDevice,
            body: device
        )
        guard let id = response.resolvedDeviceId else {
            throw PushFireError.device(
                "Device registration succeeded but no device id was returned"
            )
        }
        return device.with(id: id)
    }

    private func update(_ device: Device) async throws -> Device {
        try await apiClient.send(.updateDevice, body: device)
        return device
    }

    // MARK: - Token acquisition

    private func resolveToken() async -> String? {
        if config.requestNotificationPermission {
            let status = await permissions.authorizationStatus()
            if status == .notDetermined {
                logger.info("Requesting notification permission")
                _ = await permissions.requestAuthorization(provisional: false)
            } else {
                logger.info(
                    "Notification permission already resolved: \(String(describing: status))")
                await permissions.registerForRemoteNotifications()
            }
        } else if config.registerWithoutPrompt {
            let status = await permissions.authorizationStatus()
            if status == .notDetermined {
                // Provisional authorization makes the OS register for remote
                // notifications — so an APNs token becomes available — without showing
                // the interruptive dialog. Only acts while the user has made no explicit
                // choice, so it never overrides an existing decision.
                logger.info("Requesting provisional authorization to trigger APNs registration")
                _ = await permissions.requestAuthorization(provisional: true)
            } else {
                await permissions.registerForRemoteNotifications()
            }
        }

        guard await waitForAPNSToken() != nil else {
            logger.warning("APNs token not available yet - skipping FCM token fetch")
            return nil
        }

        return await tokens.fcmToken()
    }

    /// Apple delivers the APNs token asynchronously after registration. Asking
    /// FirebaseMessaging for an FCM token before it lands fails, so poll first and give
    /// up quietly if it never arrives (simulator, offline, or registration never fired).
    private func waitForAPNSToken() async -> String? {
        for attempt in 0..<apnsPollAttempts {
            if let token = await tokens.apnsToken() {
                return token
            }
            if attempt < apnsPollAttempts - 1 {
                try? await Task.sleep(nanoseconds: apnsPollInterval.nanoseconds)
            }
        }
        return nil
    }
}
