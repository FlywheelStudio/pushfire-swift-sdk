# PushFire Swift SDK

A native Swift SDK for integrating with the PushFire push notification platform. It handles
device registration with Firebase Cloud Messaging, subscriber login, tag management,
notification permission state, and workflow execution. Requires iOS 16.0+ and Swift Package
Manager.

## Installation

In Xcode, File → Add Package Dependencies, and enter:

```
https://github.com/FlywheelStudio/pushfire-swift-sdk
```

Choose "Up to Next Major Version" from `0.1.0`, and add the `PushFire` library. Add
`PushFireFirebaseAuth` or `PushFireSupabaseAuth` as well only if you want subscribers
logged in automatically from your auth state.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/FlywheelStudio/pushfire-swift-sdk", from: "0.1.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "PushFire", package: "pushfire-swift-sdk")
    ])
]
```

`PushFire` is the only product the core SDK needs, and it links `FirebaseMessaging` only. A
consumer who wants neither Firebase Auth nor Supabase Auth integration downloads neither
dependency — the split exists specifically so those two libraries stay opt-in.

## Firebase setup

The SDK uses Firebase Cloud Messaging for push delivery, so a Firebase project is required:

1. Create a project at the [Firebase Console](https://console.firebase.google.com/).
2. Add an iOS app to the project, using your app's bundle identifier.
3. Download `GoogleService-Info.plist` and add it to your Xcode project target.
4. Call `FirebaseApp.configure()` yourself in your app delegate.

**The SDK does not call `FirebaseApp.configure()` for you.** This is the most likely
integration mistake — if you skip it, Firebase Messaging has no project to talk to and device
registration will fail silently or crash, depending on what else touches Firebase first.

**The SDK also depends on `Messaging.messaging().apnsToken` being set**, which Firebase
normally populates automatically through its app-delegate method swizzling. If your app
disables that swizzling — setting `FirebaseAppDelegateProxyEnabled` to `NO` in Info.plist,
which is routine when the app has its own `UNUserNotificationCenterDelegate` or ships another
push SDK — you must forward the APNs token to Firebase yourself:

```swift
import UIKit
import FirebaseMessaging

func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    Messaging.messaging().apnsToken = deviceToken
}
```

Without it the SDK never obtains a token, never registers, and reports no error —
`configure()` still succeeds.

## Xcode capabilities

In your target's Signing & Capabilities tab, add:

- **Push Notifications**
- **Background Modes**, with **Remote notifications** enabled

## Getting started

Configure Firebase first — the SDK does not do it for you:

```swift
import FirebaseCore
import PushFire

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}
```

Then configure PushFire once at launch:

```swift
try await PushFire.configure(
    PushFireConfiguration(
        apiKey: "your-api-key",
        enableLogging: true
    )
)
```

`enableLogging` is meant for development. It writes subscriber external ids, subscriber ids,
and device ids to the unified system log at `os.Logger`'s `.public` privacy level (request and
response bodies are logged at `.private`). Leave it off in release builds.

`PushFire.shared` throws `PushFireError.notInitialized` until `configure` completes, so
calls read `try await PushFire.shared.login(...)`. A single `try` covers both the
accessor and the call.

There is no way to await configuration from anywhere other than the call site — `shared`
either returns the instance or throws, it does not wait. Sequence everything that touches
`shared` after the `configure` call completes, in the same task. The example app's
`ContentView.swift` does this in a single sequential `.task`:

```swift
.task {
    // Configure before observing. `PushFire.shared` throws until configure
    // completes, so starting the event loop in a separate task would race it
    // and silently give up.
    do {
        try await PushFire.configure(
            PushFireConfiguration(apiKey: apiKey, enableLogging: true)
        )
    } catch {
        // handle configuration failure
        return
    }

    await refresh()
    await observe()
}
```

Do not start an event observer (or any other `shared`-touching work) in a second, separate
task alongside `configure`. That races the configuration call: if the observer's task runs
first, `try? PushFire.shared` fails, and the observer gives up silently with no error and no
retry.

## Configuration

`PushFireConfiguration` has seven properties. Only `apiKey` is required.

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `apiKey` | `String` | required | Project API key. Sent as `Authorization: Bearer <apiKey>`. |
| `baseURL` | `URL` | `https://api.pushfire.app/functions/v1/` | Base URL for the PushFire API. The trailing slash is significant. |
| `enableLogging` | `Bool` | `false` | Emit SDK logs through `os.Logger`. See the logging note above. |
| `timeout` | `TimeInterval` | `30` | Request timeout in seconds. |
| `requestNotificationPermission` | `Bool` | `true` | Request the notification permission during `configure`. |
| `registerWithoutPrompt` | `Bool` | `false` | See below. |
| `userDefaultsSuiteName` | `String?` | `nil` | `UserDefaults` suite for SDK state. Pass an app-group suite to share state with a Notification Service Extension. |

**`registerWithoutPrompt`** only has an effect when `requestNotificationPermission` is
`false`. When both are set that way, the SDK still triggers remote-notification
registration so an APNs token — and therefore an FCM token — can be obtained without
showing the interruptive permission dialog. It does this by requesting *provisional*
authorization: the OS registers for remote notifications and delivers notifications
quietly to Notification Center, without a prompt. Provisional authorization is not the
same as no authorization — it is a user-visible behavior change, since the user can later
be asked whether to keep or turn off notifications. For registration with no authorization
at all, call `UIApplication.shared.registerForRemoteNotifications()` yourself and leave
`registerWithoutPrompt` false.

## API reference

### Subscribers

```swift
// Logs a subscriber in, creating them if they do not exist. @discardableResult.
try await PushFire.shared.login(
    externalId: "user_123",
    name: "Jane",
    email: "jane@example.com",
    phone: "+15555550123",
    metadata: ["plan": .string("pro")]
)

// Updates the logged-in subscriber. externalId cannot be changed. @discardableResult.
try await PushFire.shared.updateSubscriber(name: "Jane Doe")

// Logs the current subscriber out.
try await PushFire.shared.logout()

// The logged-in subscriber, read from local storage.
let subscriber = try await PushFire.shared.currentSubscriber

// Whether a subscriber is logged in.
let isLoggedIn = try await PushFire.shared.isSubscriberLoggedIn

// The PushFire subscriber id, if logged in.
let subscriberId = try await PushFire.shared.subscriberId()
```

### Tags

```swift
// Single-tag operations. addTag and updateTag are @discardableResult; removeTag returns Void.
try await PushFire.shared.addTag("plan", value: "pro")
try await PushFire.shared.updateTag("plan", value: "enterprise")
try await PushFire.shared.removeTag("plan")

// Bulk operations run sequentially and report successes and failures separately.
// @discardableResult.
let result = try await PushFire.shared.addTags([("plan", "pro"), ("region", "us-west")])
print(result.succeeded, result.failed)

try await PushFire.shared.updateTags([("plan", "enterprise")])

// For removals, each succeeded entry's `value` is empty — `tagId` is the field that
// matters, since a removed tag no longer has a value.
try await PushFire.shared.removeTags(["plan", "region"])
```

`addTag`, `updateTag`, `setNotificationEnabled`, and the other `@discardableResult` methods
are marked that way deliberately — call them without `_ = ` when you do not need the return
value.

### Notifications

```swift
// Prompts for the OS notification permission. Returns whether it was granted.
// @discardableResult.
let granted = try await PushFire.shared.requestNotificationPermission()

// The OS permission state and the PushFire preference.
let status = try await PushFire.shared.notificationStatus()

// Turns the PushFire preference on or off for this device. @discardableResult.
let result = try await PushFire.shared.setNotificationEnabled(true)

// Re-checks the OS permission and syncs any change to PushFire. @discardableResult.
let synced = try await PushFire.shared.syncNotificationPermission()

// Opens this app's page in Settings. @discardableResult.
let opened = try await PushFire.shared.openNotificationSettings()
```

`openNotificationSettings()` cannot itself throw — it has no `throws` in its own signature —
but calling it still reads `try await PushFire.shared.openNotificationSettings()` because the
`try` belongs to the `shared` accessor, not the method. This is not a bug; every call through
`shared` needs `try` for the same reason.

### Workflows

```swift
// Runs a workflow now, or later with `at:`. @discardableResult.
try await PushFire.shared.runWorkflow(
    "550e8400-e29b-41d4-a716-446655440000",
    for: .subscribers(["6ba7b810-9dad-11d1-80b4-00c04fd430c8"])
)

try await PushFire.shared.runWorkflow(
    "550e8400-e29b-41d4-a716-446655440000",
    for: .segments(["6ba7b811-9dad-11d1-80b4-00c04fd430c8"]),
    at: Date().addingTimeInterval(3600)
)
```

`WorkflowRunTarget` is a public enum with two cases, `.subscribers([String])` and
`.segments([String])`, each taking PushFire ids. Both `workflowId` and every target value
must be valid UUIDs — the request is rejected locally with `PushFireError.configuration`
before it reaches the network otherwise.

### Events

```swift
// A stream of SDK events. Each call to `events` returns an independent stream.
for await event in try await PushFire.shared.events {
    switch event {
    case .deviceRegistered(let device):
        print("Device registered:", device.id ?? "pending")
    case .subscriberLoggedIn(let subscriber):
        print("Logged in:", subscriber.externalId)
    case .subscriberLoggedOut:
        print("Logged out")
    case .pushTokenRefreshed(let token):
        print("New FCM token:", token)
    }
}
```

### Device and reset

```swift
// The registered device, if registration has completed.
let device = try await PushFire.shared.currentDevice

// The PushFire device id, if registered.
let deviceId = try await PushFire.shared.deviceId()

// Logs out and clears all local SDK state.
try await PushFire.shared.reset()

// Stops the SDK's observers and releases the instance.
await PushFire.shutdown()

// Whether `configure` has completed.
let configured = PushFire.isConfigured

// This SDK's version, matching the released git tag.
let version = PushFire.sdkVersion
```

## Notification state

PushFire tracks two independent things about notifications on a device, and conflating them
is the most common integration mistake:

1. **The OS permission** — whether the user has granted this app permission to show
   notifications at all. The system owns this; the SDK can only ask for it and observe it.
2. **The PushFire preference** — whether *this app* wants PushFire to deliver notifications to
   this device, set with `setNotificationEnabled(_:)`. The developer or user owns this through
   the SDK.

`NotificationStatus` exposes both: `isPermissionGranted` (the OS state) and `isEnabled` (the
PushFire preference, only meaningful when `isPermissionGranted` is true).

Consequences that follow from the split:

- **`setNotificationEnabled(true)` can fail without a network call.** If the OS permission is
  denied, it returns `.systemPermissionDenied` immediately and does not contact the server —
  there is nothing to enable server-side if the OS will not deliver anything anyway. Send the
  user to `openNotificationSettings()` to fix that from Settings.
- **The SDK syncs automatically when the app returns to the foreground.** It observes
  `UIApplication.didBecomeActiveNotification`, re-checks the OS permission, and updates the
  server if it changed. You do not need to poll for this yourself.
- **`syncNotificationPermission()` forces that same sync immediately**, rather than waiting for
  the next foreground transition. Call it right after the user comes back from
  `openNotificationSettings()`, when you want the updated status without waiting for the
  natural foreground event:

  ```swift
  try await PushFire.shared.openNotificationSettings()
  // ...user returns to the app
  let status = try await PushFire.shared.syncNotificationPermission()
  ```

- **If the developer turned the preference off, a later OS re-grant does not turn it back on.**
  Say the app called `setNotificationEnabled(false)`, and later the user re-grants the OS
  permission from Settings. The automatic foreground sync sees the permission change but
  checks the saved PushFire preference before restoring anything — since the developer said
  off, it stays off. The developer's choice wins over an incidental OS-level change.

## Auth integration

Both auth providers drive automatic subscriber login and logout from your existing auth
state — you do not need to call `login`/`logout` yourself once one is configured.

### Firebase Auth

Add the `PushFireFirebaseAuth` product, then:

```swift
import PushFireFirebaseAuth

try await PushFire.configure(
    PushFireConfiguration(apiKey: "your-api-key"),
    authProvider: FirebaseAuthProvider()
)
```

### Supabase Auth

Add the `PushFireSupabaseAuth` product, then pass your existing `SupabaseClient`:

```swift
import PushFireSupabaseAuth

try await PushFire.configure(
    PushFireConfiguration(apiKey: "your-api-key"),
    authProvider: SupabaseAuthProvider(client: supabase)
)
```

`SupabaseAuthProvider` takes the client rather than reaching for a global singleton, so it
works with however your app constructs and holds its `SupabaseClient`.

To integrate a different auth system, implement the `AuthProvider` protocol yourself — it is
a single `events: AsyncStream<AuthEvent>` requirement, where `AuthEvent` is `.signedIn(AuthUser)`
or `.signedOut`.

### Custom push token provider

`PushFire.configure` also takes an optional `pushTokenProvider:` parameter. The SDK ships a
FirebaseMessaging-backed implementation by default; pass your own to replace it:

```swift
try await PushFire.configure(
    PushFireConfiguration(apiKey: "your-api-key"),
    pushTokenProvider: MyPushTokenProvider()
)
```

`PushTokenProvider` is a public protocol with three requirements: `apnsToken() async -> String?`,
`fcmToken() async -> String?`, and `tokenRefreshes: AsyncStream<String>`. This is the
equivalent of the Flutter SDK's `getFcmTokenOverride` escape hatch, for apps that need custom
token acquisition instead of the default Firebase-backed one.

## Error handling

Every throwing SDK call throws `PushFireError`:

```swift
public enum PushFireError: Error, Sendable {
    case notInitialized
    case configuration(String)
    case device(String)
    case subscriber(String)
    case tag(String)
    case network(String)
    case api(message: String, code: String?, statusCode: Int?, responseBody: String?)
}
```

- `notInitialized` — `PushFire.shared` was accessed before `configure` completed.
- `configuration` — invalid configuration or invalid arguments to an SDK call.
- `device` — device registration or notification-preference failure.
- `subscriber` — subscriber login, update, or logout failure.
- `tag` — tag operation failure.
- `network` — transport-level failure: timeout, offline, DNS.
- `api` — a non-2xx response from the PushFire API, carrying the server's message, error
  code, HTTP status, and raw response body.

```swift
do {
    try await PushFire.shared.login(externalId: "user_123")
} catch PushFireError.api(let message, let code, let statusCode, _) {
    print("API error \(statusCode.map(String.init) ?? "?"): \(message) (\(code ?? "no code"))")
} catch {
    print("PushFire error: \(error)")
}
```

## Data storage

The SDK persists its state in `UserDefaults` — `UserDefaults.standard`, or the suite named
by `PushFireConfiguration.userDefaultsSuiteName` — under these keys:

- `pushfire_subscriber_data` — the full logged-in subscriber, as JSON: `name`, `email`,
  `phone`, and any caller-supplied `metadata`.
- `pushfire_device_id` — the registered PushFire device id.
- `pushfire_fcm_token` — the current FCM token.
- `pushfire_subscriber_id` — the logged-in subscriber's PushFire id.
- `pushfire_last_permission_status` — the last-observed OS notification permission.
- `pushfire_notification_preference` — the PushFire notification preference.

`UserDefaults` storage is an unencrypted plist inside the app container. It is readable on
a jailbroken device and is included in unencrypted device backups. Setting
`userDefaultsSuiteName` widens that exposure to every extension in the app group. Weigh
this before putting sensitive values in `metadata`.

## Differences from the Flutter SDK

If you are porting an app between the Flutter and Swift SDKs, or maintaining both, these are
the places the behavior diverges:

1. **`PushFire.shared` throws instead of being a plain singleton getter.** The Flutter SDK's
   `PushFireSDK.instance` does not throw before initialization; the Swift `PushFire.shared`
   throws `PushFireError.notInitialized` until `configure` completes. Every call through it
   needs `try`, including calls that cannot themselves fail (see `openNotificationSettings()`
   above).
2. **Bulk tag operations report failures instead of only logging them.** The Flutter SDK's
   `addTags`/`updateTags` log failures internally and return only what succeeded, silently
   dropping the rest. The Swift SDK's `BulkTagResult` returns both `succeeded` and `failed`
   explicitly, so a caller can react to a partial failure instead of discovering it was silent.
3. **Workflow targeting is a single enum, not four separate methods.** The Flutter SDK exposes
   `createImmediateWorkflowForSubscribers`, `createImmediateWorkflowForSegments`,
   `createScheduledWorkflowForSubscribers`, and `createScheduledWorkflowForSegments`. The
   Swift SDK collapses all four into one `runWorkflow(_:for:at:)`, where `WorkflowRunTarget`
   (`.subscribers` or `.segments`) picks the target and an optional `at:` picks immediate vs.
   scheduled.
4. **The platform floor is iOS 16.0, not the historical iOS 15 assumption.** This was raised
   late in the project because `supabase-swift` 2.50+ requires iOS 16; capping below it would
   have made `PushFireSupabaseAuth` unresolvable for any app already depending on a current
   `supabase-swift`.
5. **The device-registration comparison compares like for like.** The Flutter
   `DeviceService.registerDevice` originally compared the saved raw OS permission against
   the effective (permission AND preference) value, so a device whose developer disabled
   notifications PATCHed on every launch even though nothing had changed. The Swift SDK was
   written to compare raw against raw; the Flutter SDK has since been fixed the same way, so
   the two now match.
6. **The notification preference is saved only after a successful server update, not before.**
   The Flutter `DeviceService.setNotificationEnabled` originally persisted the local
   preference before making the PATCH, so a failed request left local and remote state
   disagreeing. The Swift SDK persists only once the server confirms; the Flutter SDK has
   since been fixed the same way, so the two now match.
7. **Storage keys are read with a `flutter.` fallback.** `shared_preferences` prefixes every
   key it writes with `flutter.`, so an app migrating from the Flutter SDK holds its state
   under `flutter.pushfire_device_id`. The Swift SDK reads the unprefixed key first, falls
   back to the prefixed one, and adopts the value unprefixed — without this, a migrating app
   would look unregistered and create a second device row for the same physical device. If
   your app runs both SDKs at once, note that only the Swift SDK follows the fallback;
   writes are never mirrored back to the prefixed key.
8. **Products are split three ways instead of pulling in every auth SDK.** The Flutter SDK
   depends on `firebase_auth` and `supabase_flutter` regardless of whether you use them. The
   Swift SDK splits `PushFireFirebaseAuth` and `PushFireSupabaseAuth` into separate SPM
   products from the core `PushFire` library, so a consumer using neither downloads neither
   dependency.
9. **A 2xx response whose body is not JSON is an error, not a success.** The Flutter client
   catches the decode failure and returns `{'success': true, 'raw_response': <body>}`, so a
   caller cannot tell a real result from an HTML gateway page that happened to arrive with a
   200. The Swift SDK throws `PushFireError.api` with the raw body attached in
   `responseBody`. This is the one place the SDKs deliberately disagree rather than
   converging: a response the SDK could not understand is not a result, and silently
   reporting success for one is how a broken deployment stays invisible. Endpoints that
   discard their response body are unaffected on both sides.
10. **Transport failures carry the system error's domain and code.** `PushFireError.network`
    has an `underlying: UnderlyingError?` holding `domain`, `code`, and `message`, so you can
    branch on `NSURLErrorNotConnectedToInternet` versus `NSURLErrorTimedOut` without matching
    a localized string. It is a snapshot rather than the error object because `any Error` is
    not `Sendable` and `PushFireError` crosses actor boundaries. The Flutter SDK keeps the
    original object in `originalError`; the Swift equivalent keeps what you can act on.

## License

MIT. See [LICENSE](LICENSE).
