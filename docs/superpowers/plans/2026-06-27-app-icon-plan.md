# App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add the provided pixel-style file migration image as the macOS app icon.

**Architecture:** Keep icon source assets under `assets/app-icon`. Generate a standard macOS `AppIcon.iconset` and `AppIcon.icns`; package scripts copy the `.icns` into app bundle resources and write `CFBundleIconFile` into `Info.plist`.

**Tech Stack:** Bash, macOS `sips`, `iconutil`, SwiftPM packaging scripts, macOS app bundle `Info.plist`.

---

### Task 1: Generate icon assets

**Files:**
- Existing source: `assets/app-icon/AppIcon.png`
- Create: `assets/app-icon/AppIcon.iconset/*`
- Create: `assets/app-icon/AppIcon.icns`

- [x] **Step 1: Verify source PNG**

Run: `sips -g pixelWidth -g pixelHeight assets/app-icon/AppIcon.png`
Expected: `1024 x 1024`.

- [x] **Step 2: Generate iconset sizes**

Use `sips` to generate 16, 32, 64, 128, 256, 512, and 1024 pixel PNG entries with macOS iconset names.

- [x] **Step 3: Generate icns**

Run: `iconutil -c icns assets/app-icon/AppIcon.iconset -o assets/app-icon/AppIcon.icns`.
Expected: `assets/app-icon/AppIcon.icns` exists.

### Task 2: Wire icon into app bundle scripts

**Files:**
- Modify: `scripts/build-and-run`
- Modify: `scripts/package`

- [x] **Step 1: Add icon resource variables**

Define `APP_RESOURCES` and `APP_ICON` in both scripts.

- [x] **Step 2: Copy icon into app bundle**

Create `Contents/Resources` and copy `assets/app-icon/AppIcon.icns` to `Contents/Resources/AppIcon.icns`.

- [x] **Step 3: Add Info.plist icon key**

Write `CFBundleIconFile` with value `AppIcon` in both generated `Info.plist` files.

### Task 3: Verify

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-app-icon-plan.md`

- [x] **Step 1: Run development bundle verify**

Run: `scripts/build-and-run --verify`.
Expected: app process starts and `dist/wetrans.app/Contents/Resources/AppIcon.icns` exists.

- [x] **Step 2: Check Info.plist**

Run: `/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/wetrans.app/Contents/Info.plist`.
Expected: `AppIcon`.

- [x] **Step 3: Run typecheck**

Run: `scripts/typecheck`.
Expected: PASS.

- [x] **Step 4: Mark this plan complete**

Update all checkboxes to `[x]` after verification.

## Execution Notes

- Source image verified as PNG 1024x1024 with no alpha.
- Generated `assets/app-icon/AppIcon.iconset/` and `assets/app-icon/AppIcon.icns` using `sips` and `iconutil`.
- `scripts/build-and-run --verify` passed and produced `dist/wetrans.app/Contents/Resources/AppIcon.icns`.
- `/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/wetrans.app/Contents/Info.plist` returned `AppIcon`.
- `WETRANS_PACKAGE_CONFIGURATION=debug scripts/package` passed and included the same icon resource.
- `scripts/typecheck` passed.
- `git diff --check` passed before marking this plan complete.
