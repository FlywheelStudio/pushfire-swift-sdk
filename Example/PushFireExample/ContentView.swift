import Foundation
import PushFire
import SwiftUI

/// Exercises the whole public surface of the SDK, one button per entry point, so the
/// example doubles as a manual test rig: every call reports what it returned or how it
/// failed into the log at the bottom.
struct ContentView: View {
    // Device
    @State private var deviceId = "not registered"
    @State private var device: Device?
    @State private var status: NotificationStatus?

    // Subscriber
    @State private var externalId = "user_123"
    @State private var subscriber: Subscriber?
    @State private var subscriberId: String?
    @State private var isLoggedIn = false

    // Workflows
    @State private var workflowId = ""

    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                sdkSection
                deviceSection
                subscriberSection
                tagSection
                workflowSection
                resetSection
                logSection
            }
            .navigationTitle("PushFire")
            .task {
                // Configure before observing. `PushFire.shared` throws until configure
                // completes, so starting the event loop in a separate task would race it
                // and silently give up.
                do {
                    try await PushFire.configure(
                        PushFireConfiguration(
                            apiKey: ProcessInfo.processInfo
                                .environment["PUSHFIRE_API_KEY"] ?? "",
                            enableLogging: true
                        )
                    )
                } catch {
                    append("configure failed: \(error)")
                    return
                }

                await refresh()
                await observe()
            }
        }
    }

    // MARK: - Sections

    private var sdkSection: some View {
        Section("SDK") {
            LabeledContent("Version", value: PushFire.sdkVersion)
            LabeledContent("Configured", value: PushFire.isConfigured ? "yes" : "no")
            LabeledContent("Base URL", value: baseURL)
            Button("Shut down", role: .destructive) {
                Task {
                    await PushFire.shutdown()
                    append("shutdown: observers stopped, instance released")
                    await refresh()
                }
            }
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            LabeledContent("Device id", value: deviceId)
            LabeledContent("Push token", value: maskedToken)
            LabeledContent("Model", value: device.map { "\($0.model), \($0.os) \($0.osVersion)" } ?? "unknown")
            LabeledContent(
                "OS permission",
                value: status.map { $0.isPermissionGranted ? "granted" : "denied" } ?? "unknown"
            )
            LabeledContent(
                "PushFire enabled",
                value: status.map { $0.isEnabled ? "yes" : "no" } ?? "unknown"
            )

            Button("Request permission") {
                run("requestNotificationPermission") {
                    let granted = try await PushFire.shared.requestNotificationPermission()
                    return granted ? "granted" : "denied"
                }
            }
            Button("Turn PushFire off") {
                run("setNotificationEnabled(false)") {
                    "\(try await PushFire.shared.setNotificationEnabled(false))"
                }
            }
            Button("Turn PushFire on") {
                run("setNotificationEnabled(true)") {
                    // Returns .systemPermissionDenied, without a server call, when the OS
                    // permission is off — enabling in PushFire cannot grant it.
                    "\(try await PushFire.shared.setNotificationEnabled(true))"
                }
            }
            Button("Sync permission now") {
                run("syncNotificationPermission") {
                    // The SDK syncs on foreground automatically. Call this after sending
                    // the user to Settings, to pick the change up without waiting.
                    let synced = try await PushFire.shared.syncNotificationPermission()
                    return "permission \(synced.isPermissionGranted), enabled \(synced.isEnabled)"
                }
            }
            Button("Open Settings") {
                run("openNotificationSettings") {
                    "\(try await PushFire.shared.openNotificationSettings())"
                }
            }
        }
    }

    private var subscriberSection: some View {
        Section("Subscriber") {
            TextField("External id", text: $externalId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            LabeledContent("Logged in", value: isLoggedIn ? "yes" : "no")
            LabeledContent("Subscriber id", value: subscriberId ?? "none")
            LabeledContent("Name", value: subscriber?.name ?? "none")

            Button("Log in") {
                run("login") {
                    let result = try await PushFire.shared.login(
                        externalId: externalId,
                        name: "Example User",
                        email: "user@example.com",
                        phone: "+15551234567",
                        metadata: ["tier": .string("gold"), "seats": .int(3)]
                    )
                    return result.id ?? "no id"
                }
            }
            Button("Update details") {
                run("updateSubscriber") {
                    // Only the fields passed are changed; the rest are left alone.
                    let result = try await PushFire.shared.updateSubscriber(
                        name: "Renamed User",
                        metadata: ["tier": .string("platinum")]
                    )
                    return result.name ?? "no name"
                }
            }
            Button("Log out") {
                run("logout") {
                    try await PushFire.shared.logout()
                    return nil
                }
            }
        }
    }

    private var tagSection: some View {
        Section("Tags") {
            Button("Add plan=pro") {
                run("addTag") { "\(try await PushFire.shared.addTag("plan", value: "pro").value)" }
            }
            Button("Update plan=enterprise") {
                run("updateTag") {
                    "\(try await PushFire.shared.updateTag("plan", value: "enterprise").value)"
                }
            }
            Button("Remove plan") {
                run("removeTag") {
                    try await PushFire.shared.removeTag("plan")
                    return nil
                }
            }
            Button("Add three at once") {
                run("addTags") {
                    // Bulk calls report both sides rather than throwing on the first
                    // failure, so a partial success is visible.
                    describe(
                        try await PushFire.shared.addTags([
                            ("plan", "pro"), ("region", "eu"), ("beta", "true"),
                        ]))
                }
            }
            Button("Update three at once") {
                run("updateTags") {
                    describe(
                        try await PushFire.shared.updateTags([
                            ("plan", "free"), ("region", "us"), ("beta", "false"),
                        ]))
                }
            }
            Button("Remove three at once") {
                run("removeTags") {
                    describe(try await PushFire.shared.removeTags(["plan", "region", "beta"]))
                }
            }
        }
    }

    private var workflowSection: some View {
        Section("Workflows") {
            TextField("Workflow id (UUID)", text: $workflowId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Run now for this subscriber") {
                run("runWorkflow") {
                    let response = try await PushFire.shared.runWorkflow(
                        workflowId,
                        for: .subscribers([subscriberId ?? ""])
                    )
                    return response.id ?? response.message ?? "accepted"
                }
            }
            Button("Schedule in one minute") {
                run("runWorkflow(at:)") {
                    let response = try await PushFire.shared.runWorkflow(
                        workflowId,
                        for: .subscribers([subscriberId ?? ""]),
                        at: Date().addingTimeInterval(60)
                    )
                    return response.id ?? response.message ?? "scheduled"
                }
            }
            Button("Send a hand-built request") {
                run("createWorkflowExecution") {
                    // The escape hatch: build the request yourself when runWorkflow's
                    // shape does not cover what you need.
                    let response = try await PushFire.shared.createWorkflowExecution(
                        WorkflowExecutionRequest(
                            workflowId: workflowId,
                            type: .immediate,
                            target: WorkflowTarget(
                                type: .subscribers,
                                values: [subscriberId ?? ""]
                            )
                        )
                    )
                    return response.id ?? response.message ?? "accepted"
                }
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset all local state", role: .destructive) {
                run("reset") {
                    // Logs out if logged in, then clears the subscriber and device
                    // records. The next launch registers as a new device.
                    try await PushFire.shared.reset()
                    return nil
                }
            }
        } footer: {
            Text("Clears the stored device id, push token, permission state and subscriber.")
        }
    }

    private var logSection: some View {
        Section("Events and results") {
            if log.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced())
            }
        }
    }

    // MARK: - Derived values

    private var baseURL: String {
        guard let sdk = try? PushFire.shared else { return "unknown" }
        return sdk.configuration.baseURL.absoluteString
    }

    /// Tokens are long and are a send capability; show only enough to match one against
    /// the server.
    private var maskedToken: String {
        guard let token = device?.fcmToken else { return "none" }
        guard token.count > 20 else { return token }
        return "\(token.prefix(10))...\(token.suffix(10))"
    }

    private func describe(_ result: BulkTagResult) -> String {
        result.isCompleteSuccess
            ? "\(result.succeeded.count) succeeded"
            : "\(result.succeeded.count) succeeded, \(result.failed.count) failed: "
                + result.failed.map { "\($0.tagId) (\($0.message))" }.joined(separator: ", ")
    }

    // MARK: - Plumbing

    private func observe() async {
        guard let sdk = try? PushFire.shared else { return }
        for await event in await sdk.events {
            append(String(describing: event))
            await refresh()
        }
    }

    private func refresh() async {
        guard let sdk = try? PushFire.shared else {
            deviceId = "not registered"
            device = nil
            status = nil
            subscriber = nil
            subscriberId = nil
            isLoggedIn = false
            return
        }
        deviceId = await sdk.deviceId() ?? "not registered"
        device = await sdk.currentDevice
        status = await sdk.notificationStatus()
        subscriber = await sdk.currentSubscriber
        subscriberId = await sdk.subscriberId()
        isLoggedIn = await sdk.isSubscriberLoggedIn
    }

    /// Runs an SDK call and records what it returned, or how it failed.
    private func run(_ label: String, _ operation: @escaping () async throws -> String?) {
        Task {
            do {
                if let detail = try await operation() {
                    append("\(label): \(detail)")
                } else {
                    append("\(label): ok")
                }
            } catch {
                append("\(label) failed: \(error)")
            }
            await refresh()
        }
    }

    private func append(_ line: String) {
        log.insert(line, at: 0)
    }
}
