---
"swash": patch
---

Fix the release build on the CI toolchain (macOS 15.2 SDK). The editor no longer overrides `NSTextBlock.drawBackground`, whose signature differs between SDKs; indented code, quote and alert backgrounds are now painted by the layout manager. Pull requests now run an app build on the release toolchain.
