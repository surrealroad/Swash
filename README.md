<div align="center">

# <img src="Swash/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="40" valign="middle"> Swash

### *A Native, High-Performance macOS Markdown Editor with Style*

[![Swift Version](https://img.shields.io/badge/Swift-5.10+-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS_15.0+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://apple.com)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](./LICENSE)
[![Build & Release](https://img.shields.io/badge/Release-Automated-brightgreen?style=for-the-badge&logo=github-actions&logoColor=white)](#automated-distribution)

<p align="center">
  <b>Swash</b> is a sleek, distraction-free markdown editing workspace meticulously crafted with Swift, SwiftUI, and AppKit. Designed from the ground up for writers, developers, and note-takers who demand native macOS performance and an aesthetic writing experience.
</p>

---

[Key Features](#-key-features) • [Premium Design](#%EF%B8%8F-premium-design) • [Quick Start](#-quick-start) • [Automated Releases](#-automated-distribution) • [License](#-license)

</div>

---

## ✨ Key Features

Swash combines the raw speed of AppKit's native text engine with the rich, fluid layouts of SwiftUI.

*   **⚡ Blazing-Fast Native Engine** – Powered by an optimized `NSTextView` wrapper (`SwashTextView`) for instant rendering, smooth typing, and robust scroll performance.
*   **🫧 Floating Selection Bubble Menu with Code Dropdown** – Select text to trigger an elegant, contextual bubble overlay allowing you to style your prose instantly. When code formatting is active, an integrated dropdown selector lets you choose between multiple formats and programming languages (Inline, Plain Block, JavaScript, Swift, Python, HTML, CSS, JSON, Bash) with dynamic menu positioning.
*   **📑 macOS Document-Based Architecture** – Full native integration with the macOS system. Benefit from automatic saving, file history, sandboxed security, and standard system menus.
*   **🎨 Premium Styled Markdown & Code Blocks** – Implements a sophisticated, custom-crafted `MarkdownParser` to beautifully render headings, lists, bold/italic, and links. Features gorgeous block-level and inline code formatting, automatically hiding markup delimiters (` ``` ` and languages) and displaying code cleanly inside styled containers with subtle background highlight overlays. Spellchecking and grammar corrections are automatically disabled inside code blocks to keep your code pristine and free of red squiggly underlines.
*   **🛠️ Full macOS Integration** – Leverages system-level spellchecking, autocorrect options, undo/redo handling, and native keyboard navigation.

---

## 🖌️ Premium Design & Typographic Details

Every detail of Swash has been fine-tuned to create a calm, delightful, and highly-productive writing environment:

<p align="center">
  <img src="Screenshot.png" alt="Swash Interface" width="800">
</p>

### 📐 Ergonomic Elements
*   **Perfect Line Spacing & Padding**: Customized text container insets provide standard 20px padding margins to keep text perfectly centered and comfortable to read.
*   **System Color Adaptive**: Automatically respects Light & Dark mode settings, shifting colors with beautiful macOS vibrancy.
*   **Floating Component Synchronization**: The floating selection menu is synchronized dynamically with bounds modifications and viewport scroll offsets, staying exactly where you expect it.

---

## 🚀 Quick Start

### Prerequisites
*   A Mac running **macOS 15.0+**
*   **Xcode 16.0+** or Swift Command Line Tools

### Building from Source

To compile and launch the application locally:

```bash
# Clone the repository
git clone https://github.com/surrealroad/Swash.git
cd Swash

# Build the Release version
xcodebuild -scheme Swash -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="-"

# Run the app directly
open build/Build/Products/Release/Swash.app
```

---

## 🤖 Automated Distribution & Code Signing

Swash features a modern, automated release pipeline powered by GitHub Actions. Every push to the `main` branch automatically:

1.  **Imports Apple Code Signing Certificates** securely from GitHub Secrets (if configured) or falls back gracefully to ad-hoc signatures.
2.  **Compiles and Code Signs** the native `.app` bundle, `.zip` archive, and `.dmg` disk image binaries targeting Apple Silicon and Intel Macs.
3.  **Packages the app** into:
    *   A signed, installer-ready **`.dmg` Disk Image**
    *   A signed **`.zip` Archive**
4.  **Generates a changelog** detailing all commits and contributions since the previous release.
5.  **Publishes a GitHub Release** with the assets attached and ready to download instantly!

> [!TIP]
> **Code Signing & Notarization Setup**:
> 1. Export your **Developer ID Application** certificate from Keychain Access as a `.p12` file.
> 2. Convert it to Base64 (`base64 -i Certificate.p12 | pbcopy`).
> 3. Add repository secrets in **Settings > Secrets and variables > Actions**:
>    - `MACOS_CERTIFICATE`: Base64 string of your `.p12` certificate.
>    - `MACOS_CERTIFICATE_PWD`: Password for the `.p12` file (leave empty if no password was set).
>    - `KEYCHAIN_PASSWORD`: Any temporary password for the CI keychain.
>    - `CODE_SIGN_IDENTITY` *(Optional)*: Name of your certificate (auto-detected if omitted).
>
> **To remove the Gatekeeper "Apple could not verify..." malware warning**, add Apple Notarization credentials:
>    - `NOTARIZATION_APPLE_ID`: Your Apple ID email (e.g. `user@example.com`).
>    - `NOTARIZATION_PASSWORD`: An App-Specific Password generated at [appleid.apple.com](https://appleid.apple.com).
>    - `NOTARIZATION_TEAM_ID`: Your 10-character Team ID from [developer.apple.com/account](https://developer.apple.com/account).

> [!TIP]
> Visit the [Releases](https://github.com/surrealroad/Swash/releases) section of the repository to grab the latest built application installer (`.dmg`) instantly.


---

## 📝 License

Distributed under the **MIT License**. See [`LICENSE`](./LICENSE) for more information.

<div align="center">
  <sub>Crafted with ❤️ by Jack James & Contributors</sub>
</div>
