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
xcrun swift-format lint --recursive --strict Sources Tests
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
`PushFire-Package` is the scheme that runs every test bundle (`PushFireTests` and
`PushFireSupabaseAuthTests`).

The destination's device name depends on what simulators are installed on your machine.
Substitute whichever iPhone simulator you have; run `xcrun simctl list devices available`
to see them.

## Example app

`Example/PushFireExample.xcodeproj` is generated from `Example/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd Example && xcodegen generate
```

Set `PUSHFIRE_API_KEY` in the scheme's environment variables (or export it before building)
to test against a real project.

## Scope

Keep pull requests focused on one change. Do not bundle unrelated refactors, dependency
bumps, or formatting-only changes with a feature or fix unless asked to.
