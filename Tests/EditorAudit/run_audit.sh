#!/bin/bash
# Reproduces the WYSIWYG editor audit (see docs/WYSIWYG_AUDIT.md).
# Usage: ./Tests/EditorAudit/run_audit.sh [render|interact|bubble|perf|all]
set -eo pipefail
cd "$(dirname "$0")/../.."
OUT="build/editor-audit"; mkdir -p "$OUT"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
CORE="Swash/Markdown/*.swift Swash/MarkdownEditorStyler.swift Swash/MarkdownFlavor.swift Swash/FolderAccessManager.swift Swash/MarkdownParser.swift Swash/MarkdownPreviewView.swift Swash/DetectedLink.swift Swash/InteractiveTableView.swift Swash/SwashTextView.swift"
what="${1:-all}"

if [[ $what == render || $what == all ]]; then
  swiftc -O -target arm64-apple-macos14.0 -sdk "$SDK" $CORE Swash/BubbleMenuView.swift Tests/EditorAudit/AuditRunner.swift -o "$OUT/render"
  "$OUT/render" "$OUT/render-out" | sed -n "/^RENDER/,\$p"; echo "Rendering report: $OUT/render-out/report.md (side-by-side PNGs in shots/)"
fi
if [[ $what == interact || $what == all ]]; then
  swiftc -O -target arm64-apple-macos14.0 -sdk "$SDK" $CORE Swash/BubbleMenuView.swift Tests/EditorAudit/InteractionRunner.swift -o "$OUT/interact"
  "$OUT/interact" "$OUT/interaction.md" | sed -n "/^INTERACTION/,\$p"; echo "Interaction report: $OUT/interaction.md"
fi
if [[ $what == bubble || $what == all ]]; then
  # Inject a hook into a copy of BubbleMenuView so the harness can invoke the exact closures the buttons call.
  python3 - "$OUT/BubbleMenuView.hooked.swift" <<'PY'
import sys
s = open("Swash/BubbleMenuView.swift").read()
s = s.replace("    var body: some View {\n        HStack(spacing: 4) {",
 "    var body: some View {\n        let _ = TestHooks.register(onAction: onAction, onCode: onSelectCodeFormat, onHeading: onSelectHeadingLevel, onLink: onApplyLink, context: context, formats: activeFormats, heading: activeHeadingLevel, code: activeCodeFormat, link: activeLink)\n        HStack(spacing: 4) {", 1)
s += '''
enum TestHooks {
    static var onAction: ((FormatAction) -> Void)?
    static var onCode: ((CodeFormat) -> Void)?
    static var onHeading: ((Int) -> Void)?
    static var onLink: ((String) -> Void)?
    static var state: String = ""
    static func register(onAction: @escaping (FormatAction) -> Void, onCode: @escaping (CodeFormat) -> Void, onHeading: @escaping (Int) -> Void, onLink: @escaping (String) -> Void, context: BubbleMenuContext, formats: Set<FormatAction>, heading: Int?, code: CodeFormat?, link: DetectedLink?) -> Int {
        self.onAction = onAction; self.onCode = onCode; self.onHeading = onHeading; self.onLink = onLink
        state = "context=\\(context) active=\\(formats.map{"\\($0)"}.sorted()) heading=\\(heading.map{"H\\($0)"} ?? "-") code=\\(code.map{"\\($0)"} ?? "-") link=\\(link?.url ?? "-")"
        return 0
    }
}
'''
open(sys.argv[1], "w").write(s)
PY
  swiftc -O -target arm64-apple-macos15.0 -sdk "$SDK" $CORE "$OUT/BubbleMenuView.hooked.swift" Swash/SwashDocument.swift Swash/ContentView.swift Tests/EditorAudit/BubbleRunner.swift -o "$OUT/bubble"
  "$OUT/bubble" "$OUT/bubble-out" | sed -n "/^BUBBLE/,\$p"; echo "Bubble menu report: $OUT/bubble-out/bubble.md"
fi
if [[ $what == perf || $what == all ]]; then
  swiftc -O -target arm64-apple-macos14.0 -sdk "$SDK" $CORE Swash/BubbleMenuView.swift Tests/EditorAudit/PerfRunner.swift -o "$OUT/perf"
  "$OUT/perf" 2>/dev/null | grep "lines\|PERF"
fi
