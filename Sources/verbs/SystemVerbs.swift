import ArgumentParser
import Foundation

struct NotifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Post a user notification (Notification Center).")
    @Argument(help: "Notification body text.") var message: String
    @Option(name: .long, help: "Notification title.") var title: String = "verbs"
    @Option(name: .long, help: "Notification subtitle.") var subtitle: String?
    @Flag(name: .long, help: "Play the default notification sound.") var sound = false
    @OptionGroup var out: OutputOptions

    func run() throws {
        var script = "display notification \(appleScriptQuote(message))"
        script += " with title \(appleScriptQuote(title))"
        if let subtitle { script += " subtitle \(appleScriptQuote(subtitle))" }
        if sound { script += " sound name \"default\"" }
        try osascript(script)
        Out.emit(out, human: "notified: \(title): \(message)",
                 data: ["action": "notify", "title": title, "message": message])
    }
}

struct DarkmodeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "darkmode",
        abstract: "Get or set system appearance. First use prompts once to allow controlling System Events.")
    @Argument(help: "get | on | off | toggle") var action: String = "get"
    @OptionGroup var out: OutputOptions

    func run() throws {
        let prefix = "tell application \"System Events\" to tell appearance preferences to "
        switch action {
        case "get":
            break
        case "on":
            try osascript(prefix + "set dark mode to true")
        case "off":
            try osascript(prefix + "set dark mode to false")
        case "toggle":
            try osascript(prefix + "set dark mode to not dark mode")
        default:
            throw ValidationError("action must be get | on | off | toggle")
        }
        // Always report from a fresh read: the return value of the `set`
        // statement is unreliable (observed stale on back-to-back toggles).
        let dark = try osascript(prefix + "get dark mode") == "true"
        Out.emit(out, human: dark ? "dark" : "light",
                 data: ["action": "darkmode", "requested": action, "dark": dark])
    }
}

struct VolumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "volume",
        abstract: "Get or set output volume (0-100), mute or unmute.")
    @Argument(help: "get | mute | unmute | 0-100") var action: String = "get"
    @OptionGroup var out: OutputOptions

    func run() throws {
        switch action {
        case "get":
            let vol = try osascript("output volume of (get volume settings)")
            let muted = try osascript("output muted of (get volume settings)")
            Out.emit(out, human: "volume \(vol)" + (muted == "true" ? " (muted)" : ""),
                     data: ["action": "volume_get", "volume": Int(vol) ?? -1,
                            "muted": muted == "true"])
        case "mute":
            try osascript("set volume with output muted")
            Out.emit(out, human: "muted", data: ["action": "volume_mute", "muted": true])
        case "unmute":
            try osascript("set volume without output muted")
            Out.emit(out, human: "unmuted", data: ["action": "volume_mute", "muted": false])
        default:
            guard let level = Int(action), (0...100).contains(level) else {
                throw ValidationError("action must be get | mute | unmute | 0-100")
            }
            try osascript("set volume output volume \(level)")
            Out.emit(out, human: "volume set to \(level)",
                     data: ["action": "volume_set", "volume": level])
        }
    }
}

struct SayCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "say",
        abstract: "Speak text aloud (blocks until finished).")
    @Argument(help: "Text to speak.") var text: String
    @Option(name: .long, help: "Voice name, e.g. \"Samantha\".") var voice: String?
    @OptionGroup var out: OutputOptions

    func run() throws {
        var args: [String] = []
        if let voice { args += ["-v", voice] }
        args.append(text)
        try shell("/usr/bin/say", args)
        Out.emit(out, human: "said \(text.count) chars",
                 data: ["action": "say", "length": text.count,
                        "voice": voice ?? NSNull()])
    }
}

struct ScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture the screen to a file. Full window content requires Screen Recording permission; without it macOS captures wallpaper only.")
    @Argument(help: "Output path (.png).") var path: String
    @Flag(name: .long, help: "Capture the main display only.") var mainDisplay = false
    @OptionGroup var out: OutputOptions

    func run() throws {
        let resolved = (path as NSString).expandingTildeInPath
        var args = ["-x"]  // no camera sound
        if mainDisplay { args.append("-m") }
        args.append(resolved)
        do {
            try shell("/usr/sbin/screencapture", args)
        } catch let e as VerbError {
            throw VerbError(message: e.message +
                " (screen capture requires Screen Recording permission for the" +
                " calling app: System Settings > Privacy & Security > Screen Recording)")
        }
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw VerbError(message: "screencapture produced no file")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: resolved)
        let size = (attrs?[.size] as? Int) ?? 0
        Out.emit(out, human: "screenshot -> \(resolved)",
                 data: ["action": "screenshot", "path": resolved,
                        "bytes": size])
    }
}
