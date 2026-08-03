import Foundation
import Testing

@testable import PushFire

/// Nested inside `PushFireFacadeTests` so the parent suite's `.serialized` trait covers
/// both: `PushFire` is one process-wide singleton, and two sibling suites configuring and
/// shutting it down in parallel would tear each other's instance out from under them.
extension PushFireFacadeTests {
    /// End-to-end coverage of the public `PushFire` surface.
    ///
    /// Every test drives the real facade, through the real core and services, down to a
    /// `FakeTransport`, and asserts on the HTTP method, the endpoint, the exact request body,
    /// the returned value and the emitted event. A swapped argument or a passthrough wired to
    /// the wrong service fails here rather than shipping.
    ///
    /// `.serialized` because `PushFire` is a process-wide singleton: every test shuts it down
    /// first and installs its own core.
    @Suite(.serialized)
    struct PushFireFacadeDelegationTests {

        // MARK: - Fixtures

        private static let workflowUUID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
        private static let targetUUID = "550e8400-e29b-41d4-a716-446655440000"
        private static let otherTargetUUID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

        /// A store that already looks like a registered device holding the fake token
        /// provider's FCM token, so `core.start()` re-uses it and issues no HTTP request.
        /// Tests using this can assert on `recorded[0]` being their own call.
        private func registeredStore(_ extra: [String: Any] = [:]) -> FakeStore {
            var values: [String: Any] = [
                StorageKey.deviceId: "dev_1",
                StorageKey.fcmToken: "fcm-token",
            ]
            for (key, value) in extra {
                values[key] = value
            }
            return FakeStore(values)
        }

        /// Builds a core from fakes, installs it as the singleton, and hands back the facade.
        private func install(
            _ responses: [FakeTransport.Response],
            store: FakeStore = FakeStore(),
            permissions: FakePermissionProvider = FakePermissionProvider(status: .authorized),
            tokens: FakeTokenProvider = FakeTokenProvider(),
            lifecycle: FakeLifecycleObserver = FakeLifecycleObserver()
        ) async throws -> (PushFire, FakeTransport) {
            let transport = FakeTransport(responses: responses)
            await PushFire.configureForTesting(
                core: PushFireCore(
                    config: PushFireConfiguration(
                        apiKey: "k", requestNotificationPermission: false),
                    transport: transport,
                    store: store,
                    deviceInfo: FakeDeviceInfoProvider(),
                    permissions: permissions,
                    tokens: tokens,
                    lifecycle: lifecycle,
                    authProvider: nil,
                    apnsPollInterval: .milliseconds(1),
                    apnsPollAttempts: 2
                )
            )
            return (try PushFire.shared, transport)
        }

        /// Waits for the next event, failing rather than hanging if none arrives.
        private func nextEvent(
            _ stream: AsyncStream<PushFireEvent>,
            timeoutNanoseconds: UInt64 = 2_000_000_000
        ) async -> PushFireEvent? {
            await withTaskGroup(of: PushFireEvent?.self) { group in
                group.addTask {
                    var iterator = stream.makeAsyncIterator()
                    return await iterator.next()
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return nil
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
        }

        // MARK: - Subscribers

        @Test func loginPostsEveryFieldAndEmitsLoggedIn() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok(#"{"id":"sub_1"}"#)],
                store: registeredStore()
            )
            let events = await sdk.events

            let subscriber = try await sdk.login(
                externalId: "u_1",
                name: "Jane",
                email: "jane@example.com",
                phone: "+15551234567",
                metadata: ["tier": .string("gold"), "seats": .int(3)]
            )

            #expect(subscriber.id == "sub_1")
            #expect(subscriber.deviceId == "dev_1")
            #expect(subscriber.externalId == "u_1")
            #expect(subscriber.name == "Jane")
            #expect(subscriber.email == "jane@example.com")
            #expect(subscriber.phone == "+15551234567")

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "POST")
            #expect(recorded[0].url?.lastPathComponent == "login-subscriber")

            let data = try await transport.requestData(at: 0)
            #expect(data["deviceId"] as? String == "dev_1")
            #expect(data["externalId"] as? String == "u_1")
            #expect(data["name"] as? String == "Jane")
            #expect(data["email"] as? String == "jane@example.com")
            #expect(data["phone"] as? String == "+15551234567")
            let metadata = try #require(data["metadata"] as? [String: Any])
            #expect(metadata["tier"] as? String == "gold")
            #expect(metadata["seats"] as? Int == 3)

            #expect(await nextEvent(events) == .subscriberLoggedIn(subscriber))

            await PushFire.shutdown()
        }

        @Test func updateSubscriberPatchesStoredIdentityAndReturnsMergedSubscriber() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok(#"{"id":"sub_1"}"#), .ok("{}")],
                store: registeredStore()
            )

            try await sdk.login(externalId: "u_1", name: "Jane", email: "jane@example.com")
            let updated = try await sdk.updateSubscriber(
                name: "Jane Doe",
                phone: "+15550000000",
                metadata: ["tier": .string("platinum")]
            )

            // `nil` arguments keep the existing values, and `externalId` is never changed.
            #expect(updated.id == "sub_1")
            #expect(updated.externalId == "u_1")
            #expect(updated.name == "Jane Doe")
            #expect(updated.email == "jane@example.com")
            #expect(updated.phone == "+15550000000")
            #expect(updated.metadata?["tier"] == .string("platinum"))

            let recorded = await transport.recorded
            #expect(recorded.count == 2)
            #expect(recorded[1].httpMethod == "PATCH")
            #expect(recorded[1].url?.lastPathComponent == "update-subscriber")

            let data = try await transport.requestData(at: 1)
            #expect(data["id"] as? String == "sub_1")
            #expect(data["externalId"] as? String == "u_1")
            #expect(data["name"] as? String == "Jane Doe")
            #expect(data["phone"] as? String == "+15550000000")
            // Only what the caller passed travels; the untouched email is not resent.
            #expect(data["email"] == nil)

            await PushFire.shutdown()
        }

        @Test func logoutPostsSessionIdsClearsStateAndEmitsLoggedOut() async throws {
            await PushFire.shutdown()
            let store = registeredStore()
            let (sdk, transport) = try await install(
                [.ok(#"{"id":"sub_1"}"#), .ok("{}")],
                store: store
            )

            try await sdk.login(externalId: "u_1")
            let events = await sdk.events
            try await sdk.logout()

            let recorded = await transport.recorded
            #expect(recorded.count == 2)
            #expect(recorded[1].httpMethod == "POST")
            #expect(recorded[1].url?.lastPathComponent == "logout-subscriber")

            let data = try await transport.requestData(at: 1)
            #expect(data["deviceId"] as? String == "dev_1")
            #expect(data["subscriberId"] as? String == "sub_1")

            #expect(await nextEvent(events) == .subscriberLoggedOut)
            #expect(await sdk.isSubscriberLoggedIn == false)
            #expect(await sdk.currentSubscriber == nil)
            #expect(store.string(forKey: StorageKey.subscriberId) == nil)

            await PushFire.shutdown()
        }

        @Test func subscriberReadersReportTheStoredSession() async throws {
            await PushFire.shutdown()
            let (sdk, _) = try await install(
                [.ok(#"{"id":"sub_1"}"#)],
                store: registeredStore()
            )

            #expect(await sdk.currentSubscriber == nil)
            #expect(await sdk.isSubscriberLoggedIn == false)
            #expect(await sdk.subscriberId() == nil)

            try await sdk.login(
                externalId: "u_1", name: "Jane", metadata: ["tier": .string("gold")])

            let current = try #require(await sdk.currentSubscriber)
            #expect(current.id == "sub_1")
            #expect(current.deviceId == "dev_1")
            #expect(current.externalId == "u_1")
            #expect(current.name == "Jane")
            #expect(current.metadata?["tier"] == .string("gold"))
            #expect(await sdk.isSubscriberLoggedIn == true)
            #expect(await sdk.subscriberId() == "sub_1")

            await PushFire.shutdown()
        }

        // MARK: - Tags

        @Test func addTagPostsTagBody() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok("{}")],
                store: registeredStore([StorageKey.subscriberId: "sub_1"])
            )

            let tag = try await sdk.addTag("plan", value: "pro")

            #expect(tag == SubscriberTag(tagId: "plan", subscriberId: "sub_1", value: "pro"))

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "POST")
            #expect(recorded[0].url?.lastPathComponent == "add-subscriber-tag")

            let data = try await transport.requestData(at: 0)
            #expect(data["tagId"] as? String == "plan")
            #expect(data["subscriberId"] as? String == "sub_1")
            #expect(data["value"] as? String == "pro")

            await PushFire.shutdown()
        }

        @Test func updateTagPatchesTagBody() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok("{}")],
                store: registeredStore([StorageKey.subscriberId: "sub_1"])
            )

            let tag = try await sdk.updateTag("plan", value: "enterprise")

            #expect(tag == SubscriberTag(tagId: "plan", subscriberId: "sub_1", value: "enterprise"))

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "PATCH")
            #expect(recorded[0].url?.lastPathComponent == "update-subscriber-tag")

            let data = try await transport.requestData(at: 0)
            #expect(data["tagId"] as? String == "plan")
            #expect(data["subscriberId"] as? String == "sub_1")
            #expect(data["value"] as? String == "enterprise")

            await PushFire.shutdown()
        }

        @Test func removeTagDeletesWithoutAValue() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok("{}")],
                store: registeredStore([StorageKey.subscriberId: "sub_1"])
            )

            try await sdk.removeTag("plan")

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "DELETE")
            #expect(recorded[0].url?.lastPathComponent == "remove-subscriber-tag")

            let data = try await transport.requestData(at: 0)
            #expect(data["tagId"] as? String == "plan")
            #expect(data["subscriberId"] as? String == "sub_1")
            #expect(data["value"] == nil)

            await PushFire.shutdown()
        }

        @Test func addTagsSendsEachTagInOrderAndReportsBothOutcomes() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok("{}"), .failure(400, #"{"message":"Unknown tag"}"#)],
                store: registeredStore([StorageKey.subscriberId: "sub_1"])
            )

            let result = try await sdk.addTags([("plan", "pro"), ("tier", "gold")])

            let added = SubscriberTag(tagId: "plan", subscriberId: "sub_1", value: "pro")
            #expect(result.succeeded == [added])
            #expect(result.failed.count == 1)
            #expect(result.failed[0].tagId == "tier")
            #expect(result.failed[0].message == "Unknown tag")
            #expect(result.isCompleteSuccess == false)

            let recorded = await transport.recorded
            #expect(recorded.count == 2)
            #expect(recorded.allSatisfy { $0.httpMethod == "POST" })
            #expect(recorded.allSatisfy { $0.url?.lastPathComponent == "add-subscriber-tag" })

            let first = try await transport.requestData(at: 0)
            #expect(first["tagId"] as? String == "plan")
            #expect(first["value"] as? String == "pro")
            let second = try await transport.requestData(at: 1)
            #expect(second["tagId"] as? String == "tier")
            #expect(second["value"] as? String == "gold")

            await PushFire.shutdown()
        }

        @Test func updateTagsPatchesEachTagAndReportsBothOutcomes() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.failure(404, #"{"message":"No such tag"}"#), .ok("{}")],
                store: registeredStore([StorageKey.subscriberId: "sub_1"])
            )

            let result = try await sdk.updateTags([("plan", "pro"), ("tier", "gold")])

            #expect(result.failed.count == 1)
            #expect(result.failed[0].tagId == "plan")
            #expect(result.failed[0].message == "No such tag")
            let updated = SubscriberTag(tagId: "tier", subscriberId: "sub_1", value: "gold")
            #expect(result.succeeded == [updated])
            #expect(result.isCompleteSuccess == false)

            let recorded = await transport.recorded
            #expect(recorded.count == 2)
            #expect(recorded.allSatisfy { $0.httpMethod == "PATCH" })
            #expect(recorded.allSatisfy { $0.url?.lastPathComponent == "update-subscriber-tag" })

            let second = try await transport.requestData(at: 1)
            #expect(second["tagId"] as? String == "tier")
            #expect(second["subscriberId"] as? String == "sub_1")
            #expect(second["value"] as? String == "gold")

            await PushFire.shutdown()
        }

        @Test func removeTagsDeletesEachTagAndReportsBothOutcomes() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok("{}"), .failure(404, #"{"message":"Not found"}"#)],
                store: registeredStore([StorageKey.subscriberId: "sub_1"])
            )

            let result = try await sdk.removeTags(["plan", "tier"])

            // A removed tag has no value left, so the succeeded entry carries an empty one.
            let removed = SubscriberTag(tagId: "plan", subscriberId: "sub_1", value: "")
            #expect(result.succeeded == [removed])
            #expect(result.failed.count == 1)
            #expect(result.failed[0].tagId == "tier")
            #expect(result.failed[0].message == "Not found")
            #expect(result.isCompleteSuccess == false)

            let recorded = await transport.recorded
            #expect(recorded.count == 2)
            #expect(recorded.allSatisfy { $0.httpMethod == "DELETE" })
            #expect(recorded.allSatisfy { $0.url?.lastPathComponent == "remove-subscriber-tag" })

            let second = try await transport.requestData(at: 1)
            #expect(second["tagId"] as? String == "tier")
            #expect(second["subscriberId"] as? String == "sub_1")
            #expect(second["value"] == nil)

            await PushFire.shutdown()
        }

        // MARK: - Workflows

        @Test func runWorkflowPostsAnImmediateExecutionForSubscribers() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok(#"{"id":"exec_1","message":"queued"}"#)],
                store: registeredStore()
            )

            let response = try await sdk.runWorkflow(
                Self.workflowUUID,
                for: .subscribers([Self.targetUUID])
            )

            #expect(response.id == "exec_1")
            #expect(response.message == "queued")

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "POST")
            #expect(recorded[0].url?.lastPathComponent == "create-workflow-execution")

            let data = try await transport.requestData(at: 0)
            #expect(data["workflowId"] as? String == Self.workflowUUID)
            #expect(data["type"] as? String == "Immediate")
            #expect(data["scheduledFor"] == nil)
            let target = try #require(data["target"] as? [String: Any])
            #expect(target["type"] as? String == "Subscribers")
            #expect(target["values"] as? [String] == [Self.targetUUID])

            await PushFire.shutdown()
        }

        @Test func runWorkflowPostsAScheduledExecutionForSegments() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install([.ok("{}")], store: registeredStore())

            let response = try await sdk.runWorkflow(
                Self.workflowUUID,
                for: .segments([Self.targetUUID]),
                at: Date(timeIntervalSince1970: 1_700_000_000)
            )

            #expect(response.id == nil)
            #expect(response.message == nil)

            let data = try await transport.requestData(at: 0)
            #expect(data["workflowId"] as? String == Self.workflowUUID)
            #expect(data["type"] as? String == "Scheduled")
            #expect(data["scheduledFor"] as? String == "2023-11-14T22:13:20.000Z")
            let target = try #require(data["target"] as? [String: Any])
            #expect(target["type"] as? String == "Segments")
            #expect(target["values"] as? [String] == [Self.targetUUID])

            await PushFire.shutdown()
        }

        @Test func createWorkflowExecutionSendsTheSuppliedRequestVerbatim() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install(
                [.ok(#"{"data":{"id":"exec_2"}}"#)],
                store: registeredStore()
            )

            let response = try await sdk.createWorkflowExecution(
                WorkflowExecutionRequest(
                    workflowId: Self.workflowUUID,
                    type: .immediate,
                    target: WorkflowTarget(
                        type: .subscribers,
                        values: [Self.targetUUID, Self.otherTargetUUID]
                    )
                )
            )

            #expect(response.id == "exec_2")

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "POST")
            #expect(recorded[0].url?.lastPathComponent == "create-workflow-execution")

            let data = try await transport.requestData(at: 0)
            #expect(data["workflowId"] as? String == Self.workflowUUID)
            #expect(data["type"] as? String == "Immediate")
            #expect(data["scheduledFor"] == nil)
            let target = try #require(data["target"] as? [String: Any])
            #expect(target["type"] as? String == "Subscribers")
            #expect(target["values"] as? [String] == [Self.targetUUID, Self.otherTargetUUID])

            await PushFire.shutdown()
        }

        @Test func createWorkflowExecutionRejectsAnInvalidRequestBeforeSending() async throws {
            await PushFire.shutdown()
            let (sdk, transport) = try await install([], store: registeredStore())

            await #expect(throws: PushFireError.self) {
                _ = try await sdk.createWorkflowExecution(
                    WorkflowExecutionRequest(
                        workflowId: "not-a-uuid",
                        type: .immediate,
                        target: WorkflowTarget(type: .subscribers, values: [Self.targetUUID])
                    )
                )
            }

            // Proves validation ran in the facade's path, not that the transport ran dry.
            #expect(await transport.recorded.isEmpty)

            await PushFire.shutdown()
        }

        // MARK: - Notifications

        @Test func requestNotificationPermissionPromptsThenReRegistersTheDevice() async throws {
            await PushFire.shutdown()
            let permissions = FakePermissionProvider(
                status: .notDetermined,
                requestResult: .authorized
            )
            let (sdk, transport) = try await install(
                [.ok("{}")],
                store: registeredStore(),
                permissions: permissions
            )
            let events = await sdk.events

            let granted = try await sdk.requestNotificationPermission()

            #expect(granted == true)
            // Interruptive, not provisional: this is the explicit prompt.
            #expect(permissions.requestedProvisional == [false])

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "PATCH")
            #expect(recorded[0].url?.lastPathComponent == "update-device")

            let data = try await transport.requestData(at: 0)
            #expect(data["id"] as? String == "dev_1")
            #expect(data["fcmToken"] as? String == "fcm-token")
            #expect(data["pushNotificationEnabled"] as? Bool == true)

            let device = try #require(await sdk.currentDevice)
            #expect(device.pushNotificationEnabled == true)
            #expect(await nextEvent(events) == .deviceRegistered(device))

            await PushFire.shutdown()
        }

        @Test func notificationStatusReportsOSPermissionAndStoredPreference() async throws {
            await PushFire.shutdown()
            let (sdk, _) = try await install(
                [],
                store: registeredStore([StorageKey.notificationPreference: false]),
                permissions: FakePermissionProvider(status: .authorized)
            )

            #expect(
                await sdk.notificationStatus()
                    == NotificationStatus(
                        isPermissionGranted: true,
                        isEnabled: false
                    ))

            await PushFire.shutdown()

            let (denied, _) = try await install(
                [],
                store: registeredStore(),
                permissions: FakePermissionProvider(status: .denied)
            )

            // No stored preference defaults to enabled, independent of the OS permission.
            #expect(
                await denied.notificationStatus()
                    == NotificationStatus(
                        isPermissionGranted: false,
                        isEnabled: true
                    ))

            await PushFire.shutdown()
        }

        @Test func setNotificationEnabledPatchesTheDeviceAndPersistsThePreference() async throws {
            await PushFire.shutdown()
            let store = registeredStore()
            let (sdk, transport) = try await install([.ok("{}")], store: store)
            let events = await sdk.events

            let result = try await sdk.setNotificationEnabled(false)

            #expect(result == .success)
            #expect(store.bool(forKey: StorageKey.notificationPreference) == false)

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "PATCH")
            #expect(recorded[0].url?.lastPathComponent == "update-device")

            let data = try await transport.requestData(at: 0)
            #expect(data["id"] as? String == "dev_1")
            #expect(data["fcmToken"] as? String == "fcm-token")
            #expect(data["os"] as? String == "ios")
            #expect(data["osVersion"] as? String == "18.0")
            #expect(data["language"] as? String == "en_US")
            #expect(data["manufacturer"] as? String == "Apple")
            #expect(data["model"] as? String == "iPhone")
            #expect(data["appVersion"] as? String == "1.0.0")
            #expect(data["pushNotificationEnabled"] as? Bool == false)

            let device = try #require(await sdk.currentDevice)
            #expect(device.pushNotificationEnabled == false)
            #expect(await nextEvent(events) == .deviceRegistered(device))

            await PushFire.shutdown()
        }

        @Test func setNotificationEnabledRefusesToEnableWhenPermissionDenied() async throws {
            await PushFire.shutdown()
            let store = registeredStore()
            let (sdk, transport) = try await install(
                [],
                store: store,
                permissions: FakePermissionProvider(status: .denied)
            )

            let result = try await sdk.setNotificationEnabled(true)

            #expect(result == .systemPermissionDenied)
            // Nothing changed: no request, and no preference written.
            #expect(await transport.recorded.isEmpty)
            #expect(store.bool(forKey: StorageKey.notificationPreference) == nil)

            await PushFire.shutdown()
        }

        @Test func syncNotificationPermissionPushesARevokedPermissionToTheServer() async throws {
            await PushFire.shutdown()
            let permissions = FakePermissionProvider(status: .authorized)
            let (sdk, transport) = try await install(
                [.ok("{}")],
                store: registeredStore(),
                permissions: permissions
            )
            let events = await sdk.events

            // The user turns notifications off in Settings while the app is backgrounded.
            permissions.setStatus(.denied)

            let status = await sdk.syncNotificationPermission()

            #expect(status == NotificationStatus(isPermissionGranted: false, isEnabled: true))

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "PATCH")
            #expect(recorded[0].url?.lastPathComponent == "update-device")

            let data = try await transport.requestData(at: 0)
            #expect(data["id"] as? String == "dev_1")
            #expect(data["pushNotificationEnabled"] as? Bool == false)

            let device = try #require(await sdk.currentDevice)
            #expect(device.pushNotificationEnabled == false)
            #expect(await nextEvent(events) == .deviceRegistered(device))

            await PushFire.shutdown()
        }

        @Test func openNotificationSettingsReturnsWhatThePlatformReports() async throws {
            await PushFire.shutdown()
            let refusing = FakePermissionProvider(status: .denied)
            refusing.settingsOpenResult = false
            let (sdk, _) = try await install([], store: registeredStore(), permissions: refusing)

            #expect(await sdk.openNotificationSettings() == false)
            #expect(refusing.openedSettings == 1)

            await PushFire.shutdown()

            let opening = FakePermissionProvider(status: .denied)
            opening.settingsOpenResult = true
            let (other, _) = try await install([], store: registeredStore(), permissions: opening)

            #expect(await other.openNotificationSettings() == true)
            #expect(opening.openedSettings == 1)

            await PushFire.shutdown()
        }

        // MARK: - Device and events

        @Test func currentDeviceAndDeviceIdExposeTheRegistrationMadeAtConfigure() async throws {
            await PushFire.shutdown()
            let store = FakeStore()
            let (sdk, transport) = try await install([.ok(#"{"id":"dev_1"}"#)], store: store)

            let recorded = await transport.recorded
            #expect(recorded.count == 1)
            #expect(recorded[0].httpMethod == "POST")
            #expect(recorded[0].url?.lastPathComponent == "register-device")

            let data = try await transport.requestData(at: 0)
            // A brand-new device carries no id.
            #expect(data["id"] == nil)
            #expect(data["fcmToken"] as? String == "fcm-token")
            #expect(data["os"] as? String == "ios")
            #expect(data["osVersion"] as? String == "18.0")
            #expect(data["language"] as? String == "en_US")
            #expect(data["manufacturer"] as? String == "Apple")
            #expect(data["model"] as? String == "iPhone")
            #expect(data["appVersion"] as? String == "1.0.0")
            #expect(data["pushNotificationEnabled"] as? Bool == true)

            #expect(await sdk.deviceId() == "dev_1")
            #expect(
                await sdk.currentDevice
                    == Device(
                        id: "dev_1",
                        fcmToken: "fcm-token",
                        os: "ios",
                        osVersion: "18.0",
                        language: "en_US",
                        manufacturer: "Apple",
                        model: "iPhone",
                        appVersion: "1.0.0",
                        pushNotificationEnabled: true
                    ))

            await PushFire.shutdown()
        }

        @Test func eventsHandsEachCallerAnIndependentStream() async throws {
            await PushFire.shutdown()
            let (sdk, _) = try await install(
                [.ok(#"{"id":"sub_1"}"#)],
                store: registeredStore()
            )

            let first = await sdk.events
            let second = await sdk.events

            let subscriber = try await sdk.login(externalId: "u_1", name: "Jane")

            // Both streams see the same event; neither consumes it from the other.
            #expect(await nextEvent(first) == .subscriberLoggedIn(subscriber))
            #expect(await nextEvent(second) == .subscriberLoggedIn(subscriber))

            await PushFire.shutdown()
        }

        @Test func resetLogsOutAndWipesEveryLocalKey() async throws {
            await PushFire.shutdown()
            let store = FakeStore()
            let (sdk, transport) = try await install(
                [.ok(#"{"id":"dev_1"}"#), .ok(#"{"id":"sub_1"}"#), .ok("{}")],
                store: store
            )

            try await sdk.login(externalId: "u_1")
            try await sdk.reset()

            let recorded = await transport.recorded
            #expect(recorded.count == 3)
            #expect(recorded[2].httpMethod == "POST")
            #expect(recorded[2].url?.lastPathComponent == "logout-subscriber")

            let data = try await transport.requestData(at: 2)
            #expect(data["deviceId"] as? String == "dev_1")
            #expect(data["subscriberId"] as? String == "sub_1")

            #expect(store.string(forKey: StorageKey.deviceId) == nil)
            #expect(store.string(forKey: StorageKey.fcmToken) == nil)
            #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == nil)
            #expect(store.bool(forKey: StorageKey.notificationPreference) == nil)
            #expect(store.string(forKey: StorageKey.subscriberId) == nil)
            #expect(store.string(forKey: StorageKey.subscriberData) == nil)

            #expect(await sdk.currentDevice == nil)
            #expect(await sdk.deviceId() == nil)
            #expect(await sdk.currentSubscriber == nil)
            #expect(await sdk.isSubscriberLoggedIn == false)

            await PushFire.shutdown()
        }
    }
}
