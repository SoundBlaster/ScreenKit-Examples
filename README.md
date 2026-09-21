# ScreenKit-Examples

Runnable iOS examples for [ScreenKit](https://github.com/SoundBlaster/ScreenKit) and
[Patchwork](https://github.com/SoundBlaster/Patchwork). Both apps consume the published
Swift packages directly; this repository has no dependency on the Puzzle monolith.

## Examples

### ScreenKit Lab

A focused API laboratory for collection screens, sectioned content, heterogeneous
Patchwork renderers, ScreenKit macros, and native screen containers. The test targets
exercise package use from a consuming app.

### ToNaTo

A small price-comparison app demonstrating a complete ScreenKit + Patchwork flow:
editable UIKit rows, SwiftUI content, configuration-based rows, onboarding pages,
navigation, and saved comparison history.

## Requirements

- Xcode 27 or later with the Swift 6.2 toolchain
- iOS 18 or later simulator

The project is a native Xcode project and does not require Tuist. Its current
project document uses `project.pbxproj`; Xcode 27.2 adds the newer JSON
`project.xcproj` format, which can be selected when that Xcode version is
available.

## Build and test

```sh
open ScreenKitExamples.xcodeproj
```

The project has shared schemes for both apps and uses Swift Package Manager dependencies.

Run all unit and UI tests:

```sh
make test
```

Run one app's tests:

```sh
make test-screenkitlab
make test-tonato
```

The test destination defaults to iPhone 17 Pro and can be overridden:

```sh
make test SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=18.6'
```
