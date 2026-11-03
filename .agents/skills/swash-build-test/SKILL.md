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

## 3. Markdown Conformance (shared editing corpus)

Swash's editing engine is held to the shared corpus in `@pixerate/markdown-conformance` (a pinned dev dependency, installed by `npm ci`):

```bash
npm ci
./scripts/run_conformance_tests.sh            # all cases
./scripts/run_conformance_tests.sh --verbose  # print every case
./scripts/run_conformance_tests.sh --case link-update-url
```

This compiles `Swash/Markdown/*.swift` with `Tests/MarkdownConformance/ConformanceRunner.swift` (Foundation only, no app target). Each fixture's selection markers (`‸`, `⟦…⟧`) become a raw-Markdown UTF-16 range; `format.*` commands go through `FormatCommandEdits` and `edit.*` through `MarkdownEditingCommands`. Cases with `skip.swash` upstream, or in the runner's `localSkips`, are reported as skipped with their reason. It exits non-zero on any failure, and the PR build runs it.

The Format menu, shortcuts, bubble-menu labels and code languages are generated from the package's `manifest.json`:

```bash
node scripts/generate_format_manifest.mjs           # rewrite Swash/Markdown/FormatManifest.generated.swift
node scripts/generate_format_manifest.mjs --check   # exit 1 if the committed file is stale
```

Commit the generated file. To upgrade the package, bump the exact version in `package.json`, run `npm ci`, regenerate, then fix (or locally skip, with a reason) any new conformance failures. See GOTCHAS #43 and #44.

## 4. Other Test Suites

```bash
./scripts/run_commonmark_spec.sh   # CommonMark/GFM parser spec and engine checks
./Tests/EditorAudit/run_audit.sh   # render, interaction, bubble-menu and perf harnesses
./scripts/run_rich_render_tests.sh # math and Mermaid rendering
./scripts/run_export_tests.sh      # HTML and PDF export
```

After `./scripts/run_spec_tests.sh`, restore the snapshots (GOTCHAS #8).

## 5. Known Build Gotchas

- **Sandbox Permissions**: If `xcodebuild` fails with `Operation not permitted (error code 1 / 257)` when accessing derived data (`~/Library/Developer/Xcode/DerivedData`) or clang module caches (`/var/folders/.../C/clang/ModuleCache`), ensure the command runs with appropriate developer permissions (`BypassSandbox: true` where needed).
- **Derived Data Clean**: If experiencing corrupted Swift module caches or stale build products:
  ```bash
  rm -rf build/DerivedData build/spec-runner
  ```
