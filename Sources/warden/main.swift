import Foundation
import CryptoKit

// ===========================================================================
// warden — the mediation spine (Warden epic G0 + G1).
//
// An MCP stdio server that sits between an agent and the `verbs` binary. Every
// tool call an agent makes flows through here: it is classified by mutation
// class (Design Law #3), executed, and recorded to a hash-chained provenance
// log (G1). This is the chokepoint the whole thesis rides on — verbs are the
// governed surface, the warden is the product.
//
// This v0.1 implements the *probe*: mediation + provenance. Policy (G2),
// rewind (G3), approval (G4) and the supervisor UI (G5) are deliberately not
// here yet — see ROADMAP.md. The point of the probe is to run your own agents
// through it and learn whether the ledger is something you reach for.
// ===========================================================================

// MARK: - JSON helpers

func compactJSON(_ obj: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
          let s = String(data: data, encoding: .utf8) else { return "{}" }
    return s
}

/// Deterministic, sorted-key serialization for hashing.
func canonicalJSON(_ obj: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func schemaObject(_ props: [String: [String: Any]], required: [String] = []) -> [String: Any] {
    ["type": "object", "properties": props, "required": required, "additionalProperties": false]
}
func prop(_ type: String, _ desc: String) -> [String: Any] { ["type": type, "description": desc] }

func asString(_ v: Any?) -> String? {
    switch v {
    case let s as String: return s
    case let i as Int: return String(i)
    case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
    case let b as Bool: return b ? "true" : "false"
    default: return nil
    }
}
func asBool(_ v: Any?) -> Bool {
    switch v {
    case let b as Bool: return b
    case let s as String: return s == "true" || s == "1"
    case let i as Int: return i != 0
    default: return false
    }
}

// MARK: - Mutation classification (Design Law #3 / Track S5)

enum MutationClass: String {
    case read                       // idempotent, no state change
    case reversibleWrite = "reversible-write"   // undoable via a recorded compensation
    case snapshotWrite   = "snapshot-write"     // may overwrite; undo needs a pre-image snapshot
    case irreversible                // cannot be undone (ephemeral effects, state loss)
}

// MARK: - Tool registry — verbs exposed as governed MCP tools

struct Tool {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    /// Effective mutation class, computed from the arguments.
    let classify: ([String: Any]) -> MutationClass
    /// How this action would be undone (recorded for G3; not yet auto-captured).
    let undoHint: String?
    /// Build the argv passed to `verbs` (binary + trailing --json added by caller).
    let build: ([String: Any]) throws -> [String]
}

struct ToolError: Error { let message: String }

func req(_ a: [String: Any], _ key: String) throws -> String {
    guard let v = asString(a[key]), !v.isEmpty else { throw ToolError(message: "missing required argument: \(key)") }
    return v
}

let TOOLS: [Tool] = [
    Tool(name: "app_launch",
         description: "Launch an app by name; waits until running.",
         inputSchema: schemaObject(["name": prop("string", "Application name")], required: ["name"]),
         classify: { _ in .reversibleWrite }, undoHint: "app_quit the launched app",
         build: { ["app", "launch", try req($0, "name")] }),
    Tool(name: "app_quit",
         description: "Quit a running app; --force if it refuses.",
         inputSchema: schemaObject(["name": prop("string", "Application name"),
                                    "force": prop("boolean", "Force-terminate if graceful quit is refused")],
                                   required: ["name"]),
         classify: { _ in .irreversible }, undoHint: "app_launch (unsaved state is lost)",
         build: { var v = ["app", "quit", try req($0, "name")]; if asBool($0["force"]) { v.append("--force") }; return v }),
    Tool(name: "app_focus",
         description: "Bring a running app to the front.",
         inputSchema: schemaObject(["name": prop("string", "Application name")], required: ["name"]),
         classify: { _ in .reversibleWrite }, undoHint: "app_focus the previously frontmost app",
         build: { ["app", "focus", try req($0, "name")] }),
    Tool(name: "app_frontmost",
         description: "Report the active application.",
         inputSchema: schemaObject([:]),
         classify: { _ in .read }, undoHint: nil,
         build: { _ in ["app", "frontmost"] }),
    Tool(name: "app_list",
         description: "List running apps; all=true includes background agents.",
         inputSchema: schemaObject(["all": prop("boolean", "Include background/agent apps")]),
         classify: { _ in .read }, undoHint: nil,
         build: { var v = ["app", "list"]; if asBool($0["all"]) { v.append("--all") }; return v }),
    Tool(name: "clipboard_get",
         description: "Read clipboard text.",
         inputSchema: schemaObject([:]),
         classify: { _ in .read }, undoHint: nil,
         build: { _ in ["clipboard", "get"] }),
    Tool(name: "clipboard_set",
         description: "Set clipboard text.",
         inputSchema: schemaObject(["text": prop("string", "Text to place on the clipboard")], required: ["text"]),
         classify: { _ in .reversibleWrite }, undoHint: "clipboard_set the prior clipboard contents",
         build: { ["clipboard", "set", try req($0, "text")] }),
    Tool(name: "open",
         description: "Open a path or any URL scheme with the default or a named app.",
         inputSchema: schemaObject(["target": prop("string", "Path or URL"),
                                    "with": prop("string", "App to open with")], required: ["target"]),
         classify: { _ in .reversibleWrite }, undoHint: "close what was opened",
         build: { var v = ["open", try req($0, "target")]; if let w = asString($0["with"]), !w.isEmpty { v += ["--with", w] }; return v }),
    Tool(name: "reveal",
         description: "Select a file in a Finder window.",
         inputSchema: schemaObject(["path": prop("string", "File path")], required: ["path"]),
         classify: { _ in .read }, undoHint: nil,
         build: { ["reveal", try req($0, "path")] }),
    Tool(name: "trash",
         description: "Move a file to Trash (recoverable).",
         inputSchema: schemaObject(["path": prop("string", "File path")], required: ["path"]),
         classify: { _ in .reversibleWrite }, undoHint: "restore from Trash (trashed_to path in the result)",
         build: { ["trash", try req($0, "path")] }),
    Tool(name: "window_list",
         description: "List windows with geometry (requires Accessibility).",
         inputSchema: schemaObject(["app": prop("string", "Filter to this app")]),
         classify: { _ in .read }, undoHint: nil,
         build: { var v = ["window", "list"]; if let a = asString($0["app"]), !a.isEmpty { v += ["--app", a] }; return v }),
    Tool(name: "window_move",
         description: "Move a window to screen coordinates (requires Accessibility).",
         inputSchema: schemaObject(["app": prop("string", "App"), "x": prop("integer", "X"), "y": prop("integer", "Y"),
                                    "index": prop("integer", "Window index")], required: ["app", "x", "y"]),
         classify: { _ in .reversibleWrite }, undoHint: "window_move back to the prior position",
         build: { var v = ["window", "move", try req($0, "app"), try req($0, "x"), try req($0, "y")]
                  if let i = asString($0["index"]) { v += ["--index", i] }; return v }),
    Tool(name: "window_resize",
         description: "Resize a window (requires Accessibility).",
         inputSchema: schemaObject(["app": prop("string", "App"), "width": prop("integer", "W"), "height": prop("integer", "H"),
                                    "index": prop("integer", "Window index")], required: ["app", "width", "height"]),
         classify: { _ in .reversibleWrite }, undoHint: "window_resize to the prior size",
         build: { var v = ["window", "resize", try req($0, "app"), try req($0, "width"), try req($0, "height")]
                  if let i = asString($0["index"]) { v += ["--index", i] }; return v }),
    Tool(name: "window_minimize",
         description: "Minimize a window to the Dock (requires Accessibility).",
         inputSchema: schemaObject(["app": prop("string", "App"), "index": prop("integer", "Window index")], required: ["app"]),
         classify: { _ in .reversibleWrite }, undoHint: "window_unminimize",
         build: { var v = ["window", "minimize", try req($0, "app")]; if let i = asString($0["index"]) { v += ["--index", i] }; return v }),
    Tool(name: "window_unminimize",
         description: "Restore a minimized window (requires Accessibility).",
         inputSchema: schemaObject(["app": prop("string", "App"), "index": prop("integer", "Window index")], required: ["app"]),
         classify: { _ in .reversibleWrite }, undoHint: "window_minimize",
         build: { var v = ["window", "unminimize", try req($0, "app")]; if let i = asString($0["index"]) { v += ["--index", i] }; return v }),
    Tool(name: "window_raise",
         description: "Raise a window and focus its app (requires Accessibility).",
         inputSchema: schemaObject(["app": prop("string", "App"), "index": prop("integer", "Window index")], required: ["app"]),
         classify: { _ in .reversibleWrite }, undoHint: "raise the previously frontmost window",
         build: { var v = ["window", "raise", try req($0, "app")]; if let i = asString($0["index"]) { v += ["--index", i] }; return v }),
    Tool(name: "notify",
         description: "Post a Notification Center banner.",
         inputSchema: schemaObject(["message": prop("string", "Body text"), "title": prop("string", "Title"),
                                    "subtitle": prop("string", "Subtitle"), "sound": prop("boolean", "Play a sound")],
                                   required: ["message"]),
         classify: { _ in .irreversible }, undoHint: nil,
         build: { var v = ["notify", try req($0, "message")]
                  if let t = asString($0["title"]), !t.isEmpty { v += ["--title", t] }
                  if let s = asString($0["subtitle"]), !s.isEmpty { v += ["--subtitle", s] }
                  if asBool($0["sound"]) { v.append("--sound") }; return v }),
    Tool(name: "darkmode",
         description: "Get or set system appearance: get | on | off | toggle.",
         inputSchema: schemaObject(["action": prop("string", "get | on | off | toggle")], required: ["action"]),
         classify: { asString($0["action"]) == "get" ? .read : .reversibleWrite },
         undoHint: "darkmode to the prior appearance",
         build: { ["darkmode", try req($0, "action")] }),
    Tool(name: "volume",
         description: "Get or set output volume: get | mute | unmute | 0-100.",
         inputSchema: schemaObject(["action": prop("string", "get | mute | unmute | 0-100")], required: ["action"]),
         classify: { asString($0["action"]) == "get" ? .read : .reversibleWrite },
         undoHint: "volume to the prior level",
         build: { ["volume", try req($0, "action")] }),
    Tool(name: "say",
         description: "Speak text aloud (blocks until finished).",
         inputSchema: schemaObject(["text": prop("string", "Text to speak"), "voice": prop("string", "Voice name")], required: ["text"]),
         classify: { _ in .irreversible }, undoHint: nil,
         build: { var v = ["say", try req($0, "text")]; if let vo = asString($0["voice"]), !vo.isEmpty { v += ["--voice", vo] }; return v }),
    Tool(name: "screenshot",
         description: "Capture the screen to a file (requires Screen Recording).",
         inputSchema: schemaObject(["path": prop("string", "Output .png path"),
                                    "main_display": prop("boolean", "Capture the main display only")], required: ["path"]),
         classify: { _ in .snapshotWrite }, undoHint: "delete the created file (may have overwritten an existing path)",
         build: { var v = ["screenshot", try req($0, "path")]; if asBool($0["main_display"]) { v.append("--main-display") }; return v }),
]

let TOOL_BY_NAME = Dictionary(uniqueKeysWithValues: TOOLS.map { ($0.name, $0) })

// MARK: - Locate the verbs binary

func verbsBinary() -> String {
    if let env = ProcessInfo.processInfo.environment["WARDEN_VERBS_BIN"], !env.isEmpty { return env }
    let selfDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let sibling = selfDir.appendingPathComponent("verbs").path
    if FileManager.default.isExecutableFile(atPath: sibling) { return sibling }
    for p in ["/usr/local/bin/verbs", "/opt/homebrew/bin/verbs"] {
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return "verbs" // fall back to PATH resolution via /usr/bin/env
}

func runVerb(_ argv: [String]) -> (stdout: String, stderr: String, code: Int32) {
    let p = Process()
    let bin = verbsBinary()
    if bin.contains("/") {
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = argv
    } else {
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [bin] + argv
    }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err
    do { try p.run() } catch {
        return ("", "could not launch verbs (\(bin)): \(error.localizedDescription)", 2)
    }
    p.waitUntilExit()
    let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let se = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (so.trimmingCharacters(in: .whitespacesAndNewlines),
            se.trimmingCharacters(in: .whitespacesAndNewlines), p.terminationStatus)
}

// MARK: - Provenance log (G1: W3/W5/W6)

final class Provenance {
    let url: URL
    private var prevHash = "genesis"
    private var seq = 0
    private let iso = ISO8601DateFormatter()

    init() {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["WARDEN_DIR"], !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warden")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("provenance.jsonl")
        // Resume the chain from the last record if the log exists.
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let lines = text.split(whereSeparator: \.isNewline)
            if let last = lines.last, let d = last.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                prevHash = (obj["hash"] as? String) ?? prevHash
                seq = ((obj["seq"] as? Int) ?? 0) + 1
            }
        }
    }

    @discardableResult
    func record(agent: String, tool: String, arguments: [String: Any], argv: [String],
                mutationClass: String, undoHint: String?, exit: Int32, durationMs: Int) -> String {
        var rec: [String: Any] = [
            "ts": iso.string(from: Date()),
            "seq": seq,
            "agent": agent,
            "tool": tool,
            "arguments": arguments,
            "argv": argv,
            "mutation_class": mutationClass,
            "undo_hint": undoHint ?? NSNull(),
            "exit": Int(exit),
            "ok": exit == 0,
            "duration_ms": durationMs,
            "prev_hash": prevHash,
        ]
        let hash = sha256Hex(canonicalJSON(rec))
        rec["hash"] = hash
        if let line = String(data: canonicalJSON(rec), encoding: .utf8) {
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile(); fh.write(Data((line + "\n").utf8)); try? fh.close()
            } else {
                try? (line + "\n").data(using: .utf8)?.write(to: url)
            }
        }
        prevHash = hash; seq += 1
        return hash
    }
}

// MARK: - MCP stdio server

let PROTOCOL_VERSION = "2024-11-05"
var clientName = "unknown"
let provenance = Provenance()

func send(_ obj: [String: Any]) {
    print(compactJSON(obj)); fflush(stdout)
}
func reply(id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}
func replyError(id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}
func log(_ s: String) { FileHandle.standardError.write(Data("[warden] \(s)\n".utf8)) }

func handleToolsCall(id: Any, params: [String: Any]) {
    guard let name = params["name"] as? String, let tool = TOOL_BY_NAME[name] else {
        replyError(id: id, code: -32602, message: "unknown tool: \(params["name"] ?? "nil")")
        return
    }
    let args = (params["arguments"] as? [String: Any]) ?? [:]
    let cls = tool.classify(args)
    let argv: [String]
    do { argv = try tool.build(args) } catch let e as ToolError {
        _ = provenance.record(agent: clientName, tool: name, arguments: args, argv: [],
                              mutationClass: cls.rawValue, undoHint: tool.undoHint, exit: 64, durationMs: 0)
        reply(id: id, result: ["content": [["type": "text", "text": "usage error: \(e.message)"]], "isError": true])
        return
    } catch { replyError(id: id, code: -32603, message: "\(error)"); return }

    let full = argv + ["--json"]
    let started = Date()
    let (out, err, code) = runVerb(full)
    let ms = Int(Date().timeIntervalSince(started) * 1000)
    provenance.record(agent: clientName, tool: name, arguments: args, argv: ["verbs"] + full,
                      mutationClass: cls.rawValue, undoHint: tool.undoHint, exit: code, durationMs: ms)
    log("\(name) [\(cls.rawValue)] exit=\(code) \(ms)ms")

    if code == 0 {
        var result: [String: Any] = ["content": [["type": "text", "text": out.isEmpty ? "ok" : out]], "isError": false]
        if let d = out.data(using: .utf8), let structured = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            result["structuredContent"] = structured
        }
        reply(id: id, result: result)
    } else {
        let msg = err.isEmpty ? "verbs exited \(code)" : err
        reply(id: id, result: ["content": [["type": "text", "text": "\(msg) (exit \(code))"]], "isError": true])
    }
}

func serve() {
    log("serving MCP over stdio; verbs=\(verbsBinary()); provenance=\(provenance.url.path)")
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty { continue }
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = msg["method"] as? String else { continue }
        let id = msg["id"]
        let params = (msg["params"] as? [String: Any]) ?? [:]

        switch method {
        case "initialize":
            if let ci = params["clientInfo"] as? [String: Any], let n = ci["name"] as? String { clientName = n }
            let pv = (params["protocolVersion"] as? String) ?? PROTOCOL_VERSION
            reply(id: id ?? NSNull(), result: [
                "protocolVersion": pv,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "warden", "version": "0.1.0"],
            ])
        case "notifications/initialized", "initialized":
            break // notification, no reply
        case "ping":
            if let id { reply(id: id, result: [:]) }
        case "tools/list":
            let tools = TOOLS.map { t -> [String: Any] in
                ["name": t.name, "description": t.description, "inputSchema": t.inputSchema]
            }
            reply(id: id ?? NSNull(), result: ["tools": tools])
        case "tools/call":
            if let id { handleToolsCall(id: id, params: params) }
        default:
            if let id { replyError(id: id, code: -32601, message: "method not found: \(method)") }
        }
    }
}

// MARK: - Entry point

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case nil, "serve":
    serve()
case "tools":
    // Print the governed tool registry with mutation classes (human/debug view).
    for t in TOOLS {
        let cls = t.classify([:]).rawValue
        print("\(t.name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(cls.padding(toLength: 17, withPad: " ", startingAt: 0)) \(t.description)")
    }
case "log":
    // W7: basic provenance query. `warden log [--json]`.
    let asJSON = args.contains("--json")
    guard let text = try? String(contentsOf: provenance.url, encoding: .utf8) else {
        FileHandle.standardError.write(Data("no provenance log at \(provenance.url.path)\n".utf8)); exit(1)
    }
    for line in text.split(whereSeparator: \.isNewline) {
        if asJSON { print(line); continue }
        guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
        let seq = o["seq"] as? Int ?? -1
        let ts = o["ts"] as? String ?? ""
        let agent = o["agent"] as? String ?? "?"
        let tool = o["tool"] as? String ?? "?"
        let cls = o["mutation_class"] as? String ?? "?"
        let ok = (o["ok"] as? Bool ?? false) ? "ok " : "FAIL"
        print("#\(seq)  \(ts)  \(ok)  \(agent)  \(tool) [\(cls)]")
    }
case "--help", "-h", "help":
    print("""
    warden — mediation spine for macos-verbs (Warden epic G0/G1)

    USAGE:
      warden [serve]      Run the MCP stdio server (default). Point your agent here.
      warden tools        List the governed tool registry with mutation classes.
      warden log [--json] Show the hash-chained provenance log (~/.warden/provenance.jsonl).
      warden help         This help.

    ENV:
      WARDEN_VERBS_BIN    Path to the `verbs` binary (else: sibling, /usr/local/bin, PATH).
      WARDEN_DIR          Provenance dir (default: ~/.warden).
    """)
default:
    FileHandle.standardError.write(Data("unknown command: \(args[0]) (try `warden help`)\n".utf8)); exit(64)
}
