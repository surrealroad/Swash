# GitHub-Flavored Markdown (GFM) Compliance Matrix

This document tracks Swash's compliance against the official GitHub-Flavored Markdown (GFM) specification for supported syntax extensions and core blocks.

Automated verification runs via `./Scripts/run_spec_tests.sh`.

---

## 4.12 Tables (extension)

| Case ID | Example | Description | Parser AST | Preview View | Editor View | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `table-basic` | 198 | Basic 2x2 table with outer pipes | PASS | PASS | PASS | ✅ Compliant |
| `table-alignments` | 199 | Left, center, right delimiter alignments | PASS | PASS | PASS | ✅ Compliant |
| `table-escaped-pipes` | 200 | Table cells with escaped pipes `\|` | PASS | PASS | PASS | ✅ Compliant |
| `table-all-alignments` | 202 | All alignment specifiers (`:---`, `:---:`, `---:`) | PASS | PASS | PASS | ✅ Compliant |
| `table-ragged-rows` | 201 | Row with fewer cells than header | PASS | PASS | PASS | ✅ Compliant |
| `table-inline-formatting` | 203 | Inline markdown (code, bold, italic) in cells | PASS | PASS | PASS | ✅ Compliant |

---

## 5.3 Task List Items (extension)

| Case ID | Example | Description | Parser AST | Preview View | Editor View | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `tasklist-basic` | 279 | Basic checked and unchecked items | PASS | PASS | PASS | ✅ Compliant |
| `tasklist-case-insensitive`| 280 | Case-insensitive `[X]` vs `[x]` | PASS | PASS | PASS | ✅ Compliant |
| `tasklist-nested` | 281 | Indented / nested task list items | PASS | PASS | PASS | ✅ Compliant |
| `tasklist-mixed-asterisk` | 282 | Asterisk `* [ ]` bullet task list items | PASS | PASS | PASS | ✅ Compliant |

---

## Snapshot Gallery
Generated off-screen PNG snapshots are saved into:
- Formatted Preview: `Tests/GFMSpec/snapshots/preview/<case-id>.png`
- Rich Editor: `Tests/GFMSpec/snapshots/editor/<case-id>.png`
