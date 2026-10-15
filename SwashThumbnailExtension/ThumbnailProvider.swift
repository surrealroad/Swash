//
//  ThumbnailProvider.swift
//  SwashThumbnailExtension
//

import QuickLookThumbnailing
import AppKit

class ThumbnailProvider: QLThumbnailProvider {
    
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let size = request.maximumSize
        
        let reply = QLThumbnailReply(contextSize: size) { context -> Bool in
            let fileURL = request.fileURL
            // Only ~500 characters are drawn, so read just the start of the file
            let head = (try? FileHandle(forReadingFrom: fileURL)).flatMap { handle -> Data? in
                defer { try? handle.close() }
                return try? handle.read(upToCount: 4096)
            } ?? Data()
            // A character cut at the end of the 4 KB lies past the 500 drawn (at most 4 bytes each)
            let textContent = String(decoding: head, as: UTF8.self)
            
            // Draw background paper
            let bounds = CGRect(origin: .zero, size: size)
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            
            // Border
            NSColor.separatorColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            path.lineWidth = 1
            path.stroke()
            
            // Draw text snippet
            let padding: CGFloat = size.width * 0.08
            let textRect = bounds.insetBy(dx: padding, dy: padding)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byWordWrapping
            
            let fontSize = max(10, size.width * 0.06)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributedString = NSAttributedString(string: String(textContent.prefix(500)), attributes: attributes)
            
            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = nsContext
            
            attributedString.draw(in: textRect)
            
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        
        handler(reply, nil)
    }
}
