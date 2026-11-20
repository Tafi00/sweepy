# Resident App — Schema Sync & E2E Starter

Minimal workspace for preventing API schema drift between the backend, Web Admin Portal, and native iOS (`Codable` / Notification Service Extension) builds.

## Scope
- `openapi/schema.yaml`: Single source of truth for verified rental listing payloads.
- `ios/ListingModels.swift`: Resilient Swift `Codable` models handling timestamp & optional metadata edge cases.
- `e2e/listing-approval.spec.ts`: Playwright E2E tests for the admin approval flow.

## Run E2E Tests
```bash
npm install
npx playwright test
