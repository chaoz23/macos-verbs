import ArgumentParser

@main
struct Verbs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verbs",
        abstract: "macOS verbs for agents — deterministic system actions with JSON output and diff(1)-style exit codes.",
        discussion: """
        Every verb accepts --json for a machine-readable result object.
        Exit codes: 0 = success, 1 = actionable failure (not running, \
        not found), 2 = system error, 64 = usage error.
        """,
        version: "0.2.0",
        subcommands: [
            AppCommand.self,
            WindowCommand.self,
            ClipboardCommand.self,
            OpenCommand.self,
            RevealCommand.self,
            TrashCommand.self,
            NotifyCommand.self,
            DarkmodeCommand.self,
            VolumeCommand.self,
            SayCommand.self,
            ScreenshotCommand.self,
        ]
    )
}
