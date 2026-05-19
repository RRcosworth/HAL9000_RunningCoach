# Hermes AI Coach iOS Integration - Development Log

## Date
2026-05-19

## Completed Scope
- [x] Phase 1 iOS Coach tab MVP
- [x] Phase 1 Hermes Gateway mock/real route
- [x] Context injection from HealthKit-derived training data
- [x] Native Markdown rendering for paragraphs, lists, code blocks, and tables
- [x] Local chat history persistence
- [x] Unit tests for Markdown parsing and plan patch conversion

## Key Architecture Decisions
1. The Coach tab uses the existing `APIClient` and `UserSessionStore` base URL so Profile remains the single backend configuration surface.
2. Chat history is stored in UserDefaults for the MVP because the existing `CacheStore` is memory-only and cannot restore cold-start history.
3. The Gateway is a thin Flask adapter in `HermesGateway/coach_gateway.py`; it owns prompt assembly, rate limiting, mock mode, and the `hermes ask --skill running-knowledge-base` call, but no coaching logic.
4. Plan sync is represented by `CoachPlanSyncService` and tested, but automatic mutation of the Training tab remains a Phase 2 integration step.

## Issues And Solutions
1. Issue: The project had no backend files in the iOS repo.
   Solution: Added a small standalone Gateway folder that can run next to the iOS project without affecting Xcode builds.
2. Issue: Markdown rendering should not use WebView.
   Solution: Added a lightweight SwiftUI parser/renderer for common Hermes response blocks.
3. Issue: Training context can be incomplete when HealthKit data is missing.
   Solution: `CoachContextCollector` sends nullable fields and keeps chat usable even with partial health data.

## Test Results
- [x] `xcodebuild test` passes
- [x] Coach Markdown parser test passes
- [x] Coach plan patch conversion test passes

## Known Limits
1. Responses are non-streaming.
2. The app sends requests to the configured backend; Gateway must be running separately.
3. Generated `plan_patch` is parsed into sessions but is not yet automatically applied to the visible Training tab.

## Next Steps
1. Add end-to-end mock integration using `/api/coach/chat?mock=true`.
2. Wire accepted `plan_patch` into Training state after a confirmation UI.
3. Add a Training-session-to-Coach handoff action.
