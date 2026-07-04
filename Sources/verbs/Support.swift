import AppKit
import ArgumentParser
import Foundation

// ---------------------------------------------------------------------------
// Output contract (agent-facing):
//   - every verb accepts --json; JSON goes to stdout, one object per invocation
//   - human output is a single short line unless the verb is a list
//   - errors are text on stderr; the exit code carries the semantics:
//       0 = success, 1 = actionable failure (not found, not running, ...),
//       2 = system error, 64 = usage error (ArgumentParser default)
// ---------------------------------------------------------------------------

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit a JSON object instead of human text.")
    var json = false
}

enum Out {
    static func emit(_ opts: OutputOptions, human: String, data: [String: Any]) {
        if opts.json {
            var payload = data
            payload["ok"] = true
            print(Self.jsonString(payload))
        } else {
            print(human)
        }
    }

    static func jsonString(_ dict: [String: Any]) -> String {
        guard
            let bytes = try? JSONSerialization.data(
                withJSONObject: dict, options: [.sortedKeys]),
            let s = String(data: bytes, encoding: .utf8)
        else { return "{\"ok\":false,\"error\":\"json encoding failed\"}" }
        return s
    }
}

enum VerbErrorKind: Int32 {
    case actionable = 1
    case system = 2
}

/// Runtime failure with the agent-facing exit classification attached.
struct VerbError: Error, CustomStringConvertible {
    let message: String
    let kind: VerbErrorKind

    init(message: String, kind: VerbErrorKind = .actionable) {
        self.message = message
        self.kind = kind
    }

    static func system(_ message: String) -> VerbError {
        VerbError(message: message, kind: .system)
    }

    var description: String { message }
}

// ---------------------------------------------------------------------------
// Process helpers
// ---------------------------------------------------------------------------

@discardableResult
func shell(_ tool: String, _ args: [String], stdin: String? = nil) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err
    if let stdin {
        let inPipe = Pipe()
        p.standardInput = inPipe
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        inPipe.fileHandleForWriting.closeFile()
    }
    do {
        try p.run()
    } catch {
        throw VerbError.system(
            "could not start \(tool): \(error.localizedDescription)")
    }
    p.waitUntilExit()
    let stdout = String(
        data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if p.terminationStatus != 0 {
        let stderr = String(
            data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw VerbError.system(stderr.isEmpty
            ? "\(tool) exited \(p.terminationStatus)"
            : stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Run an AppleScript snippet and return its result string.
@discardableResult
func osascript(_ script: String) throws -> String {
    try shell("/usr/bin/osascript", ["-e", script])
}

/// Escape a string for embedding in a double-quoted AppleScript literal.
func appleScriptQuote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

// ---------------------------------------------------------------------------
// App lookup
// ---------------------------------------------------------------------------

/// Find a running application by (case-insensitive) name or bundle id.
func runningApp(named query: String) -> NSRunningApplication? {
    let q = query.lowercased()
    return NSWorkspace.shared.runningApplications.first {
        $0.localizedName?.lowercased() == q
            || $0.bundleIdentifier?.lowercased() == q
    }
}

func appRecord(_ app: NSRunningApplication) -> [String: Any] {
    [
        "name": app.localizedName ?? "",
        "bundle_id": app.bundleIdentifier ?? "",
        "pid": app.processIdentifier,
        "active": app.isActive,
        "hidden": app.isHidden,
    ]
}
