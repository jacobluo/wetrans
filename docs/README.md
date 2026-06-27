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

- `real-host-sftp-smoke.md`
  - Real-host SFTP E2E guide.
  - Documents the non-secret fixture format, secret handling, and the default connect/list/upload/download verification path.

## Superpowers Specs

Focused feature specs live under:

```text
docs/superpowers/specs/
```

These specs are narrower than the project-level PRD. They should describe one implementable feature slice, including user flow, UI states, module interactions, errors, and acceptance criteria.

Current focused specs include:

- `docs/superpowers/specs/host-onboarding-and-management-spec.md`
- `docs/superpowers/specs/credential-and-host-key-security-spec.md`
- `docs/superpowers/specs/file-browsing-spec.md`
- `docs/superpowers/specs/transfer-queue-spec.md`
- `docs/superpowers/specs/directory-transfers-spec.md`
- `docs/superpowers/specs/e2e-default-path-spec.md`

Implementation plans live under:

```text
docs/superpowers/plans/
```

## Verification

Default verification is driven by repository scripts:

```bash
scripts/verify
```

The E2E layer is available directly:

```bash
scripts/e2e
```

`scripts/e2e` starts a temporary local Docker OpenSSH fixture, runs SFTP connect/list/upload/download checks through libssh2, then performs packaged app build/run smoke through the native Accessibility runner. External SFTP hosts are opt-in through `WETRANS_SFTP_INTEGRATION_FILE`; full UI scenarios remain opt-in through `WETRANS_E2E_RUN_FULL=1`.

## Current Decisions

- wetrans is macOS native only.
- Stack is SwiftUI + AppKit.
- SSH Config generates saved hosts; it is not a runtime reference.
- P0 does not support ProxyJump, SSH Agent, complex ProxyCommand, or keyboard-interactive auth.
- MVP supports multi-file and directory upload/download with bounded concurrency.
- Default transfer limits are 3 global running tasks and 2 running tasks per host.
- Secrets live in Keychain, not JSON.
