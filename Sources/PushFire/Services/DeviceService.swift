import Foundation

/// A duration in milliseconds for the APNs poll loop.
///
/// This predates the package's iOS 16 floor: it was originally a stand-in for
/// `Duration` (Swift's standard type, iOS 16+) before the floor was raised. It is kept
/// as-is because it works and there's no value in churning it: a minimal type exposing
/// only the `.milliseconds(_:)` factory the poll loop needs, so call sites read the
/// same as they would with `Duration`.
struct PollInterval: Sendable, Equatable {
    let nanoseconds: UInt64

    static func milliseconds(_ value: Int) -> PollInterval {
        PollInterval(nanoseconds: UInt64(value) * 1_000_000)
    }
}

/// The result of a manual `requestNotificationPermission()` call: whether the OS
/// permission was granted, and the device registration it produced, if any.
struct NotificationPermissionRequest: Sendable {
    let granted: Bool
    let device: Device?
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
    /// How the poll loop waits between checks. Injectable only so a test can count the
    /// gaps: the number of sleeps is what makes the window 5.0s rather than 5.5s, and it
    /// is not observable from the number of token checks.
    private let sleeper: @Sendable (PollInterval) async -> Void

    /// How long a late APNs token has to arrive, matched to the Flutter SDK.
    ///
    /// Flutter checks once, then retries up to 10 times with a 500ms delay before each
    /// retry — 11 checks, and 10 gaps totalling 5.0 seconds. Counting only the retries
    /// here would give a device on a slow network half a second less grace on iOS than
    /// the same device gets through the Flutter SDK.
    static let defaultAPNSPollInterval = PollInterval.milliseconds(500)
    static let defaultAPNSPollAttempts = 11
    /// The in-flight registration. Concurrent callers await this one rather than
    /// starting a second registration — the Swift equivalent of
    /// `PushFireCore.permissionCheck`, applied to `registerDevice()`. Without this,
    /// two concurrent calls can both observe no stored device id and both POST
    /// register-device, creating two device rows with one permanently orphaned.
    private var registrationTask: Task<Device?, any Error>?

    init(
        apiClient: APIClient,
        config: PushFireConfiguration,
        store: any KeyValueStore,
        deviceInfo: any DeviceInfoProvider,
        permissions: any NotificationPermissionProvider,
        tokens: any PushTokenProvider,
        logger: PushFireLogger,
        apnsPollInterval: PollInterval = DeviceService.defaultAPNSPollInterval,
        apnsPollAttempts: Int = DeviceService.defaultAPNSPollAttempts,
        sleeper: @escaping @Sendable (PollInterval) async -> Void = {
            try? await Task.sleep(nanoseconds: $0.nanoseconds)
        }
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
        self.sleeper = sleeper
    }

    /// Registers the device, or updates it if something changed.
    ///
    /// Returns nil when no push token is available yet. This is not an error: on iOS the
    /// APNs token arrives asynchronously, and the token-refresh stream re-drives
    /// registration once it lands.
    @discardableResult
    func registerDevice() async throws -> Device? {
        if let existing = registrationTask {
            return try await existing.value
        }

        let task = Task { try await self.performRegistration() }
        registrationTask = task
        defer { registrationTask = nil }
        return try await task.value
    }

    private func performRegistration() async throws -> Device? {
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

    // MARK: - Permission sync

    /// Re-checks the OS permission and syncs any change to PushFire.
    ///
    /// Returns the re-registered device when the server was updated, nil otherwise.
    /// Never throws: this runs on app foreground where there is no caller to handle a
    /// failure, and a failed sync must simply be retried on the next resume.
    func checkAndHandlePermissionStatusChange() async -> Device? {
        let current = await permissions.authorizationStatus().isEnabled

        guard let last = store.bool(forKey: StorageKey.lastPermissionStatus) else {
            store.setBool(current, forKey: StorageKey.lastPermissionStatus)
            return nil
        }

        guard last != current else { return nil }

        // Deliberately do NOT persist the new status here. registerDevice() compares the
        // incoming value against the saved last-known status to decide whether to PATCH;
        // writing it up front makes registerDevice() see "no change" and silently skip
        // the update, and also suppresses retries, because a failed sync would still have
        // advanced the saved status.

        if !current {
            logger.info("OS notification permission revoked - updating server to disabled")
            return try? await registerDevice()
        }

        let preference = store.bool(forKey: StorageKey.notificationPreference) ?? true
        if preference {
            logger.info("OS notification permission re-granted - restoring")
            return try? await registerDevice()
        }

        // The developer opted out, so leave the server alone — but acknowledge the OS
        // change so it is not re-detected on every resume.
        store.setBool(current, forKey: StorageKey.lastPermissionStatus)
        logger.info("OS permission re-granted but preference is disabled - not restoring")
        return nil
    }

    // MARK: - Preference

    /// Sets whether this device should receive PushFire notifications.
    ///
    /// This is a PushFire-level preference, distinct from the OS permission.
    func setNotificationEnabled(_ enabled: Bool) async throws -> SetNotificationResult {
        logger.info("Setting notification enabled: \(enabled)")

        if enabled {
            let osPermission = await permissions.authorizationStatus().isEnabled
            guard osPermission else {
                logger.warning("Cannot enable notifications - OS permission is denied")
                return .systemPermissionDenied
            }
        }

        if store.bool(forKey: StorageKey.notificationPreference) == enabled {
            logger.info("Notification preference already \(enabled) - nothing to do")
            return .success
        }

        guard let deviceId = store.string(forKey: StorageKey.deviceId) else {
            throw PushFireError.device(
                "Cannot set notification preference - no device registered"
            )
        }
        guard let fcmToken = store.string(forKey: StorageKey.fcmToken) else {
            throw PushFireError.device(
                "Cannot set notification preference - no push token available"
            )
        }

        let info = await deviceInfo.deviceInfo()
        let device = Device(
            id: deviceId,
            fcmToken: fcmToken,
            os: info.os,
            osVersion: info.osVersion,
            language: info.language,
            manufacturer: info.manufacturer,
            model: info.model,
            appVersion: info.appVersion,
            pushNotificationEnabled: enabled
        )

        try await update(device)

        // Persist only after the server confirms, so a failed PATCH cannot leave local
        // and remote disagreeing.
        store.setBool(enabled, forKey: StorageKey.notificationPreference)

        logger.info("Notification preference updated to \(enabled)")
        return .success
    }

    /// The OS permission state and the PushFire preference.
    /// Does not require a registered device.
    func notificationStatus() async -> NotificationStatus {
        NotificationStatus(
            isPermissionGranted: await permissions.authorizationStatus().isEnabled,
            isEnabled: store.bool(forKey: StorageKey.notificationPreference) ?? true
        )
    }

    /// Prompts for the notification permission, re-registering the device if granted.
    ///
    /// Returns the re-registered device alongside the granted flag so the caller can
    /// update its own state from this single registration, rather than re-registering
    /// a second time itself (which would re-run the APNs poll and FCM token fetch).
    @discardableResult
    func requestNotificationPermission() async throws -> NotificationPermissionRequest {
        logger.info("Manually requesting notification permission")
        let status = await permissions.requestAuthorization(provisional: false)
        let granted = status.isEnabled

        var device: Device?
        if granted {
            logger.info("Permission granted - re-registering device")
            device = try await registerDevice()
        }

        return NotificationPermissionRequest(granted: granted, device: device)
    }

    /// Opens this app's page in Settings so the user can grant the permission manually.
    func openNotificationSettings() async -> Bool {
        await permissions.openSettings()
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

    @discardableResult
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
            // No sleep after the last check: N checks must span N-1 gaps, or the window
            // silently grows past the 5.0s the Flutter SDK allows. The check count alone
            // does not reveal that, which is why `sleeper` is injectable.
            if attempt < apnsPollAttempts - 1 {
                await sleeper(apnsPollInterval)
            }
        }
        return nil
    }
}
