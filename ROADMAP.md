# Roadmap — Warden: the open, neutral, reversible desktop primitive for a 99%-agent Mac

> **The bet.** The Mac's primary user becomes the agent; the human collapses to a ~1% supervisor.
> We design for that machine now, accepting the present is the wrong-shaped world to validate
> against. We build to be *correct and canonical at the tipping point*, not maximally adopted today.

**North star:** *the open, neutral, reversible desktop primitive the agent-governance industry
forgot to build — because no one gets paid to protect the individual. Verbs are the bridge;
the warden is the destination; determinism and reversibility are the physics.*

This roadmap **supersedes verb-count expansion.** Coverage is a decaying actuation bridge that
Apple (App Intents) and a red ocean of enterprise MCP gateways are already commoditizing. We do
not fight there. Our territory is the intersection none of them serve because it has no compliance
buyer: **local + reversible + desktop-actuation, user-side, individual.**

## Design laws (every change must pass all five)
1. **Agent-primary, human-supervisory.** Default consumer is an agent (MCP or shell). The human
   surface is see / approve / rewind / kill — never operation.
2. **Determinism is a gate.** No action we can't make typed + verifiable *without re-perception*.
3. **Reversible + bounded by default.** Every mutating action is simulable, reversible-or-snapshotted,
   and blast-radius-limited. "Trash, not rm" is law.
4. **Governance over coverage.** Verbs are the demo surface; the warden is the product.
5. **OSS · neutral · local as identity.** A governor you can't inspect can't be trusted;
   standards win open; neutrality must be unowned.

Sizing: S ≈ hours · M ≈ 1–3 days · L ≈ ~1 week · XL ≈ multi-week / open-ended.

---

## Track S — make the verbs *governable* (fold-in, not expansion)
- **S1** — Structured JSON errors: in `--json`, errors emit `{"ok":false,"error":{kind,message,exit}}`. **[S]**
- **S2** — Native paths where feasible (CoreAudio volume first); retire the flakiest osascript calls. **[S–M]**
- **S3** — `verbs doctor` / `permissions --json`: machine-readable TCC state per tier. **[S]**
- **S4** — `wait`: deterministic sync primitive, zero new permissions. **[M]**
- **S5** — Reversibility descriptors: every verb declares permission tier, mutation class
  (`read`/`reversible-write`/`snapshot-write`/`irreversible`), and the compensating action. **[M]** ✅ *modeled in the warden registry*
- **S6** — `verbs mcp` native mode so the warden needn't shell out. **[M]**

## G0 — Mediation spine *(the probe — build first, alone)* ✅ **landed (v0.1)**
- **W1** — MCP proxy skeleton (stdio JSON-RPC, northbound to agent). ✅
- **W2** — Front macos-verbs as the first governed surface (verbs → MCP tools). ✅
- **W3** — Universal call log (append-only JSONL). ✅
- **W4** — "Point your agent at me" (stdio server + config snippet). ✅

## G1 — Provenance / decision lineage  *(partially landed)*
- **W5** — Structured lineage record (agent · tool · args · argv · class · outcome · duration · ts). ✅
- **W6** — Tamper-evident log (hash-chained entries). ✅
- **W7** — `warden log` query (filter by agent/tool/time/outcome). ✅ *(basic)*
- **W8** — Agent identity (captured from MCP `initialize` clientInfo; reject-anonymous option). ◧ *(capture done; enforcement TODO)*

> **GATE after G1:** run your own agents through G0+G1. Do you ever *read* the log? Tune anything?
> If the ledger is something you reach for, the thesis is live → build G2/G3. If you never look,
> fold — for the price of two weekends.

## G2 — Policy & capability attenuation *(the real IP)*
- **W9** — Policy engine (deny-by-default; per-agent allow/deny by tool). **[L]**
- **W10** — Scoped constraints (path scopes, argument constraints). **[L]**
- **W11** — Rate limits / quotas (N destructive ops per window per agent). **[M]**
- **W12** — Time-boxed grants (TTL, expiry). **[M]**
- **W13** — Policy file + hot-reload. **[S]**

## G3 — Reversibility / rewind *(the biggest white space — the field is all detective/preventive)*
- **W14** — Mutation classification (consumes S5 descriptors). **[M]** ◧ *(classes modeled; capture TODO)*
- **W15** — Compensation journal (record the inverse for every reversible write). **[L]**
- **W16** — Snapshot hook (stash a copy before snapshot-writes). **[L]**
- **W17** — `warden rewind` (undo the last N actions / a session). **[L]**
- **W18** — Irreversible gate (blocked without an approval token → G4). **[M]**

## G4 — Approval gates & blast-radius *(the 1% human moment, as a queue)*
- **W19** — Approval queue (gated actions pause and surface). **[L]**
- **W20** — Dry-run / simulate (projected effect without executing). **[L]**
- **W21** — Blast-radius caps + global kill switch. **[M]**

## G5 — Supervisor legibility *(rebuild the human surface for oversight)*
- **W22** — Local TUI/dashboard (live feed, per-agent activity, exception + approval queue). **[L]**
- **W23** — Anomaly flags (spikes in destructive ops, new tools, off-scope attempts). **[M]**
- **W24** — Kill switch + session controls from the UI. **[S]**

## G6 — Cross-surface adapters *(breadth = the only real moat)*
- **W25** — Govern arbitrary downstream MCP servers (multiplex many). **[L]**
- **W26** — Shell/exec adapter (govern general command execution). **[L]**
- **W27** — App Intents bridge (govern Apple's sanctioned actions through the same envelope). **[XL, gated on Apple]**
- **W28** — Filesystem watch (mediation completeness — detect out-of-band mutation). **[L]**

## G7 — Cross-platform & hardening
- **W29** — Linux build (agents aren't Mac-only; the anti-sherlock hedge). **[L]**
- **W30** — Golden tests across mediation + policy + rewind. **[L]**
- **W31** — Threat model + signed releases (the chokepoint is the biggest attack surface). **[M]**
- **W32** — MCP registry listing + `tool.json` for the warden itself. **[S]**

---

## Sequencing
```
S1–S5 ─┐ (verbs → governable, parallel)
G0 ────┼─▶ G1 ─▶ [GATE] ─▶ G2 ∥ G3 ─▶ G4 ─▶ G5 ─▶ G6 ─▶ G7
       │                      policy  rewind
S6 (opt)┘
```

## Falsifiability — kill-signals for the *thesis*
Any one firing means fold early:
- **Trajectory stalls** — agent share of real desktop actuation plateaus low; the 99% never comes.
- **Native de-rasterization outruns us** — App Intents / an agent-OS covers the surface before the 99% arrives.
- **The neutral slot closes** — the platform ships a user-side governor, or the OSS-neutral position gets absorbed.
