# PushFire example app

A SwiftUI app exercising the whole public surface of the SDK. It doubles as the manual
test rig for behavior the unit tests cannot reach: a real APNs token, a real permission
prompt, a real settings round trip.

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
