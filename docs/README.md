# wetrans Docs

This directory contains the project-level product and engineering documents for wetrans.

## Canonical Documents

- `prd.md`
  - Product baseline for the MVP.
  - Defines user value, feature scope, product decisions, and acceptance criteria.

- `architecture-design.md`
  - Architecture baseline for the MVP.
  - Defines macOS stack, modules, data flow, concurrency model, error model, and testing strategy.

- `technical-selection.md`
  - Technical selection baseline.
  - Records stack choices and library evaluation direction, especially libssh2 vs libssh.

- `data-model.md`
  - Data model baseline.
  - Defines persisted JSON schemas, Keychain records, trusted host keys, transfer history, and runtime-only state.

- `implementation-plan.md`
  - Canonical overall implementation plan.
  - Defines milestone order and which milestones need focused Superpowers specs.

## Superpowers Specs

Focused feature specs live under:

```text
docs/superpowers/specs/
```

These specs are narrower than the project-level PRD. They should describe one implementable feature slice, including user flow, UI states, module interactions, errors, and acceptance criteria.

Planned focused specs:

- `docs/superpowers/specs/host-onboarding-and-management-spec.md`
- `docs/superpowers/specs/credential-and-host-key-spec.md`
- `docs/superpowers/specs/file-browsing-spec.md`
- `docs/superpowers/specs/transfer-queue-spec.md`

## Current Decisions

- wetrans is macOS native only.
- Stack is SwiftUI + AppKit.
- SSH Config generates saved hosts; it is not a runtime reference.
- P0 does not support ProxyJump, SSH Agent, complex ProxyCommand, or keyboard-interactive auth.
- MVP supports multi-file upload/download with bounded concurrency.
- Default transfer limits are 3 global running tasks and 2 running tasks per host.
- Secrets live in Keychain, not JSON.
