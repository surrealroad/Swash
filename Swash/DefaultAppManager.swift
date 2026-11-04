//
//  DefaultAppManager.swift
//  Swash
//
//  Swash's shared default-app manager for Markdown files. The manager itself lives in MacAppKitExtras.
//

#if os(macOS)
import UniformTypeIdentifiers
import MacAppKitExtras

extension DefaultAppManager {
    static let shared = DefaultAppManager(
        contentTypes: [
            UTType(filenameExtension: "md"),
            UTType("net.daringfireball.markdown")
        ].compactMap { $0 },
        prompt: .init(
            messageText: "Make Swash your default Markdown app?",
            informativeText: "Swash is not currently the default app for .md files. Would you like to make it the default app?"
        )
    )
}
#endif
