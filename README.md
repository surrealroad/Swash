<div align="center">

# <img src="Swash/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="40" valign="middle"> Swash

### Write Markdown the way it looks.

[![Platform](https://img.shields.io/badge/macOS-15.7+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/surrealroad/Swash/releases)
[![iPhone and iPad](https://img.shields.io/badge/iPhone_%26_iPad-coming_soon-555555?style=for-the-badge&logo=apple&logoColor=white)](#-on-iphone-and-ipad)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](./LICENSE)

<p align="center">
  <b>Swash</b> is a fast, native Markdown editor for the Mac. You type in formatted text, with headings, lists, tables, images, math and diagrams shown as they'll look, while your notes stay plain <code>.md</code> files you can open anywhere.
</p>

[**Download for Mac**](https://github.com/surrealroad/Swash/releases/latest) • [Features](#-features) • [Shortcuts](#%EF%B8%8F-keyboard-shortcuts) • [Build from source](#-build-from-source)

<img src="Screenshot.png" alt="Swash editing a Markdown document" width="800">

</div>

---

## ✨ Features

### Edit formatted text, keep plain Markdown

- **Formatted editing.** Write straight into styled text: the Markdown symbols disappear and you see headings, bold, links, quotes and lists. Switch to **Source** to see every character, or **Split** to see both side by side, scrolling together.
- **Feels like Notion.** Press Enter to continue a list or to-do, Tab to nest it, and Backspace to undo a heading or bullet. Type **/** on an empty line to insert a heading, list, quote, callout, code block, divider or table.
- **Formatting at your fingertips.** Select text for a floating formatting menu, or use the Format menu and familiar shortcuts like ⌘B, ⌘I and ⌘K.
- **Paste from anywhere.** Text copied from web pages, Google Docs, Word, Pages, Confluence or Jira is turned into clean Markdown, with its headings, links, lists, tables and images.
- **Tables you can edit.** Click into a cell and type; no lining up pipes by hand.
- **Clickable to-do lists.** Check items off with a click.

### Everything renders

- **Math and diagrams.** LaTeX equations and Mermaid flowcharts, sequence diagrams and charts are drawn right in the document, even offline.
- **Images** from your document's folder appear inline.
- **Code blocks** with syntax colouring and a language badge you can click to change.
- **GitHub-style extras:** alerts (Note, Tip, Warning…), footnotes, task lists, collapsible sections, keycaps and more.
- **Fully compatible.** Swash follows the CommonMark and GitHub Flavored Markdown standards, so files look the same in Swash as they do on GitHub. It can also edit Slack-style formatting.

### Built for the Mac

- **Work on a whole folder.** File › Open Folder… shows all your Markdown files in a sidebar, saves as you go, and picks up changes made in other apps.
- **Preview in Finder.** Press Space on any Markdown file for a formatted Quick Look preview, and see real thumbnails of your notes.
- **Capture from anywhere.** Send selected text from any app to a new Swash note with the Services menu, or create notes and count words with Shortcuts.
- **A real Mac app.** Light and Dark Mode, autosave and version history, system spellcheck (kept out of your code blocks), undo everything, and automatic updates.
- **Private by design.** No account, no cloud and no tracking. Your files stay where you put them.

---

## ⌨️ Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘B / ⌘I / ⌘E | Bold / italic / inline code |
| ⌘⇧X | Strikethrough |
| ⌘K | Add, edit or remove a link |
| ⌥⌘1–3 / ⌥⌘0 | Heading 1–3 / body text |
| ⇧⌘8 / ⇧⌘7 / ⇧⌘9 | Bulleted / numbered / to-do list |
| ⇧⌘. | Quote |
| ⌥⌘C | Code block |
| ⇧⌘O | Open a folder |
| / | Insert a block (on an empty line) |

---

## 📱 On iPhone and iPad

Swash for iPhone and iPad is on its way. It has the same formatted editor, slash menu and editable tables as the Mac, a formatting bar above the keyboard, Split view on iPad, a Quick Note widget, Shortcuts, and a **Save to Swash** share option for other apps. Until it's in the App Store you can [build it from source](#-build-from-source).

---

## 📥 Install

1. Download **Swash-macOS.dmg** from the [latest release](https://github.com/surrealroad/Swash/releases/latest).
2. Open it and drag Swash to your Applications folder.
3. Open Swash. It can set itself as your default app for `.md` files in **Settings**, and it keeps itself up to date.

> [!TIP]
> If macOS says it can't check Swash for malicious software, Control-click the app in Applications and choose **Open**.

---

## 🛠 Build from source

You need macOS 15.7 or later and Xcode 26.

```bash
git clone https://github.com/surrealroad/Swash.git
cd Swash
xcodebuild -scheme Swash -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="-"
open build/Build/Products/Release/Swash.app
```

For iPhone and iPad, open `Swash.xcodeproj` in Xcode, choose an iOS device or simulator, and run.

Contributors: see [`AGENTS.md`](./AGENTS.md) for the workflow, [`GOTCHAS.md`](./GOTCHAS.md) for known pitfalls and [`docs/RELEASING.md`](./docs/RELEASING.md) for how releases are built and signed.

---

## 📝 License

Swash is released under the [MIT License](./LICENSE).

Swash bundles [KaTeX](https://katex.org) (MIT, © Khan Academy and contributors) for math typesetting and [Mermaid](https://mermaid.js.org) (MIT, © Knut Sveidqvist) for diagrams. Both run offline inside the app; their licenses are in [`Swash/Rendering/`](./Swash/Rendering/).

<div align="center">
  <sub>Made by Jack James and contributors</sub>
</div>
