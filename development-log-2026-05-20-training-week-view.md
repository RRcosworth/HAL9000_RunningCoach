# Development Log - 2026-05-20 - Training Week View

## Summary

Implemented the Training week view follow-up requested on 2026-05-20.

## Changes

- Training history rows can now open the workout detail screen when they map to an Apple Health workout UUID.
- Training reuses the existing workout detail implementation, including route map, key metrics, heart rate chart, splits, and workout sharing.
- Weekly progress now merges backend `/api/weekly` data with local Apple Health running workouts for the current Monday-to-today week.
- If the backend weekly request fails but Apple Health has current-week runs, Training shows local history/progress instead of blocking on the network error.
- Added a HealthKit summary fetch API for current-week running workouts.

## Notes

- `training-week-view-development-spec.md` was not present in the repository or nearby local Codex/Hermes paths during implementation, so this pass follows the user-facing requirements from the request directly.
- The 5.2 km local run should now be reflected in weekly progress as long as Apple Health exposes it to the app.

## Verification

- `xcodebuild -project HAL9000.xcodeproj -scheme HAL9000 -destination 'id=D8F5F63F-76BF-5E5F-B6F1-9A35CFEF5EBD' build`

## Follow-up: Cache, Week View, Selective Export

Implemented the 3-part Training upgrade requested after the first pass.

- `CacheStore` now persists cache entries to disk under Application Support, while keeping the existing in-memory fast path.
- Training reads disk cache on cold start and can show expired cache with a visible stale-data notice while refreshing in the background.
- Weekly cache TTL is now 24 hours.
- Training plan layout now renders a Monday-to-Sunday `TrainingWeekDay` view with rest-day cards.
- Export is now a sheet-driven multi-select flow. The user selects planned running sessions before syncing to Apple Watch or generating Garmin TCX.

Verification:

- `xcodebuild -project HAL9000.xcodeproj -scheme HAL9000 -destination 'id=D8F5F63F-76BF-5E5F-B6F1-9A35CFEF5EBD' build`

## Follow-up: Today and Training Review Fixes

Fixed the review findings from the Today/Training pass.

- Training week days now support multiple sessions on the same date instead of silently showing only the first workout.
- Cached Training data is rebuilt after local Apple Health merge, so cold-start week cards reflect the newest local run data.
- Manual refresh no longer deletes the disk cache before the network request, preserving stale-cache fallback when `/api/weekly` fails.
- Garmin TCX export state is reset when the export selection changes, preventing an old generated file from being shared after changing checkboxes.
- Export eligibility now uses the training type string directly, so unknown workout types are not treated as running just because the fallback icon is `figure.run`.
- Today supplemental HealthKit queries now write back only to the snapshot that started them, preventing slower background metric loads from overwriting newer refreshes.

Verification:

- `xcodebuild -project HAL9000.xcodeproj -scheme HAL9000 -destination 'id=D8F5F63F-76BF-5E5F-B6F1-9A35CFEF5EBD' build`
- `xcodebuild test -project HAL9000.xcodeproj -scheme HAL9000 -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- `xcrun devicectl device install app --device D8F5F63F-76BF-5E5F-B6F1-9A35CFEF5EBD /Users/songh/Library/Developer/Xcode/DerivedData/HAL9000-crdijpbpspuebffhvdefclxbkdjw/Build/Products/Debug-iphoneos/HAL9000.app`
