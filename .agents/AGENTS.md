# Repository Rules

On completion of any work, agents must execute the following workflow:

## 1. Validation & Testing
- **Run Tests**: Execute all relevant unit, integration, and build tests locally (e.g. `xcodebuild -scheme Swash -configuration Debug build`) to validate that changes do not break existing functionality or introduce regressions before committing.

## 2. Changeset Creation
- **Requirement**: Every pull request, feature, bug fix, or task MUST include a changeset file generated via `npx changeset` (or by creating a markdown file in `.changeset/<unique-name>.md`).
- **Semantic Bump**: Select the appropriate semantic bump (`patch`, `minor`, `major`) and describe the changes clearly.
- **Verification**: Verify pending changesets before committing using `npx changeset status --since=origin/main`.

## 3. Automatic Commits and Pushes
- **Requirement**: Agents must automatically commit and push their changes to the remote GitHub repository as work is completed.
- **Commit Strategy**: Group changes into logical, atomic commits with clear, descriptive commit messages.
- **Frequency**: Commit and push whenever a coherent sub-task or the main task is successfully completed and verified. Do not wait for multiple unrelated tasks to pile up before committing.

## 4. CI Monitoring & Resolution
- **Monitor CI**: After pushing to GitHub, monitor the GitHub Actions / CI process execution (e.g. using `gh run list` / `gh run watch` or checking status).
- **Fix Errors & Warnings**: If the CI process fails or reports any errors or warnings, inspect the logs immediately, resolve the issues, re-validate locally, and push the fix. Repeat until CI builds cleanly without errors or warnings.
