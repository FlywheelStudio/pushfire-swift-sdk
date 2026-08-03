# PushFire example app

A minimal SwiftUI app exercising the SDK.

## Running it

1. Install XcodeGen and generate the project:

   ```bash
   brew install xcodegen
   cd Example && xcodegen generate
   ```

2. Add your own `GoogleService-Info.plist` to `Example/PushFireExample/`. It is not
   committed — Firebase configuration is per-project.

3. Set your PushFire API key in the scheme's environment as `PUSHFIRE_API_KEY`.

4. Run on a real device. Push tokens are not issued to the simulator, so device
   registration will not complete there.
