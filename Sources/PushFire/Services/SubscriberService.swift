import Foundation

/// Manages the subscriber session bound to this device.
actor SubscriberService {
    private let apiClient: APIClient
    private let deviceService: DeviceService
    private let store: any KeyValueStore
    private let logger: PushFireLogger

    init(
        apiClient: APIClient,
        deviceService: DeviceService,
        store: any KeyValueStore,
        logger: PushFireLogger
    ) {
        self.apiClient = apiClient
        self.deviceService = deviceService
        self.store = store
        self.logger = logger
    }

    // MARK: - Wire bodies

    private struct LoginBody: Encodable {
        let deviceId: String
        let externalId: String
        let name: String?
        let email: String?
        let phone: String?
        let metadata: [String: JSONValue]?
    }

    private struct UpdateBody: Encodable {
        let id: String
        let externalId: String
        let name: String?
        let email: String?
        let phone: String?
        let metadata: [String: JSONValue]?
    }

    private struct LogoutBody: Encodable {
        let deviceId: String
        let subscriberId: String
    }

    // MARK: - Session

    /// Logs a subscriber in, creating them if they do not exist.
    func login(
        externalId: String,
        name: String?,
        email: String?,
        phone: String?,
        metadata: [String: JSONValue]?
    ) async throws -> Subscriber {
        logger.info("Starting subscriber login: \(externalId)")

        guard let deviceId = await deviceService.deviceId() else {
            throw PushFireError.subscriber(
                "Device is not registered yet, so the subscriber cannot be logged in"
            )
        }

        let response: IdentifierResponse = try await apiClient.send(
            .loginSubscriber,
            body: LoginBody(
                deviceId: deviceId,
                externalId: externalId,
                name: name,
                email: email,
                phone: phone,
                metadata: metadata
            )
        )

        guard let subscriberId = response.resolvedSubscriberId else {
            throw PushFireError.subscriber(
                "Subscriber login succeeded but no subscriber id was returned"
            )
        }

        let subscriber = Subscriber(
            id: subscriberId,
            deviceId: deviceId,
            externalId: externalId,
            name: name,
            email: email,
            phone: phone,
            metadata: metadata
        )

        persist(subscriber)
        logger.info("Subscriber login completed: \(subscriberId)")
        return subscriber
    }

    /// Updates the logged-in subscriber.
    ///
    /// `externalId` is never changed — the backend rejects it — so the stored value is
    /// always resent as-is.
    func updateSubscriber(
        name: String?,
        email: String?,
        phone: String?,
        metadata: [String: JSONValue]?
    ) async throws -> Subscriber {
        guard let current = currentSubscriber(), let id = current.id else {
            throw PushFireError.subscriber("No subscriber is logged in")
        }

        logger.info("Updating subscriber: \(id)")

        try await apiClient.send(
            .updateSubscriber,
            body: UpdateBody(
                id: id,
                externalId: current.externalId,
                name: name,
                email: email,
                phone: phone,
                metadata: metadata
            )
        )

        let updated = current.with(name: name, email: email, phone: phone, metadata: metadata)
        persist(updated)
        logger.info("Subscriber updated")
        return updated
    }

    /// Logs the current subscriber out.
    ///
    /// Local state is cleared whether or not the server call succeeds — a failed logout
    /// must not leave the device believing it still has a session. The error still
    /// propagates.
    func logout() async throws {
        logger.info("Starting subscriber logout")

        let subscriber = currentSubscriber()
        let deviceId = await deviceService.deviceId()

        guard let subscriberId = subscriber?.id, let deviceId else {
            logger.warning("No subscriber or device found for logout")
            clear()
            return
        }

        do {
            try await apiClient.send(
                .logoutSubscriber,
                body: LogoutBody(deviceId: deviceId, subscriberId: subscriberId)
            )
        } catch {
            clear()
            throw error
        }

        clear()
        logger.info("Subscriber logout completed")
    }

    // MARK: - Local state

    /// The stored subscriber, if one is logged in.
    func currentSubscriber() -> Subscriber? {
        guard let json = store.string(forKey: StorageKey.subscriberData),
            let data = json.data(using: .utf8)
        else { return nil }

        do {
            return try JSONDecoder().decode(Subscriber.self, from: data)
        } catch {
            logger.warning("Could not decode the stored subscriber", error)
            return nil
        }
    }

    func isLoggedIn() -> Bool {
        currentSubscriber()?.id != nil
    }

    func subscriberId() -> String? {
        store.string(forKey: StorageKey.subscriberId)
    }

    /// Clears local subscriber state without calling the server.
    ///
    /// Unlike `logout()`, this does not require a logged-in subscriber (a non-nil
    /// `id`) — it exists so `PushFireCore.reset()` can unconditionally wipe local
    /// state, including a stored subscriber whose `id` is nil.
    func clearLocalData() {
        clear()
    }

    /// Persists a subscriber locally.
    ///
    /// Named `persist` rather than `store` so it does not collide with the `store`
    /// property.
    func persist(_ subscriber: Subscriber) {
        // Encode before writing anything. Writing the id first and then failing to
        // encode would leave subscriberId() reporting a logged-in user that
        // currentSubscriber() and isLoggedIn() cannot see, and nothing later
        // reconciles that split.
        guard let data = try? JSONEncoder().encode(subscriber),
            let json = String(data: data, encoding: .utf8)
        else {
            logger.warning("Could not encode the subscriber; local state left unchanged")
            return
        }

        if let id = subscriber.id {
            store.setString(id, forKey: StorageKey.subscriberId)
        }
        store.setString(json, forKey: StorageKey.subscriberData)
    }

    private func clear() {
        store.remove(forKey: StorageKey.subscriberId)
        store.remove(forKey: StorageKey.subscriberData)
        logger.info("Subscriber data cleared")
    }
}
