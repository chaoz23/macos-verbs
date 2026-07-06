import AppKit
import ArgumentParser
import Foundation

private func isURLTarget(_ target: String) -> Bool {
    // Let callers force path interpretation for filenames that contain a
    // colon, while accepting every RFC 3986 scheme (mailto:, tel:, custom
    // application schemes), not only URLs that contain ://.
    let pathPrefixes = ["/", "./", "../", "~"]
    guard !pathPrefixes.contains(where: target.hasPrefix) else { return false }
    return target.range(
        of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
        options: .regularExpression
    ) != nil
}

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a file or URL, optionally with a specific application.")
    @Argument(help: "File path or URL.") var target: String
    @Option(name: .long, help: "Application to open it with, e.g. \"Preview\".")
    var with: String?
    @OptionGroup var out: OutputOptions

    func run() throws {
        var args: [String] = []
        if let with { args += ["-a", with] }
        // Resolve paths; pass absolute URLs of any scheme through untouched.
        let isURL = isURLTarget(target)
        let resolved = isURL
            ? target
            : URL(fileURLWithPath: (target as NSString).expandingTildeInPath).path
        if !isURL && !FileManager.default.fileExists(atPath: resolved) {
            throw VerbError(message: "no such file: \(resolved)")
        }
        args.append(resolved)
        try shell("/usr/bin/open", args)
        Out.emit(out, human: "opened \(target)" + (with.map { " with \($0)" } ?? ""),
                 data: ["action": "open", "target": resolved,
                        "with": with ?? NSNull()])
    }
}

struct RevealCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reveal",
        abstract: "Reveal a file in a new Finder window, selected.")
    @Argument(help: "File or folder path.") var path: String
    @OptionGroup var out: OutputOptions

    func run() throws {
        let resolved = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw VerbError(message: "no such file: \(resolved)")
        }
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: resolved)])
        Out.emit(out, human: "revealed \(resolved)",
                 data: ["action": "reveal", "path": resolved])
    }
}

struct TrashCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trash",
        abstract: "Move a file or folder to the Trash (recoverable, unlike rm).")
    @Argument(help: "File or folder path.") var path: String
    @OptionGroup var out: OutputOptions

    func run() throws {
        let resolved = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw VerbError(message: "no such file: \(resolved)")
        }
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: resolved), resultingItemURL: &trashed)
        } catch {
            throw VerbError.system("trash failed: \(error.localizedDescription)")
        }
        Out.emit(out, human: "trashed \(resolved)",
                 data: ["action": "trash", "path": resolved,
                        "trashed_to": trashed?.path ?? NSNull()])
    }
}
