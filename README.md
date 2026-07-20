# macos-verbs

Deterministic macOS actions for AI agents (and humans at a shell), in one
self-contained binary. `verbs` gives an agent the system-level actions it
otherwise has to improvise with brittle `osascript` one-liners or reach for
full GUI automation to get.

```
verbs app focus Safari          verbs clipboard get
verbs app frontmost --json      verbs notify "Build done" --title CI
verbs darkmode toggle           verbs reveal ~/report.pdf
verbs volume 40                 verbs trash ~/old-draft.txt
verbs open mailto:agent@example.com
```

Most verbs need no accessibility permissions or TCC prompts. The permission-
gated exceptions are documented below.

## Install

```bash
git clone https://github.com/chaoz23/macos-verbs
cd macos-verbs
./install.sh                              # builds + installs verbs and warden to /usr/local/bin
# or a user-local prefix, no sudo:
PREFIX="$HOME/.local/bin" ./install.sh
```

Or by hand: `swift build -c release && cp .build/release/{verbs,warden} /usr/local/bin/`.

Requires macOS 13+ and Swift 5.9+ (Command Line Tools are enough — no Xcode).

## Test

The project uses shell-based contract tests because both binaries are executable
tools. Run the same checks as CI with:

```bash
bash scripts/test.sh
```

`swift test` is not the test entrypoint for this repo; SwiftPM will report that
there are no test targets.

## Verbs

| Verb | What it does |
|---|---|
| `app launch <name>` | Launch by name (LaunchServices resolution), wait until running |
| `app quit <name> [--force]` | Graceful terminate; `--force` if refused |
| `app focus <name>` | Bring a running app to the front |
| `app frontmost` | Print the active application |
| `app list [--all]` | Running apps (`--all` includes background agents) |
| `clipboard get` | Print clipboard text (exit 1 if none) |
| `clipboard set [text]` | Set from argument or stdin |
| `open <path-or-url> [--with <app>]` | Open a path or any URL scheme with the default or named app |
| `reveal <path>` | Select the file in a Finder window |
| `trash <path>` | Move to Trash — recoverable, unlike `rm` |
| `window list [--app <name>]` | Windows with title, geometry, minimized state |
| `window move <app> <x> <y> [--index]` | Move a window to screen coordinates |
| `window resize <app> <w> <h> [--index]` | Resize a window |
| `window minimize / unminimize <app> [--index]` | Dock a window / restore it |
| `window raise <app> [--index]` | Raise a specific window and focus its app |
| `notify <msg> [--title] [--subtitle] [--sound]` | Notification Center banner |
| `darkmode get\|on\|off\|toggle` | System appearance |
| `volume get\|mute\|unmute\|0-100` | Output volume |
| `say <text> [--voice]` | Speak aloud (blocks until done) |
| `screenshot <path> [--main-display]` | Capture screen to file |

## For agents

- **`--json` on every verb.** One JSON object per invocation on stdout,
  always containing `"ok": true` and an `"action"` discriminator. Errors are
  text on stderr — stdout stays parseable.
- **Exit codes carry the semantics:** `0` success · `1` actionable failure
  (app not running, file missing, clipboard empty) · `2` system error ·
  `64` usage error. Branch on the code without parsing anything.
- **Idempotent reads, explicit writes.** `get`-style verbs never change
  state; `trash` is used instead of delete so every destructive action is
  recoverable.
- **`tool.json`** at the repo root describes the full surface
  machine-readably.

Example — an agent confirming what the user is looking at:

```
$ verbs app frontmost --json
{"action":"frontmost","app":{"active":true,"bundle_id":"com.apple.Safari",
 "hidden":false,"name":"Safari","pid":4821},"ok":true}
```

## Permissions (TCC)

Everything works with zero permission grants, except:

| Verb | Requirement |
|---|---|
| `darkmode` | First use prompts once to allow controlling System Events (Automation). Subsequent calls are silent. |
| `screenshot` | Full screen content requires Screen Recording permission for the *calling* app (your terminal / agent host). Without it the verb fails with exit 1 and a clear message pointing at System Settings. |
| `window *` | Requires the **Accessibility** permission for the calling app (System Settings → Privacy & Security → Accessibility). Every window verb checks first and fails with exit 1 + guidance if ungranted — never silently, never mysteriously. |

The permission tiers are deliberate: an agent can use every tier-0 verb
unattended out of the box, and each escalation (`window`) is a single
explicit human grant with a clear error message pointing at it.

## Design notes

- Native `NSWorkspace`/`NSPasteboard`/`NSRunningApplication` calls where
  macOS exposes an API; `osascript` only where it doesn't (notifications,
  appearance, volume). App-name resolution goes through `open -a` —
  LaunchServices' own resolver, the most reliable name→app mapping there is.
- URL detection follows RFC-style schemes, including `mailto:`, `tel:`, and
  custom application schemes. Prefix a colon-containing filename with `./`
  to force path interpretation.
- State reported after a write comes from a **fresh read**, not the write's
  return value (the AppleScript `set` return was observed stale on
  back-to-back dark-mode toggles).
- Single static binary, no runtime dependencies, ~1s cold build check.

## warden — the governance layer (preview)

`verbs` gives an agent deterministic actions. **`warden`** governs them. It's a
second binary in this repo: an MCP stdio server that sits between an agent and
`verbs`, so every action an agent takes flows through one chokepoint that
classifies it, executes it, and records it to a hash-chained provenance log.

```bash
swift build -c release
./.build/release/warden serve          # MCP stdio server — point your agent here
./.build/release/warden tools          # the governed registry + mutation classes
./.build/release/warden log            # the hash-chained provenance ledger (~/.warden)
```

Each of the verbs is exposed as a typed MCP tool tagged with a **mutation
class** — `read` / `reversible-write` / `snapshot-write` / `irreversible` — and,
for reversible actions, the compensating action needed to undo it. Every call is
appended to `~/.warden/provenance.jsonl` with agent identity, arguments, outcome,
timing, and a SHA-256 hash chained to the prior record (tamper-evident lineage).

This is the first increment (G0 mediation + G1 provenance) of a larger bet: as
the Mac's primary user shifts from human to agent, the durable primitive isn't
more actions — it's the **reversible, auditable governance envelope** around
them. Policy/attenuation, `warden rewind`, approval gates, a supervisor UI, and
cross-surface adapters are the road ahead. See [ROADMAP.md](ROADMAP.md).

To wire it into an MCP client, run `warden serve` as the command (it speaks
newline-delimited JSON-RPC over stdio). It finds `verbs` as a sibling binary, at
`/usr/local/bin`, or on `PATH` — or set `WARDEN_VERBS_BIN`.

## License

Apache-2.0
