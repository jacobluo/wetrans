# wetrans Agent Guide

This repository keeps Superpowers workflow specs in the Superpowers specs directory and keeps long-lived project design documents directly under `docs/`.

## Documentation Layout

- `docs/superpowers/specs/2026-06-26-wetrans-prd.md`
  - Superpowers brainstorming spec for the wetrans PRD.
  - Product scope, user flows, MVP/P1/P2 scope, data model, acceptance criteria.

- `docs/architecture-design.md`
  - Architecture design document.
  - Technical stack, module interfaces, data flow, persistence, SSH/SFTP choices, security model, testing approach.
  - Create this file when architecture design is finalized.

- `docs/technical-selection.md`
  - Technical selection document, if needed separately from architecture.
  - Compare concrete choices such as libssh2 vs libssh, Swift Package layout, persistence format, and distribution approach.

- `docs/data-model.md`
  - Data model design, if it grows beyond the PRD and architecture document.
  - Define persisted JSON schemas, Keychain keys, trusted host key records, transfer summaries, and migration rules.

- `docs/implementation-plan.md`
  - Implementation plan.
  - Milestones, task breakdown, test strategy, verification steps.
  - Create this only after the architecture design is reviewed.
  - This is the canonical implementation plan location. Do not create a root-level `PLAN.md` unless the user explicitly asks for a temporary scratch checklist.

## Directory Rules

- Put Superpowers workflow specs under `docs/superpowers/specs/`.
- Put project design documents directly under `docs/`, including architecture design, technical selection, data model, and overall planning documents.
- Do not move Superpowers specs out of `docs/superpowers/specs/` unless the user explicitly asks for a different location.
- Use `docs/implementation-plan.md` for the canonical implementation plan. Avoid root-level `PLAN.md` for project planning.
- Use stable, descriptive filenames for project documents directly under `docs/`; do not date-prefix those files:

```text
docs/<topic>.md
```

- Superpowers specs may keep the workflow-generated date-prefixed names under `docs/superpowers/specs/`.

## Current Product Decisions

- Product name: wetrans.
- wetrans is a native macOS SSH/SFTP remote file manager.
- SSH Config is a host generation source, not a runtime reference.
- Hosts generated from SSH Config are persisted as normal saved hosts.
- Normal host metadata is stored locally.
- Passwords and private key passphrases are stored in macOS Keychain.
- The MVP uses a three-pane file manager layout and a global transfer queue.

## Architecture Discussion Focus

Before implementation, settle these choices in the architecture design:

- Native macOS stack decision: SwiftUI + AppKit unless explicitly changed.
- SFTP implementation choice and spike plan: libssh2 vs libssh.
- Module interfaces for host catalog, SSH config scanning, credential storage, remote file system, host session management, and transfer queue.
- Persistence layout for hosts, trusted host keys, transfer summaries, and runtime-only state.
- MVP SSH feature boundary and unsupported-option handling.
