# Vendored popup dependencies

The player presentation uses the following MIT-licensed upstream packages:

- `LNPopupUI` 4.0.1
- `LNPopupController` 4.5.5
- `LNSwiftUIUtils` 1.1.5
- `LNSystemMarqueeLabel` 0.1.2

Only package sources, manifests, and license files are vendored. Demo projects and Git history are omitted.
The primary `LNPopupUI` product is built statically so XcodeGen does not need to embed a separate dynamic framework in the device app bundle.

## Xcode 27 Beta compatibility patch

`LNPopupController/Package.swift` prefixes recursively discovered private header search paths with `./`.
Without that prefix, Xcode 27 Beta truncates paths whose first component repeats the target name (for example,
`LNPopupController/Private/Appearance`), which causes otherwise-present private headers to report “file not found.”

Keep this patch when refreshing the package until upstream or Xcode no longer requires it.

## Player motion tuning

`LNPopupController.mm` sets the popup content transition duration to 0.62 seconds instead of the upstream 0.50 seconds. This is an intentional app-level tuning for a calmer, continuous mini-player dock/undock motion on the target ProMotion iPhone. Preserve or re-evaluate it when refreshing the package.

The same file rasterizes the full popup content controller at native screen scale only while an interactive drag is active, then disables rasterization after the settle animation. This keeps slow, finger-tracked closing to one composited surface instead of redrawing the SwiftUI player hierarchy each frame.
