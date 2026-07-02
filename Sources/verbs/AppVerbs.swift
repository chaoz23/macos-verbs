import AppKit
import ArgumentParser
import Foundation

struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Launch, quit, focus, and inspect applications.",
        subcommands: [Launch.self, Quit.self, Focus.self, Frontmost.self, List.self]
    )

    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Launch an application by name (waits until it is running).")
        @Argument(help: "Application name, e.g. \"Safari\".") var name: String
        @OptionGroup var out: OutputOptions

        func run() throws {
            // /usr/bin/open -a uses LaunchServices' own name resolution —
            // the most reliable name->app mapping available.
            try run_open(name)
            // Poll briefly so "launch" means launched, not merely requested.
            for _ in 0..<50 {
                if let app = runningApp(named: name) {
                    Out.emit(out, human: "launched \(app.localizedName ?? name)",
                             data: ["action": "launch", "app": appRecord(app)])
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            Out.emit(out, human: "launch requested: \(name)",
                     data: ["action": "launch", "app": ["name": name], "confirmed": false])
        }

        private func run_open(_ name: String) throws {
            do { try shell("/usr/bin/open", ["-a", name]) }
            catch { throw VerbError(message: "no application named \"\(name)\"") }
        }
    }

    struct Quit: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Quit a running application (graceful terminate).")
        @Argument(help: "Application name or bundle id.") var name: String
        @Flag(name: .long, help: "Force-quit if graceful terminate is refused.")
        var force = false
        @OptionGroup var out: OutputOptions

        func run() throws {
            guard let app = runningApp(named: name) else {
                throw VerbError(message: "\"\(name)\" is not running")
            }
            let ok = force ? app.forceTerminate() : app.terminate()
            guard ok else {
                throw VerbError(message: "\(name) refused to terminate (try --force)")
            }
            Out.emit(out, human: "quit \(app.localizedName ?? name)",
                     data: ["action": "quit", "app": appRecord(app), "forced": force])
        }
    }

    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bring a running application to the front.")
        @Argument(help: "Application name or bundle id.") var name: String
        @OptionGroup var out: OutputOptions

        func run() throws {
            guard let app = runningApp(named: name) else {
                throw VerbError(message: "\"\(name)\" is not running")
            }
            guard app.activate(options: [.activateIgnoringOtherApps]) else {
                throw VerbError(message: "could not activate \(name)")
            }
            Out.emit(out, human: "focused \(app.localizedName ?? name)",
                     data: ["action": "focus", "app": appRecord(app)])
        }
    }

    struct Frontmost: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the frontmost (active) application.")
        @OptionGroup var out: OutputOptions

        func run() throws {
            guard let app = NSWorkspace.shared.frontmostApplication else {
                throw VerbError(message: "no frontmost application (no GUI session?)")
            }
            Out.emit(out, human: app.localizedName ?? "?",
                     data: ["action": "frontmost", "app": appRecord(app)])
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List running applications (regular activation policy only).")
        @Flag(name: .long, help: "Include background/agent apps.") var all = false
        @OptionGroup var out: OutputOptions

        func run() throws {
            let apps = NSWorkspace.shared.runningApplications.filter {
                all || $0.activationPolicy == .regular
            }
            let records = apps.map(appRecord)
            let names = apps.compactMap { $0.localizedName }.sorted()
            Out.emit(out, human: names.joined(separator: "\n"),
                     data: ["action": "list", "count": records.count, "apps": records])
        }
    }
}
