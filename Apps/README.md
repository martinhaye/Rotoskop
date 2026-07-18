# Apps

iOS app shell (Implementation order step 5). **iPhone portrait only.**

## Open / run

```bash
open Apps/Rotoskop/Rotoskop.xcodeproj
```

**Physical phone** (connected + trusted, signing already set in Xcode):

```bash
Scripts/run-on-device.sh            # auto-pick first connected iPhone
Scripts/run-on-device.sh Martin      # by name or UDID
```

**Simulator:**

```bash
xcodebuild -project Apps/Rotoskop/Rotoskop.xcodeproj -scheme Rotoskop \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The app target depends on the local Swift package (`RotoskopGit`, `RotoskopUI`).
Derived data for device builds goes under `build/DerivedData-device/` (gitignored).

## What’s in v1 (step 5)

- **Projects** list: clone from GitHub HTTPS into app-managed storage; swipe to delete clone.
- **Settings**: GitHub PAT → Keychain.
- **Project shell** tabs: Files / Editor / Build / Run (stubs until steps 6–7).
- **Git** sheet: status, commit-all, branch create/switch, push/pull, clean-merge-only.

Shared logic lives in `Sources/RotoskopGit` and `Sources/RotoskopUI` (testable without the app target).
