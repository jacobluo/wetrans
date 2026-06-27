# UI Layout Polish Spec

## Context

After the latest PR merge, the main browser and saved-host editing surfaces need small layout fixes to better match the ardot MVP prototype and macOS desktop expectations.

## Requirements

- Saved-host inline editor Cancel and Save buttons must use the same visible button sizing as neighboring saved-host actions.
- Local and Remote path fields in the main browser must get more horizontal room.
- File panel toolbar actions must be compact icon buttons in this order: go up, refresh, upload/download.
- Toolbar icon buttons must keep hover help text and correct SF Symbols for their action.
- The transfer queue area must be vertically resizable by dragging between file panels and the queue.
- Local and Remote file listings must support horizontal scrolling for wide rows.

## Non-Goals

- No redesign of the ardot prototype.
- No changes to SFTP behavior, transfer queue scheduling, credential storage, or host persistence.
- No new committed macOS UI automation target.

## Verification

- Add focused tests for exposed layout contracts where SwiftUI view introspection is not available.
- Run focused UI tests first, then the repository verification script before handoff.
