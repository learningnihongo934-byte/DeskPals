import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    SpriteSheet.writePreview(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--iconset"), i + 1 < args.count {
    AppIcon.writeIconset(to: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
