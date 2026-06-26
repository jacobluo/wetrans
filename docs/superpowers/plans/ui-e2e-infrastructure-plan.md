# UI E2E Infrastructure Plan

> **Scope:** Add a committed macOS UI E2E harness for the SwiftPM app bundle, then expose stable accessibility selectors for host onboarding and transfer flows.

## Task 1: Add E2E Runner Product

- [x] Add a SwiftPM executable product named `wetrans-e2e`.
- [x] Implement a native macOS Accessibility runner that can smoke-test the launched app.
- [x] Keep full credential-dependent scenarios gated by environment variables.

## Task 2: Add Stable UI Selectors

- [x] Add accessibility identifiers for connect-host choices, manual fields, SSH Config alias search/select/save, host rows, file rows, panel buttons, queue controls, and host-key trust buttons.
- [x] Fix host-key trust alert dismissal so trusting does not clear the pending key before the action runs.

## Task 3: Wire Verification

- [x] Replace `scripts/e2e` with a real packaged-app + UI runner smoke check.
- [x] Document the environment variables printed by the runner for manual full-flow E2E.
- [x] Run focused build/tests, `scripts/e2e`, and `scripts/verify`.
