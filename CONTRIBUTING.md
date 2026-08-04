# Contributing

## Branches and pull requests

The base branch is `dev`. Open pull requests against `dev`, not `main`. `main` only
receives merges from `dev`.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`,
`test:`, `chore:`, etc.). No emoji, in commit messages, PR descriptions, or code comments.
Keep the summary line concise and focused on why the change was made.

## Formatting

The project is formatted with `swift-format`, configured in `.swift-format` (100-column
lines, 4-space indentation). Before committing:

```bash
xcrun swift-format lint --recursive --strict Sources Tests Example/PushFireExample
```

A clean run produces no output. Fix any reported violations before opening a pull request.

## Building and testing

Build the core library:

```bash
xcodebuild build -scheme PushFire -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Run the full test suite:

```bash
xcodebuild test -scheme PushFire-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Use `PushFire-Package`, not `PushFire`, to run tests. The per-product `PushFire` scheme is
library-only and has no test action — `xcodebuild test` against it fails immediately.
`PushFire-Package` is the scheme that runs every test bundle (`PushFireTests`,
`PushFireFirebaseAuthTests` and `PushFireSupabaseAuthTests`).

Do not pass `-only-testing` to filter tests. It silently matches nothing here and reports
`Executed 0 tests` alongside `** TEST SUCCEEDED **`, which reads as a pass. The line that
actually proves a run is `✔ Test run with N tests` — one per bundle.

The destination's device name depends on what simulators are installed on your machine.
Substitute whichever iPhone simulator you have; run `xcrun simctl list devices available`
to see them.

### Suites that touch `PushFire`

`PushFire` is a process-wide singleton. `.serialized` orders tests within a single suite,
not across sibling suites, so two top-level suites that each call `configure` and
`shutdown` will run in parallel and tear each other's instance down. Any suite touching
`PushFire.configure`, `.shared` or `.shutdown` must be nested inside `PushFireFacadeTests`
so the parent's `.serialized` trait covers it. Suites that drive `PushFireCore` directly
are unaffected.

### Deliberately uncovered code

Coverage is measured with:

```bash
xcodebuild test -scheme PushFire-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES -resultBundlePath cov.xcresult
xcrun xccov view --report --only-targets cov.xcresult
```

Some files sit at low coverage on purpose. Raising them would mean adding indirection to
production code purely to satisfy a number, which costs more than it protects:

- `Platform/Live/*` — thin adapters over `UNUserNotificationCenter`, `FirebaseMessaging`,
  `UIApplication` and `NotificationCenter`. Every `Platform/` protocol has a fake, and the
  logic that uses these adapters is fully covered through those fakes. The adapters
  themselves hold no branching worth testing and cannot run without the real OS services.
- `API/HTTPTransport.swift` — `URLSessionTransport` needs a live network. `APIClient` is
  tested against the `HTTPTransport` protocol via `FakeTransport`, which is the seam that
  exists for exactly this reason.
- `Logging/PushFireLogger.swift` — writes straight to `os.Logger`, which has no injectable
  sink. Asserting on it would require either an `OSLogStore` read (entitlement-dependent
  and flaky) or a logging protocol threaded through every service. Its behaviour is a
  guard on `enabled` and string interpolation.
- `PushFire.configure` and `PushFireCore.live` — the live wiring path builds a real
  `URLSession` and Firebase-backed token provider. Tests install a core built from fakes
  through `configureForTesting(core:)`, covering everything downstream.
- `FirebaseAuthProvider.events` and `SupabaseAuthProvider.events` — the `AsyncStream`
  wiring needs a real `Auth.auth()` or `SupabaseClient`. Both providers deliberately
  extract their identity mapping into a pure static `authEvent(...)` so the part that can
  be wrong is tested directly.

When adding code to any of these files, keep the logic in the tested layer and the
untested file a pass-through.

## Example app

`Example/PushFireExample.xcodeproj` is generated from `Example/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd Example && xcodegen generate
```

Set `PUSHFIRE_API_KEY` in the scheme's environment variables (or export it before building)
to test against a real project.

The example reaches every public call on the facade — most behind a button, the read-only
ones as rows refreshed after each action — and reports what each call returned or how it
failed. The `authProvider:`/`pushTokenProvider:` parameters of `configure` are out of
scope: the example links only the `PushFire` product, so neither auth product is in the
binary. That is deliberate — it is the manual test rig for behavior the
unit tests cannot reach (a real APNs token, a real permission prompt, a real settings
round trip), and it is where an integrator looks to see how a call is meant to be used. When
you add a public API, add it here too.

## Scope

Keep pull requests focused on one change. Do not bundle unrelated refactors, dependency
bumps, or formatting-only changes with a feature or fix unless asked to.
