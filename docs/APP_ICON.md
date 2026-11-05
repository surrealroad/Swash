# App Icon Prompt & Generation Guide

This document records the brand palette, prompts, and rendering pipeline used to create the Swash app icon (`Swash/Assets.xcassets/AppIcon.appiconset`), aligned with the Pixerate family visual identity (`JazzPaint/docs/APP_ICON.md`).

## 1. Pixerate Brand Palette

- **Background**: Deep obsidian-violet gradient (`#0D061A` to `#1A0B2E`)
- **Primary Fuchsia (`--primary` / `AccentColor`)**: `#EE6BFF` (light) / `#C800DE` (dark)
- **Glow Outline (`GlowOutline`)**: `#E12AFB` (`oklch(0.667 0.295 322.15)`)
- **Glow Shadow (`GlowShadow`)**: `#8E51FF` / `#7F22FE` (`oklch(0.606 0.25 292.717)`)
- **Swash / Pixel Gradient**: Hot pink (`#EC4899` / `#EE1D7E`) → electric fuchsia (`#E12AFB`) → luminous violet (`#8E51FF`) → electric indigo (`#4338CA`)

## 2. Subagent Brief

```text
Generate a 1024x1024 app icon for "Swash" (a macOS and iOS Markdown & writing app by Pixerate).

Visual brief:
- Style: Typical modern Apple macOS / iOS app icon aesthetic — tactile, dimensional, glossy 3D/vector-crafted object with rich lighting, subtle inner glow, smooth gradients, and clean silhouette.
- Subject: A bold, sculptural, glossy 3D calligraphic serif letter "S" intertwined with its graceful infinity-like looping typographic swash flourish, where the sweeping ends of the calligraphic swash flourish gracefully dissolve and scatter outward into crisp, floating, luminous rounded-square pixel blocks of varying sizes with glowing edges (echoing the Pixerate loose pixel motif).
- Brand Colours (from the Pixerate repo):
  - Background: Full-bleed rich dark obsidian-violet gradient (`#0D061A` to `#1A0B2E`, full square canvas with NO white border, NO transparent corners, and NO pre-cut rounded-rectangle frame inside the image — fill the entire 1024x1024 square edge-to-edge so iOS/macOS icon masks apply cleanly).
  - Swash & Pixels Palette: Pixerate's signature neon gradient — hot pink / rose (`#EC4899` / `#EE1D7E`), electric fuchsia (`#E12AFB` / `#EE6BFF` / `#C800DE`), luminous violet (`#8E51FF` / `#7F22FE`), and deep electric indigo (`#4338CA`).
- Composition: Centered, bold, uncluttered, instantly readable at both 1024px and small 16px/32px dock/home-screen sizes. No text label below the emblem.
```

## 3. Exact Image Generation Prompt

```text
Apple macOS and iOS app icon design for a modern Markdown writing app. Full-bleed edge-to-edge dark obsidian-violet gradient background (#0D061A to #1A0B2E), completely filling the 1:1 square canvas into all four 90-degree corners without rounded corner cutouts, borders, or squircle frames. In the center, a single bold, sculptural, tactile 3D calligraphic serif letter "S" intertwined with an elegant, sweeping infinity-like typographic swash flourish looping through its middle. The 3D calligraphic "S" and its sweeping swash flourish are rendered in glossy, luminous neon gradients of hot pink (#EC4899), electric fuchsia (#E12AFB), vibrant violet (#8E51FF), and deep electric indigo (#4338CA), with glass-like specular highlights and subtle inner bloom. The sweeping loop of the swash flourish gracefully dissolves and scatters outward into crisp, floating, luminous rounded-square pixel blocks of varying sizes with glowing edges. Clean, uncluttered iconic silhouette, centered, readable at small dock sizes, no fountain pen, no extra text wordmark.
```

## 4. Generating the iOS & macOS Asset Set

- **iOS (`icon_ios_1024.png`)**: Uses the 1024×1024 full-bleed opaque RGB PNG (`hasAlpha: no`).
- **macOS (`icon_16x16.png` through `icon_512x512@2x.png`)**: Framed to the Apple HIG macOS squircle grid (`824/1024` body, continuous corner radius `22.37%` of the body, specular inner border, and downward Dock drop shadow `dy = +10`, `radius = 16`, `opacity = 28%`):

```bash
swift -e '
import AppKit
import SwiftUI

@MainActor
func renderMacSquircle(nsImage: NSImage, px: Int) -> Data {
    let s = CGFloat(px)
    let body = s * (824.0 / 1024.0)
    let radius = body * 0.2237
    let shadowRadius = s * (16.0 / 1024.0)
    let shadowY = s * (10.0 / 1024.0)
    let borderWidth = max(0.5, s * (2.0 / 1024.0))

    let view = ZStack {
        Color.clear
        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: body, height: body)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.93, green: 0.42, blue: 1.0).opacity(0.45),
                                Color.white.opacity(0.12),
                                Color(red: 0.56, green: 0.32, blue: 1.0).opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: borderWidth
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: shadowRadius, x: 0, y: shadowY)
    }
    .frame(width: s, height: s)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    guard let cgImage = renderer.cgImage else {
        fatalError("Failed to render at \(px)")
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: s, height: s)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG")
    }
    return pngData
}

MainActor.assumeIsolated {
    let outDir = "Swash/Assets.xcassets/AppIcon.appiconset"
    let srcPath = "\(outDir)/icon_ios_1024.png"
    guard let nsImage = NSImage(contentsOfFile: srcPath) else {
        fatalError("Could not load \(srcPath)")
    }

    let macSizes: [(name: String, px: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for item in macSizes {
        let pngData = renderMacSquircle(nsImage: nsImage, px: item.px)
        try! pngData.write(to: URL(fileURLWithPath: "\(outDir)/\(item.name)"))
    }
}
'
```
