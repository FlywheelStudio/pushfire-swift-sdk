import PushFire
import SwiftUI

struct ContentView: View {
    @State private var deviceId = "not registered"
    @State private var externalId = "user_123"
    @State private var status: NotificationStatus?
    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("Device id", value: deviceId)
                    LabeledContent(
                        "OS permission",
                        value: status.map { $0.isPermissionGranted ? "granted" : "denied" }
                            ?? "unknown"
                    )
                    LabeledContent(
                        "PushFire enabled",
                        value: status.map { $0.isEnabled ? "yes" : "no" } ?? "unknown"
                    )
                }

                Section("Subscriber") {
                    TextField("External id", text: $externalId)
                        .textInputAutocapitalization(.never)
                    Button("Log in") { run { try await PushFire.shared.login(externalId: externalId) } }
                    Button("Add tag plan=pro") {
                        run { try await PushFire.shared.addTag("plan", value: "pro") }
                    }
                    Button("Log out") { run { try await PushFire.shared.logout() } }
                }

                Section("Notifications") {
                    Button("Request permission") {
                        run { try await PushFire.shared.requestNotificationPermission() }
                    }
                    Button("Turn PushFire off") {
                        run { try await PushFire.shared.setNotificationEnabled(false) }
                    }
                    Button("Turn PushFire on") {
                        run { try await PushFire.shared.setNotificationEnabled(true) }
                    }
                    Button("Open Settings") {
                        run { try await PushFire.shared.openNotificationSettings() }
                    }
                }

                Section("Events") {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("PushFire")
            .task { await observe() }
            .task { await refresh() }
        }
    }

    private func observe() async {
        guard let sdk = try? PushFire.shared else { return }
        for await event in await sdk.events {
            log.insert(String(describing: event), at: 0)
            await refresh()
        }
    }

    private func refresh() async {
        guard let sdk = try? PushFire.shared else { return }
        deviceId = await sdk.deviceId() ?? "not registered"
        status = await sdk.notificationStatus()
    }

    /// Runs an SDK call and records the outcome.
    private func run(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                log.insert("error: \(error)", at: 0)
            }
            await refresh()
        }
    }
}
