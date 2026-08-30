# Changesets

Hello and welcome! This folder contains Changeset files that track versions and changes for Swash.

## Adding a Changeset

When you make changes to this repository, create a changeset markdown file describing your change:

```bash
npx changeset
```

Follow the prompts to select the package (`swash`), semantic bump type (`patch`, `minor`, or `major`), and provide a summary of your changes.

You can also run:
```bash
npm run changeset:status
```
to view pending changesets against `origin/main`.
