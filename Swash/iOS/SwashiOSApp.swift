//
//  SwashiOSApp.swift
//  Swash
//
//  App entry point on iPhone and iPad. The macOS entry point is in SwashApp.swift.
//

#if os(iOS)
import SwiftUI

@main
struct SwashApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: SwashDocument()) { file in
            IOSContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            // The iPadOS menu bar and hardware-keyboard shortcuts, as on the Mac
            FormatMenuCommands()
        }
    }
}
#endif
