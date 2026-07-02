import AppKit
import ApplicationServices
import ArgumentParser
import Foundation

// ---------------------------------------------------------------------------
// Window verbs — the one permission-tier-2 command group. Everything here
// requires the Accessibility permission (AXIsProcessTrusted) for the CALLING
// app (your terminal / agent host). Without it, every subcommand exits 1
// with pointed guidance instead of failing mysteriously.
// ---------------------------------------------------------------------------

private func requireAX() throws {
    guard AXIsProcessTrusted() else {
        throw VerbError(message:
            "window verbs require the Accessibility permission for the "
            + "calling app (System Settings > Privacy & Security > "
            + "Accessibility). Grant it to your terminal or agent host, "
            + "then retry.")
    }
}

private func axWindows(of app: NSRunningApplication) throws -> [AXUIElement] {
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value)
    guard err == .success, let windows = value as? [AXUIElement] else {
        if err == .apiDisabled {
            throw VerbError(message:
                "accessibility API disabled for this process — grant the "
                + "Accessibility permission and retry")
        }
        return []
    }
    return windows
}

private func axString(_ el: AXUIElement, _ attr: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success
    else { return nil }
    return v as? String
}

private func axBool(_ el: AXUIElement, _ attr: String) -> Bool {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
          let n = v as? Bool else { return false }
    return n
}

private func axPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
          let val = v, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
    var pt = CGPoint.zero
    return AXValueGetValue(val as! AXValue, .cgPoint, &pt) ? pt : nil
}

private func axSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
          let val = v, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
    var sz = CGSize.zero
    return AXValueGetValue(val as! AXValue, .cgSize, &sz) ? sz : nil
}

private func windowRecord(_ w: AXUIElement, index: Int) -> [String: Any] {
    let pos = axPoint(w, kAXPositionAttribute)
    let size = axSize(w, kAXSizeAttribute)
    return [
        "index": index,
        "title": axString(w, kAXTitleAttribute) ?? "",
        "x": pos.map { Int($0.x) } ?? NSNull() as Any,
        "y": pos.map { Int($0.y) } ?? NSNull() as Any,
        "width": size.map { Int($0.width) } ?? NSNull() as Any,
        "height": size.map { Int($0.height) } ?? NSNull() as Any,
        "minimized": axBool(w, kAXMinimizedAttribute),
    ]
}

private func targetWindow(app appName: String, index: Int) throws
    -> (NSRunningApplication, AXUIElement) {
    guard let app = runningApp(named: appName) else {
        throw VerbError(message: "\"\(appName)\" is not running")
    }
    let windows = try axWindows(of: app)
    guard index >= 0, index < windows.count else {
        throw VerbError(message:
            "\(appName) has \(windows.count) window(s); index \(index) not found")
    }
    return (app, windows[index])
}

struct WindowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "List, move, resize, minimize, and raise application windows. Requires the Accessibility permission.",
        subcommands: [List.self, Move.self, Resize.self, Minimize.self,
                      Unminimize.self, Raise.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List windows (all regular apps, or one app's).")
        @Option(name: .long, help: "Only this application's windows.")
        var app: String?
        @OptionGroup var out: OutputOptions

        func run() throws {
            try requireAX()
            let apps: [NSRunningApplication]
            if let app {
                guard let a = runningApp(named: app) else {
                    throw VerbError(message: "\"\(app)\" is not running")
                }
                apps = [a]
            } else {
                apps = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
            }
            var records: [[String: Any]] = []
            var humanLines: [String] = []
            for a in apps {
                let windows = (try? axWindows(of: a)) ?? []
                for (i, w) in windows.enumerated() {
                    var rec = windowRecord(w, index: i)
                    rec["app"] = a.localizedName ?? ""
                    records.append(rec)
                    let title = rec["title"] as? String ?? ""
                    let geo = "\(rec["width"] ?? "?")x\(rec["height"] ?? "?") @ \(rec["x"] ?? "?"),\(rec["y"] ?? "?")"
                    let min = (rec["minimized"] as? Bool == true) ? " (minimized)" : ""
                    humanLines.append(
                        "\(a.localizedName ?? "?")[\(i)] \(title.isEmpty ? "<untitled>" : title) — \(geo)\(min)")
                }
            }
            Out.emit(out, human: humanLines.isEmpty ? "no windows"
                        : humanLines.joined(separator: "\n"),
                     data: ["action": "window_list", "count": records.count,
                            "windows": records])
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a window to screen coordinates.")
        @Argument(help: "Application name.") var app: String
        @Argument(help: "X position.") var x: Int
        @Argument(help: "Y position.") var y: Int
        @Option(name: .long, help: "Window index (default 0 = frontmost).")
        var index: Int = 0
        @OptionGroup var out: OutputOptions

        func run() throws {
            try requireAX()
            let (a, w) = try targetWindow(app: app, index: index)
            var pt = CGPoint(x: x, y: y)
            let value = AXValueCreate(.cgPoint, &pt)!
            let err = AXUIElementSetAttributeValue(
                w, kAXPositionAttribute as CFString, value)
            guard err == .success else {
                throw VerbError(message: "could not move window (AX error \(err.rawValue))")
            }
            Out.emit(out, human: "moved \(a.localizedName ?? app)[\(index)] to \(x),\(y)",
                     data: ["action": "window_move", "app": a.localizedName ?? app,
                            "window": windowRecord(w, index: index)])
        }
    }

    struct Resize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resize a window.")
        @Argument(help: "Application name.") var app: String
        @Argument(help: "Width.") var width: Int
        @Argument(help: "Height.") var height: Int
        @Option(name: .long, help: "Window index (default 0 = frontmost).")
        var index: Int = 0
        @OptionGroup var out: OutputOptions

        func run() throws {
            try requireAX()
            let (a, w) = try targetWindow(app: app, index: index)
            var sz = CGSize(width: width, height: height)
            let value = AXValueCreate(.cgSize, &sz)!
            let err = AXUIElementSetAttributeValue(
                w, kAXSizeAttribute as CFString, value)
            guard err == .success else {
                throw VerbError(message: "could not resize window (AX error \(err.rawValue))")
            }
            Out.emit(out, human: "resized \(a.localizedName ?? app)[\(index)] to \(width)x\(height)",
                     data: ["action": "window_resize", "app": a.localizedName ?? app,
                            "window": windowRecord(w, index: index)])
        }
    }

    struct Minimize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Minimize a window to the Dock.")
        @Argument(help: "Application name.") var app: String
        @Option(name: .long, help: "Window index (default 0).") var index: Int = 0
        @OptionGroup var out: OutputOptions

        func run() throws {
            try requireAX()
            let (a, w) = try targetWindow(app: app, index: index)
            let err = AXUIElementSetAttributeValue(
                w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            guard err == .success else {
                throw VerbError(message: "could not minimize (AX error \(err.rawValue))")
            }
            Out.emit(out, human: "minimized \(a.localizedName ?? app)[\(index)]",
                     data: ["action": "window_minimize",
                            "app": a.localizedName ?? app, "index": index])
        }
    }

    struct Unminimize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Restore a minimized window from the Dock.")
        @Argument(help: "Application name.") var app: String
        @Option(name: .long, help: "Window index (default 0).") var index: Int = 0
        @OptionGroup var out: OutputOptions

        func run() throws {
            try requireAX()
            let (a, w) = try targetWindow(app: app, index: index)
            let err = AXUIElementSetAttributeValue(
                w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            guard err == .success else {
                throw VerbError(message: "could not restore (AX error \(err.rawValue))")
            }
            Out.emit(out, human: "restored \(a.localizedName ?? app)[\(index)]",
                     data: ["action": "window_unminimize",
                            "app": a.localizedName ?? app, "index": index])
        }
    }

    struct Raise: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Raise a specific window to the front and focus its app.")
        @Argument(help: "Application name.") var app: String
        @Option(name: .long, help: "Window index (default 0).") var index: Int = 0
        @OptionGroup var out: OutputOptions

        func run() throws {
            try requireAX()
            let (a, w) = try targetWindow(app: app, index: index)
            let err = AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            guard err == .success else {
                throw VerbError(message: "could not raise window (AX error \(err.rawValue))")
            }
            a.activate(options: [.activateIgnoringOtherApps])
            Out.emit(out, human: "raised \(a.localizedName ?? app)[\(index)]",
                     data: ["action": "window_raise",
                            "app": a.localizedName ?? app, "index": index])
        }
    }
}
