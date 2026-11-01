import AppKit

/// Draws the app icon: Mochi standing on top of a little window, on a sky-to-sunset tile.
enum AppIcon {
    /// Writes a macOS .iconset folder; `iconutil -c icns` turns it into AppIcon.icns.
    static func writeIconset(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for mult in [1, 2] {
                let name = mult == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                write(render(base * mult), to: "\(dir)/\(name)")
            }
        }
    }

    static func render(_ px: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let u = CGFloat(px) / 1024   // design in a 1024 grid, Cocoa-style y-up
        ctx.scaleBy(x: u, y: u)

        // Tile with Apple's icon-grid margins
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
        ctx.addPath(tilePath)
        ctx.setFillColor(rgb(0x8EC5FF))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()
        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [rgb(0xFFD6A5), rgb(0xFFB5C2), rgb(0x8EC5FF)] as CFArray,
                             locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

        // A window for Mochi to stand on
        let win = CGRect(x: 170, y: 60, width: 684, height: 380)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: CGColor(gray: 0, alpha: 0.25))
        ctx.addPath(CGPath(roundedRect: win, cornerWidth: 36, cornerHeight: 36, transform: nil))
        ctx.setFillColor(rgb(0xFFFDF8))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: win, cornerWidth: 36, cornerHeight: 36, transform: nil))
        ctx.clip()
        ctx.setFillColor(rgb(0xECE6F6))
        ctx.fill(CGRect(x: win.minX, y: win.maxY - 64, width: win.width, height: 64))
        ctx.restoreGState()
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(rgb(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: win.minX + 34 + CGFloat(i) * 46, y: win.maxY - 46, width: 28, height: 28))
        }
        // Text lines inside the window
        ctx.setFillColor(rgb(0xE4DDEE))
        for (i, w) in [420.0, 330, 380].enumerated() {
            ctx.addPath(CGPath(roundedRect: CGRect(x: win.minX + 48, y: win.maxY - 130 - CGFloat(i) * 56, width: w, height: 24),
                               cornerWidth: 12, cornerHeight: 12, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()

        // Mochi, crisp pixels, feet on the window's top edge
        let sprite = SpriteSheet(kind: .mochi).image(.stand, .open)
        let size: CGFloat = 16 * 28
        ctx.interpolationQuality = .none
        ctx.draw(sprite, in: CGRect(x: 512 - size / 2, y: win.maxY, width: size, height: size))
        return ctx.makeImage()!
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func write(_ img: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
