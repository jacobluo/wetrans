# App Icon Spec

Status: Implemented

## Purpose

Add a first-party macOS app icon for wetrans so locally built and packaged app bundles no longer use the generic executable icon.

## Visual Direction

The icon uses a pixel-styled file migration metaphor: a soft macOS rounded-square tile, cloud/file center, and upload/download arrows. The style should stay crisp at small sizes while preserving the provided high-resolution source image as the design source of truth.

## Scope

- Keep the provided source PNG at `assets/app-icon/AppIcon.png`.
- Generate a macOS `.iconset` and final `AppIcon.icns` from the source PNG.
- Copy `AppIcon.icns` into `Contents/Resources` for both development and package scripts.
- Add `CFBundleIconFile` to generated `Info.plist` files.

## Acceptance Criteria

- `scripts/build-and-run --verify` creates `dist/wetrans.app/Contents/Resources/AppIcon.icns`.
- `dist/wetrans.app/Contents/Info.plist` contains `CFBundleIconFile` with value `AppIcon`.
- `scripts/package` includes the same icon in the packaged app bundle.
- The build still passes `scripts/typecheck`.
