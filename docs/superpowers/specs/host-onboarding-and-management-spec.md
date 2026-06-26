# Host Onboarding and Management Spec

Status: Draft for review
Parent PRD: `docs/prd.md`
Related docs:

- `docs/architecture-design.md`
- `docs/data-model.md`
- `docs/implementation-plan.md`

## 1. Purpose

This spec defines how users add, generate, save, organize, edit, favorite, and delete hosts in wetrans.

It combines two implementation-plan milestones:

- M3: Host Management
- M4: SSH Config Host Generation

The feature slice ends when a host becomes a persisted `SavedHost` that can later be used by connection, browsing, and transfer features.

## 2. User Value

Users should be able to turn a server into a saved wetrans host without touching JSON files or retyping every SSH setting.

wetrans supports two onboarding paths:

- Manual Add: users enter host fields directly.
- Select from SSH Config: users choose an alias, wetrans runs `ssh -G`, and the resolved result becomes an editable host draft.

After saving, both paths produce the same kind of `SavedHost`.

## 3. Scope

### 3.1 In Scope

- Empty host sidebar state.
- Host sidebar groups:
  - Favorites
  - Recent
  - My Hosts
  - Connect Host
- Connect Host dialog.
- Manual host form.
- SSH Config alias selection.
- SSH Config alias scanning rules.
- `ssh -G <alias>` resolution.
- Generated host draft editing.
- SavedHost creation.
- SavedHost editing.
- SavedHost deletion.
- Favorite/unfavorite.
- Recent connection metadata through `HostCatalog.markConnected`.
- Last local path and last remote path metadata fields.
- Credential save/delete calls through the `CredentialStore` interface.
- Validation and user-facing errors for host onboarding.

### 3.2 Out of Scope

- Real SSH/SFTP connection.
- Host key verification.
- Remote directory browsing.
- Local file browsing.
- Upload or download.
- Transfer queue behavior.
- ProxyJump support.
- SSH Agent support.
- Complex ProxyCommand execution.
- Keyboard-interactive authentication.
- Refresh from SSH Config after a host has already been saved.

## 4. Product Decisions

### 4.1 SSH Config Generates Hosts

SSH Config is a creation source, not a runtime reference.

```text
Select alias
-> run ssh -G alias
-> create HostDraft
-> user confirms or edits
-> save SavedHost
```

After save, the host does not depend on SSH Config. `originSSHConfigAlias` and `resolvedAt` are metadata only.

### 4.2 Saved Hosts Use One Unified Model

Manual hosts and SSH Config-generated hosts both become `SavedHost`.

The app should not maintain separate runtime connection paths for manual hosts and generated hosts.

### 4.3 Credentials Are Never Stored in hosts.json

The host form may collect password or private key passphrase, but those values must be passed to `CredentialStore`.

`SavedHost` and `hosts.json` must not contain:

- SSH password
- Private key passphrase
- Token-like secret values

### 4.4 Sidebar Avoids Duplicate Rows

The same host should appear in only one sidebar group at a time, using this priority:

```text
Favorites -> Recent -> My Hosts
```

Rules:

- Favorite hosts appear in Favorites.
- Non-favorite hosts with `lastConnectedAt` appear in Recent.
- Non-favorite hosts without `lastConnectedAt` appear in My Hosts.
- `Connect Host` is always visible at the bottom.

This keeps the sidebar concise while preserving all host states.

## 5. User Interface

### 5.1 Empty State

When no hosts exist, the sidebar should show:

```text
My Hosts
  No hosts yet

+ Connect Host
```

The main area may show an empty-state message:

```text
Add a host to start browsing remote files.
```

### 5.2 Sidebar Host Row

Each host row should show:

- Display name.
- Optional secondary label, such as `username@hostname`.
- Favorite indicator if applicable.
- Context menu entry points.

Context menu actions:

- Edit Host
- Favorite or Unfavorite
- Delete Host

### 5.3 Connect Host Dialog

The first screen shows two choices at the top:

```text
Manual Add
Enter server address, username, port, and authentication.

Select from SSH Config
Choose an alias from ~/.ssh/config and generate a host.
```

The lower half of this first screen shows the saved-host management area from the current ardot prototype:

- Saved Hosts title and search field.
- Name-only saved-host list.
- Detail pane for the selected host.
- Edit, delete, save, and favorite/unfavorite actions.
- Explicit source text that SSH Config entries become saved hosts and are not runtime references.

Selecting either choice opens the corresponding form flow.

## 6. Manual Add Flow

### 6.1 Fields

| Field | Required | Notes |
| --- | --- | --- |
| Display name | Yes | Shown in sidebar |
| Host / IP | Yes | Saved as `hostname` |
| Port | No | Defaults to `22` |
| Username | Yes | Saved as `username` |
| Auth type | Yes | `password` or `sshKey` |
| Identity file | Conditional | Required when auth type is `sshKey` |
| Password | No | Stored through `CredentialStore` when provided; later connection flow may prompt if missing |
| Private key passphrase | No | Stored through `CredentialStore` when provided |
| Default remote path | No | Saved as `defaultRemotePath` |
| Note | No | Saved as `note` |

### 6.2 Actions

Primary action:

```text
Save Host
```

Future connection features may add:

```text
Save and Connect
```

This spec only requires saving the host. Connection behavior is handled by later specs.

### 6.3 Save Behavior

On save:

1. Validate fields.
2. Create `SavedHost`.
3. Save non-sensitive fields through `HostCatalog`.
4. Save password or passphrase through `CredentialStore`.
5. Add the host to the sidebar.
6. Select the saved host.

## 7. SSH Config Generation Flow

### 7.1 Alias Selection

When the user chooses Select from SSH Config:

1. wetrans calls `SSHConfigScanner.scanDefaultConfig()`.
2. The dialog shows searchable aliases.
3. The user selects one alias.
4. wetrans calls `SSHConfigResolver.resolve(alias:)`.
5. wetrans creates a `HostDraft`.
6. The user reviews or edits the draft.
7. The user saves it as a normal `SavedHost`.

### 7.2 Alias Display Rules

Show:

```text
Host dev
Host prod staging
```

Do not show:

```text
Host *
Host prod-*
Host ?
Host !bad *
```

MVP scanner behavior:

- Reads `~/.ssh/config`.
- Supports basic `Include`.
- Supports multiple aliases on one `Host` line.
- Filters wildcard aliases.
- Filters negated aliases.
- Ignores `Match` blocks for alias discovery.

### 7.3 Resolution Rules

Resolution uses:

```text
/usr/bin/ssh -G <alias>
```

Resolved fields may include:

- `hostname`
- `user`
- `port`
- `identityfile`
- `proxyjump`
- `proxycommand`

Supported fields map into `HostDraft`.

Unsupported options become visible warnings. They must not be silently executed by this flow.

### 7.4 Generated Draft Defaults

Given alias `dev`, the generated draft should default to:

```text
source: sshConfigGenerated
displayName: dev
hostname: resolved hostname
port: resolved port or 22
username: resolved user or current local username if resolver returns none
authType: sshKey if identityfile exists, otherwise password
identityFile: first resolved identityfile when present
originSSHConfigAlias: dev
resolvedAt: current date
```

The user may edit the generated draft before saving.

## 8. Edit Host Flow

Users can edit saved hosts from the sidebar context menu.

Editable fields:

- Display name
- Hostname
- Port
- Username
- Auth type
- Identity file
- Password
- Private key passphrase
- Default remote path
- Note
- Favorite state

Read-only metadata:

- Host ID
- Source
- Origin SSH Config alias
- Resolved at
- Last connected at

If the auth type changes:

- Changing from password to SSH key should delete the stored password unless the user cancels the save.
- Changing from SSH key to password should delete the stored key passphrase unless the user cancels the save.

## 9. Delete Host Flow

When deleting a host, show a confirmation:

```text
Delete "<displayName>"?

This removes the saved host from wetrans. It does not modify ~/.ssh/config.
```

On confirm:

1. Remove host from `HostCatalog`.
2. Delete credentials for the host through `CredentialStore`.
3. Remove runtime sidebar selection if the deleted host was selected.
4. Select the next available host if one exists.

Deleting a generated host must not modify SSH Config.

## 10. Recent and Favorite Behavior

### 10.1 Favorite

Favorite state is stored on `SavedHost.isFavorite`.

Rules:

- User can favorite any saved host.
- User can unfavorite any favorite host.
- Favorite state persists after app restart.

### 10.2 Recent

Recent state is derived from `SavedHost.lastConnectedAt`.

This spec does not perform real connections. It defines the input point:

```swift
HostCatalog.markConnected(hostId:at:)
```

When later connection features call this method:

- `lastConnectedAt` is updated.
- The host moves into Recent unless it is favorited.
- Recent hosts are sorted descending by `lastConnectedAt`.
- Recent list shows at most 10 hosts.

## 11. Data Changes

### 11.1 SavedHost

This feature creates and updates `SavedHost` records as defined in `docs/data-model.md`.

Required fields after save:

- `id`
- `source`
- `displayName`
- `hostname`
- `port`
- `username`
- `authType`
- `isFavorite`
- `favoriteRemotePaths`

Optional fields:

- `identityFile`
- `lastConnectedAt`
- `lastRemotePath`
- `lastLocalPath`
- `defaultRemotePath`
- `originSSHConfigAlias`
- `resolvedAt`
- `note`

### 11.2 CredentialStore Calls

Manual and generated host flows may call:

```swift
savePassword(_:hostId:)
saveKeyPassphrase(_:hostId:)
deleteCredentials(hostId:)
```

The concrete Keychain implementation belongs to the Credential and Host Key Security milestone, but this spec requires host onboarding code to use the `CredentialStore` interface rather than placing secrets in `SavedHost`.

## 12. Module Responsibilities

### 12.1 HostCatalog

Must support:

- Load hosts.
- Save host.
- Delete host.
- Set favorite.
- Mark connected.
- Update last paths.

### 12.2 SSHConfigScanner

Must support:

- Default config scanning.
- Basic Include expansion.
- Alias extraction.
- Wildcard filtering.
- Negation filtering.

### 12.3 SSHConfigResolver

Must support:

- Running `ssh -G`.
- Parsing resolved output.
- Mapping supported fields to `ResolvedSSHConfig`.
- Producing warnings for unsupported options.

### 12.4 Host Sidebar View Model

Must support:

- Grouping hosts by Favorites, Recent, and My Hosts.
- Selecting a host.
- Empty state.
- Context menu actions.
- Reacting to host catalog updates.

### 12.5 Connect Host Dialog View Model

Must support:

- Manual draft editing.
- SSH Config alias searching.
- Generated draft editing.
- Validation errors.
- Save action.
- Cancel action.

## 13. Validation

Validation rules:

- Display name must not be empty.
- Hostname must not be empty.
- Port must be between 1 and 65535.
- Username must not be empty.
- Identity file must be present when auth type is SSH key.
- Password must not be persisted in `SavedHost`.
- Private key passphrase must not be persisted in `SavedHost`.

For MVP, identity file path existence can be warned rather than blocking save, because the file may be on a removable or permission-gated path.

## 14. Error Handling

### 14.1 SSH Config Missing

Message:

```text
~/.ssh/config was not found. You can add a host manually.
```

Recovery:

- Show Manual Add action.

### 14.2 No Selectable Aliases

Message:

```text
No supported SSH Config hosts were found.
```

Recovery:

- Explain that wildcard and negated hosts are hidden.
- Show Manual Add action.

### 14.3 Alias Resolution Failed

Message:

```text
wetrans could not resolve this SSH Config host.
```

Recovery:

- Let user choose another alias.
- Let user switch to Manual Add.
- Show technical details on demand.

### 14.4 Unsupported SSH Options

Message:

```text
This host uses SSH options wetrans does not support yet.
```

Recovery:

- Show warnings on the generated draft.
- Allow save only when required connection fields are present.
- Do not execute unsupported `ProxyCommand`.

### 14.5 Save Failed

Message:

```text
wetrans could not save this host.
```

Recovery:

- Keep the form open.
- Preserve entered values.
- Show technical details on demand.

## 15. Acceptance Criteria

### 15.1 Manual Host

- User can open Connect Host and choose Manual Add.
- User can enter required fields.
- User can save a manual host.
- Saved manual host appears in My Hosts.
- Saved manual host persists after app restart.
- Password and passphrase do not appear in `hosts.json`.

### 15.2 SSH Config Generated Host

- User can open Connect Host and choose Select from SSH Config.
- Supported aliases are listed.
- Unsupported wildcard and negated aliases are hidden.
- User can select an alias.
- wetrans runs `ssh -G <alias>`.
- Resolved fields populate an editable host draft.
- User can save the generated host.
- Generated host appears as a normal saved host.
- Generated host persists without relying on future SSH Config reads.

### 15.3 Sidebar Management

- Favorites, Recent, and My Hosts groups render correctly.
- A host appears in only one group by priority: Favorites, then Recent, then My Hosts.
- User can favorite and unfavorite a host.
- User can edit a host.
- User can delete a host.
- Deleting a generated host does not modify SSH Config.
- Deleting a host calls credential cleanup.

### 15.4 Metadata

- `originSSHConfigAlias` is saved for generated hosts.
- `resolvedAt` is saved for generated hosts.
- `lastConnectedAt` can be updated through `markConnected`.
- `lastLocalPath` and `lastRemotePath` can be updated through host catalog path updates.

## 16. Test Scenarios

### 16.1 Unit Tests

- Manual host validation passes with required fields.
- Manual host validation fails with empty display name.
- Manual host validation fails with invalid port.
- SSH key host validation fails without identity file.
- Password and passphrase are not encoded into `SavedHost`.
- Host sidebar groups by priority.
- Recent group sorts by `lastConnectedAt` descending.
- Recent group limits to 10 hosts.
- Deleting a host calls `CredentialStore.deleteCredentials`.

### 16.2 SSH Config Scanner Tests

Fixture input:

```text
Host dev
  HostName dev.example.com

Host prod staging
  HostName prod.example.com

Host *
  User ubuntu

Host prod-*
  User deploy

Host !bad *
  User blocked
```

Expected selectable aliases:

```text
dev
prod
staging
```

### 16.3 Resolver Tests

Given `ssh -G dev` output:

```text
hostname dev.example.com
user ubuntu
port 22
identityfile ~/.ssh/id_ed25519
```

Expected draft:

```text
displayName: dev
hostname: dev.example.com
username: ubuntu
port: 22
authType: sshKey
identityFile: ~/.ssh/id_ed25519
originSSHConfigAlias: dev
```

### 16.4 UI Smoke Tests

- Empty sidebar shows Connect Host.
- Manual Add form can save a host.
- SSH Config flow can show aliases from fixture data.
- Generated draft can be edited before save.
- Favorite action moves host to Favorites.
- Delete action removes host from sidebar.

## 17. Implementation Notes

- Use fake `CredentialStore` in host onboarding tests until the Keychain implementation is built.
- Use fixture-based `SSHConfigScanner` and `SSHConfigResolver` adapters in tests.
- Keep `HostDraft` separate from `SavedHost`.
- Do not start a real SFTP connection from this feature.
- Do not write to or modify `~/.ssh/config`.
- Do not write to or modify OpenSSH `known_hosts`.
