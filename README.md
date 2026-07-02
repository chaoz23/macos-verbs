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
```

No accessibility permissions required — every v1 verb works without TCC
prompts (two documented exceptions below).

## Install

```bash
git clone https://github.com/chaoz23/macos-verbs
cd macos-verbs
swift build -c release
cp .build/release/verbs /usr/local/bin/
```

Requires macOS 13+ and Swift 5.9+ (Command Line Tools are enough — no Xcode).

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
| `open <path-or-url> [--with <app>]` | Open with default or named app |
| `reveal <path>` | Select the file in a Finder window |
| `trash <path>` | Move to Trash — recoverable, unlike `rm` |
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

Deliberately **out of v1**: window management (move/resize/list) — it
requires the Accessibility permission, which complicates unattended agent
use. It's the natural v2 once the core proves out.

## Design notes

- Native `NSWorkspace`/`NSPasteboard`/`NSRunningApplication` calls where
  macOS exposes an API; `osascript` only where it doesn't (notifications,
  appearance, volume). App-name resolution goes through `open -a` —
  LaunchServices' own resolver, the most reliable name→app mapping there is.
- State reported after a write comes from a **fresh read**, not the write's
  return value (the AppleScript `set` return was observed stale on
  back-to-back dark-mode toggles).
- Single static binary, no runtime dependencies, ~1s cold build check.

## License

Apache-2.0
