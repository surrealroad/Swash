import Cocoa

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

for win in windowList {
    if let owner = win[kCGWindowOwnerName as String] as? String, owner == "Swash",
       let windowID = win[kCGWindowNumber as String] as? Int,
       let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
       let width = bounds["Width"], width > 200 {
        print("\(windowID)")
        exit(0)
    }
}
exit(1)
