---
name: changeset-management
description: >-
  Create, format, and verify changesets for pull requests, commits, and releases in Swash.
  Use when completing a feature, bugfix, refactor, or chore prior to committing and pushing.
---

# Changeset Management Workflow

Every commit, pull request, and release in Swash requires an accompanying changeset file inside `.changeset/`.

## 1. Creating a Changeset

Create a markdown file with a descriptive kebab-case name in `.changeset/<unique-name>.md`:

```markdown
---
"swash": <type>
---

<Clear description of changes made>
```

### Semantic Bump Types
- `patch`: Bug fixes, minor adjustments, documentation, internal chores, or non-breaking refactors.
- `minor`: New features, visible UI additions, or new capabilities that maintain backwards compatibility.
- `major`: Breaking architectural shifts, minimum macOS version requirement changes, or backwards-incompatible file format shifts.

## 2. Verification

Before committing, verify pending changesets:

```bash
npx changeset status --since=origin/main
```

### Known Gotcha: Verification on `main`
- **Issue**: Running `npx changeset status --since=origin/main` when working directly on `main` before committing will fail with:
  `Error: Failed to find where HEAD diverged from "origin/main"`
  because HEAD has not diverged from `origin/main` yet.
- **Solution**:
  1. Ensure the markdown file exists in `.changeset/` and strictly adheres to the frontmatter format above (specifying package `"swash"`).
  2. Or, run verification after committing locally: `npx changeset status --since=HEAD~1`.
