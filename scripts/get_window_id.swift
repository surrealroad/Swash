import Cocoa

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

// Optionally limited to one process: get_window_id.swift <pid>
let pid = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) : nil

for win in windowList {
    if let owner = win[kCGWindowOwnerName as String] as? String,
       owner.contains("Swash"),
       pid == nil || win[kCGWindowOwnerPID as String] as? Int == pid,
       let windowID = win[kCGWindowNumber as String] as? Int,
       let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
       let width = bounds["Width"], width > 200 {
        print("\(windowID)")
        exit(0)
    }
}
exit(1)
