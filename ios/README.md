# Shot Tracker — iOS

Native Swift/SwiftUI port of the PWA. Designed to build on GitHub Actions so this entire project can be developed from Windows without a Mac.

## Repo layout

```
ios/
├── project.yml                     # XcodeGen config — source of truth for the Xcode project
├── ShotTracker/
│   ├── ShotTrackerApp.swift        # @main App entry
│   ├── Views/ContentView.swift
│   ├── Camera/CameraManager.swift  # AVCaptureSession wrapper
│   ├── Camera/CameraPreview.swift  # SwiftUI UIViewRepresentable of AVCaptureVideoPreviewLayer
│   ├── Model/GameSession.swift     # @Observable session state
│   └── Assets.xcassets/            # AppIcon auto-generated from ../icons/icon.svg at build
└── ShotTrackerTests/               # XCTest target
```

The `.xcodeproj` is **not** committed — it's generated from `project.yml` by `xcodegen` on every build. Edit YAML, not project.pbxproj.

## Current status — Phase 0 (scaffolding)

- [x] Camera preview fullscreen, portrait lock
- [x] Camera permission request + denied-state UX
- [x] GameSession model (shots/makes/misses) — no classifier yet
- [x] Unit test target + 3 smoke tests on GameSession
- [x] GitHub Actions: build + test on every push
- [x] GitHub Actions: archive + upload to TestFlight on manual dispatch

**What it does right now:** opens the camera and shows a live fullscreen preview with a "Camera ready" pill. Nothing else. This is intentional — Phase 0 validates the full pipeline from Windows commit → GitHub Actions build → TestFlight on your phone before any real code is written.

## Roadmap

From `IOS_PORT.md` §16, with actual status:

| Phase | Scope | Status |
|---|---|---|
| 0 | Camera preview, no detection | **Done** |
| 1 | Detection pipeline (YOLOv8n CoreML, color fallback, rim disruption) | Not started |
| 2 | Shot classifier port + unit tests | Not started |
| 3 | UI polish (glass bars, stats, tap zones, summary, haptics) | Not started |
| 4 | Custom-trained model on your footage | Not started |
| 5 | Public TestFlight | N/A — private TestFlight from Phase 0 onward |

---

## One-time Apple setup (~60 minutes)

You need this done once before the `testflight` job can upload. The unsigned `build` job runs without any of this.

### 1. App Store Connect — register the app

1. Log in to <https://appstoreconnect.apple.com>
2. **Users and Access → Integrations → App Store Connect API** → Generate a team API key (role: **App Manager**).
   - Download the `.p8` file (you can only download once).
   - Note the **Key ID** and **Issuer ID** shown on that page.
3. **Apps → +** → New App:
   - Platform: iOS
   - Name: `Shot Tracker` (or any unused name)
   - Bundle ID: create new → `com.lorenzoleo.shottracker` (must match `project.yml`)
   - SKU: `shottracker-001` or similar (internal, any value)

### 2. Apple Developer Portal — certificate + identifier

1. <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**
2. **Identifiers → +** → App IDs → App → Continue
   - Description: Shot Tracker
   - Bundle ID (explicit): `com.lorenzoleo.shottracker`
   - Capabilities: leave defaults (no special entitlements for camera)
3. **Certificates → +** → Apple Distribution → Continue
   - You need a CSR (Certificate Signing Request). Since you're on Windows, use this one-time workaround on a cloud Mac OR:
     - Install **OpenSSL for Windows** and run:
       ```
       openssl req -new -newkey rsa:2048 -nodes -keyout key.pem \
         -out request.csr \
         -subj "/emailAddress=lorenzoleollamas@gmail.com/CN=Lorenzo/C=US"
       ```
     - Upload `request.csr`, download the issued `.cer`
     - Convert to P12 (what we need for CI):
       ```
       openssl x509 -inform DER -outform PEM -in distribution.cer -out distribution.pem
       openssl pkcs12 -export -inkey key.pem -in distribution.pem \
         -out distribution.p12 -password pass:CHOOSE_A_PASSWORD
       ```
   - Keep `distribution.p12` and the password.
4. **Your Team ID** is shown at top-right of the developer portal (10-char alphanumeric).

> Provisioning profile is downloaded automatically by the GitHub Action — you don't need to create one by hand.

### 3. GitHub secrets

Repo → **Settings → Environments → New environment → `testflight`** → add these secrets:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Your 10-char Team ID |
| `BUILD_CERTIFICATE_BASE64` | `base64 -w 0 distribution.p12` — the whole P12 as base64 |
| `P12_PASSWORD` | The password you chose when exporting the P12 |
| `APPSTORE_ISSUER_ID` | From App Store Connect API page |
| `APPSTORE_KEY_ID` | From App Store Connect API page |
| `APPSTORE_PRIVATE_KEY` | Contents of the `.p8` file, including `-----BEGIN/END PRIVATE KEY-----` lines |

On Windows, to base64 a file for pasting:
```
certutil -encode distribution.p12 distribution.p12.b64
```
Then open the `.b64` file, delete the `-----BEGIN/END CERTIFICATE-----` header/footer lines, and paste the rest as the secret value.

### 4. TestFlight testers

App Store Connect → your app → **TestFlight → Internal Testing → New Group**. Add your Apple ID (same email as the developer account) as a tester.

Once a build is uploaded and passes processing (~5–15 min), TestFlight on your iPhone will prompt you to install it.

---

## How to ship a build

### Every push to `main`
- Automatically runs the `build` job: compile check + unit tests. No upload.

### When you want a TestFlight build
- Actions → **iOS Build** → **Run workflow** → set `deploy` to `true` → Run.
- Takes ~10–15 min. Watch the `testflight` job logs.
- When it succeeds, check App Store Connect → your app → TestFlight. Build appears in "Processing" first, then "Ready to Test".

### Build numbers
The `CURRENT_PROJECT_VERSION` is set to `github.run_number` on each TestFlight upload. Never decrements; each upload gets a fresh number automatically.

---

## Developing from Windows — pragmatic workflow

You cannot run the simulator or open Xcode. What you can do:

1. Edit Swift files in VS Code (install the Swift extension for syntax highlighting — it won't give you type checking without sourcekit-lsp, which is Mac-only).
2. Push to a branch. GitHub Actions compiles it — compile errors show up in the `build` job log within ~5 minutes.
3. Iterate on compile errors until green.
4. Dispatch the `testflight` job to get the binary on your phone.
5. Test on the phone — real device is the source of truth for anything camera-related.

Rough iteration cost per full cycle: **~15 minutes** (commit → TestFlight install prompt). Front-load as much logic as you can into **unit-testable code** (the shot classifier in Phase 2 is the biggest example) so most bugs are caught by the `build` job's `test` step without needing a TestFlight round-trip.

### Things you cannot do without a Mac
- Run the iOS Simulator
- Use Xcode Previews (`#Preview { ... }`)
- Step-debug with breakpoints (device debugging requires Xcode attached via USB)

### Workarounds for the above
- **Cloud Mac when really needed:** `mac-in-cloud` or `MacStadium` hourly rentals. Useful 1–2 times during Phase 1 to verify frame-rate and camera orientation visually. $2–5/hr.
- **Xcode Cloud:** Apple's own CI can also build, and it has a simulator recording feature. Considered and rejected for this project because GitHub Actions is free for public repos and doesn't require fiddling with another dashboard.

---

## Local development (if you ever get a Mac)

```
cd ios
brew install xcodegen
xcodegen generate
open ShotTracker.xcodeproj
```

Build & run on a connected iPhone (Cmd+R). For Xcode to sign a dev build:

- In Xcode → Project → ShotTracker target → Signing & Capabilities
- Check "Automatically manage signing", select your Team. Xcode handles the rest.

Do **not** commit the generated `ShotTracker.xcodeproj` — it's in `.gitignore`.

---

## Known next-steps / open questions captured in the plan

- **Phase 1:** port detection pipeline. Start with off-the-shelf YOLOv8n CoreML (drop the `.mlmodel` into `ShotTracker/` and wire a `VNCoreMLRequest`). See `IOS_PORT.md` §6.
- **Phase 2:** port `checkMake` / `classifyShotAttempt` from `index.html`. This is pure logic — unit tests first, then wire to live frames.
- **Training data for custom model (Phase 4):** needs 45° / 15–20ft / indoor+outdoor footage, labeled. Use `media/` contents + YouTube pulls.
