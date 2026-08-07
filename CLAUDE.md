# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MalatangLog（麻辣湯ログ）is a native iOS app (SwiftUI + SwiftData, no external dependencies, no SPM packages) for logging visits to malatang (麻辣湯) shops: what you ordered, photos, ratings, spice/numbing level, and nearby-shop discovery via MapKit. Everything is stored on-device only — no accounts, no backend, no analytics/ad SDKs. See `README.md` for the full product spec summary and `Docs/REMOTE_DEVELOPMENT.md` for the self-hosted TestFlight CI.

## Commands

There is no SPM/CocoaPods dependency step — open `MalatangLog.xcodeproj` in Xcode 16+ (iOS 17.0 deployment target, Swift 5 mode) and it builds directly.

### Build / run
- Xcode GUI: open the project, ⌘R (simulator or a signed device).
- CLI build (Release, generic iOS destination — used by CI, not for iterating in a simulator):
  ```bash
  xcodebuild -project MalatangLog.xcodeproj -scheme MalatangLog -configuration Release \
    -destination "generic/platform=iOS" clean build
  ```

### Tests
- Xcode GUI: ⌘U.
- CLI, all tests:
  ```bash
  xcodebuild -project MalatangLog.xcodeproj -scheme MalatangLog \
    -destination "platform=iOS Simulator,name=iPhone 16" test
  ```
- CLI, a single test class or method (`-only-testing`):
  ```bash
  xcodebuild -project MalatangLog.xcodeproj -scheme MalatangLog \
    -destination "platform=iOS Simulator,name=iPhone 16" \
    -only-testing:MalatangLogTests/MasterServiceTests test
  ```
- Test files map to specific invariants — check the table in `README.md` §3 before changing behavior in `Data/`, `Purchase/`, or `MapKitSupport/`, since each test file pins a specific edge case (e.g. `MasterServiceTests` guards ID stability across renames, `BackupServiceTests` guards duplicate-skip-on-reimport).

### Local CI pipeline (`Scripts/`)
This repo drives its own build → archive → TestFlight upload from a LaunchAgent on a home Mac; there is no hosted CI. Relevant when touching `Scripts/` or diagnosing a failed automated release:
- `Scripts/build.sh` — git sync + Release build
- `Scripts/archive.sh` — archive + IPA export
- `Scripts/upload.sh` — altool validate + upload
- `Scripts/pipeline.sh` — runs the three above under a lock, notifies on success/failure
- `Scripts/check-for-updates.sh` — polls `origin/main`, triggers `pipeline.sh` on new commits
- All scripts source `Scripts/lib/common.sh`, which refuses to proceed if the working tree has uncommitted changes or has diverged from `origin/main` (no silent reset/overwrite).
- Local secrets (`ASC_KEY_ID`/`.p8`) live outside the repo at `~/Library/Application Support/MalatangLogCI/`, never in git.
- `SKIP_GIT_SYNC=true ./Scripts/build.sh` builds without touching git — useful for a dry-run build check.

## Architecture

### Persistence
SwiftData with an explicit versioned schema (`Models/AppSchema.swift`): `MalatangSchemaV1` lists the five persistent models (`Serving`, `Store`, `Ingredient`, `Noodle`, `Soup`), and `MalatangMigrationPlan` is the (currently empty) migration stage list — add new `MigrationStage`s here when the schema changes, don't just edit the models in place. `AppModelContainer.make()` throws instead of silently falling back to an in-memory store; `MalatangLogApp.swift` catches that failure and shows `DataUnavailableView` rather than losing data invisibly. This "never silently lose data" posture also shows up as:
- Master data (`Ingredient`/`Noodle`/`Soup`) is never physically deleted — only hidden — so renaming or hiding an item never breaks a past `Serving` that references it (IDs are stable across renames).
- Backups (`Data/BackupService.swift`, `.malaarchive` files) are a `FileWrapper` serialization (photos + data in one file, no zip dependency), support additive-merge or full-replace with a two-step confirmation, and skip duplicate IDs on reimport.

### Module layout (`MalatangLog/`)
- `Models/` — SwiftData entities + the schema/migration plan above.
- `Data/` — master-data seeding/dedup (`MasterService`, `SeedMaster`), "frequently used ingredients" ranking (`FrequentIngredients`), photo storage, backup/restore, sample data.
- `Design/` — theme (4 color themes × light/dark via `AppearanceSettings`), typography, shared components (tags, spice/numbing indicators, star ratings, steam effect).
- `MapKitSupport/` — location, nearby-shop search, and building external Google/Apple Maps URLs (falls back to name-search when a shop has no coordinates).
- `Purchase/` — StoreKit 2, non-consumable "unlimited" unlock. `StoreAccessPolicy.requiresUnlock` is the gate: free tier is a fixed number of *distinct visited shops* (`PurchaseConfiguration.freeStoreLimit`), not a count of servings — revisiting an already-visited shop or logging a serving with no shop selected never consumes free-tier quota.
- `Features/` — one folder per tab/screen area: `Home`, `Map`, `Album`, `Analytics`, `Catalog` (shop/serving detail, search), `Record` (the entry editor), `Settings`, `Purchase`.
- `RootView.swift` — the 4-tab `TabView` (home/map/album/analytics); seeds master data and sample data via `.task` on first appearance. Accepts `--preview-tab=<name>` as a launch argument to open on a specific tab (used by UI testing/screenshots).

### Design decisions worth knowing before changing related code
- Duplicating a serving ("この一杯をもう一度") resets photos and rating — a repeat order is a new bowl, not a clone of the old photo/rating.
- Analytics (`AnalyticsView`) suppresses charts when fewer than 3 data points exist, and excludes unset prices from average-price calculations rather than treating them as zero.
- Initial master data intentionally collapses several duplicate/alias ingredient names (e.g. 湯葉/腐竹, 米粉/米線) into one canonical display name with the rest folded in as searchable aliases — see README §5 for the specific merges if you touch `SeedMaster.swift`.
