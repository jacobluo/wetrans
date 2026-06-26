# wetrans Agent Guide

This repository uses project-level documentation paths instead of skill-default documentation paths.

## Documentation Layout

- `docs/2026-06-26-wetrans-prd.md`
  - Product requirements document for wetrans.
  - Product scope, user flows, MVP/P1/P2 scope, data model, acceptance criteria.

- `docs/2026-06-26-wetrans-architecture-design.md`
  - Architecture design document.
  - Technical stack, module interfaces, data flow, persistence, SSH/SFTP choices, security model, testing approach.
  - Create this file when architecture design is finalized.

- `docs/2026-06-26-wetrans-implementation-plan.md`
  - Implementation plan.
  - Milestones, task breakdown, test strategy, verification steps.
  - Create this only after the architecture design is reviewed.

## Directory Rules

- Put project documents directly under `docs/`.
- Do not put canonical project documents under `docs/superpowers/specs/`.
- Use `docs/superpowers/specs/` only for temporary skill-generated drafts if a workflow absolutely requires it, then move reviewed documents into `docs/`.
- Keep document filenames date-prefixed and descriptive:

```text
YYYY-MM-DD-wetrans-<topic>.md
```

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
