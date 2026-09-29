---
name: swash-build-test
description: >-
  Build Swash, compile application extensions, and execute the GFM spec compliance tests.
  Use when compiling the macOS project, running tests, or validating changes before committing.
---

# Swash Build & Test Workflow

This skill guides building the Swash macOS application, its app extensions, and running test suites.

## 1. Quick Build Verification

To quickly verify that the application compiles without code signing requirements:

```bash
xcodebuild -scheme Swash -configuration Debug build CODE_SIGN_IDENTITY="-"
```

To compile specific app extensions:
```bash
# Quick Look Extension
xcodebuild -scheme SwashQuickLookExtension -configuration Debug build CODE_SIGN_IDENTITY="-"

# Share Extension
xcodebuild -scheme SwashShareExtension -configuration Debug build CODE_SIGN_IDENTITY="-"

# Widget Extension
xcodebuild -scheme SwashWidgetExtension -configuration Debug build CODE_SIGN_IDENTITY="-"

# Thumbnail Extension
xcodebuild -scheme SwashThumbnailExtension -configuration Debug build CODE_SIGN_IDENTITY="-"
```

## 2. Running GFM Spec Tests

Swash validates its markdown parsing against the GitHub Flavored Markdown (GFM) spec and snapshot suite:

```bash
./scripts/run_spec_tests.sh
```

This compiles `Tests/GFMSpec/GFMSpecRunner.swift` with the Swash markdown components and executes the test suite. Ensure all tests pass with zero failures.

## 3. Known Build Gotchas

- **Sandbox Permissions**: If `xcodebuild` fails with `Operation not permitted (error code 1 / 257)` when accessing derived data (`~/Library/Developer/Xcode/DerivedData`) or clang module caches (`/var/folders/.../C/clang/ModuleCache`), ensure the command runs with appropriate developer permissions (`BypassSandbox: true` where needed).
- **Derived Data Clean**: If experiencing corrupted Swift module caches or stale build products:
  ```bash
  rm -rf build/DerivedData build/spec-runner
  ```
