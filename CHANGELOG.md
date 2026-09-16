# swash

## 1.2.0

### Minor Changes

- 9dadde2: Achieve full feature parity with GitHub Flavored Markdown (GFM) Specification:
  - Parser: Add support for link reference definitions, arbitrary fence lengths (backticks and tildes), ATX closing hashes, Setext headings, thematic breaks with mixed characters/spaces, list marker variations (`-`, `*`, `+`, numbered), and pipe handling inside code spans in tables.
  - Formatted Editor: Render continuous alert callout blocks, Setext headings with hidden delimiter lines, thematic break divider rules, interactive checkbox markers with custom tint, and expanded underscore-based inline emphasis.
  - Preview & Quick Look: Add base URL resolution for document-relative assets and hide link reference definition blocks.
  - Test Suite: Add comprehensive GFM compliance fixture suite and headless snapshot renderer covering 40 spec cases across 7 categories.

## 1.1.3

### Patch Changes

- a7be6b4: Add automated GFM spec compliance testing and headless visual snapshot test harness for Tables and Task Lists.

## 1.1.2

### Patch Changes

- b5be2cf: Update AGENTS.md to mandate maintaining and checking GOTCHAS.md for issues, pitfalls, solutions, and workarounds.

## 1.1.1

### Patch Changes

- e346b21: Refine release workflow sequence to commit and push version bumps and assets prior to creating GitHub releases.

## 1.1.0

### Minor Changes

- d1de8bb: Mandate and configure Changesets for versioning and change tracking across the repository.
