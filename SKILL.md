---
name: prism
description: >-
  Dispatch multiple independent agents to answer the SAME complete question
  from different analytical lenses, then synthesize. Reach for this by default,
  without waiting to be asked, when redundant cross-model judgment could change
  the decision: ambiguous architecture/design tradeoffs, high-stakes or
  hard-to-reverse changes, competing root-cause hypotheses, or
  failure-mode-sensitive reviews — and whenever you would otherwise spawn 2+
  independent reviewers for one question. Skip for trivial lookups, deterministic
  transforms, routine small edits, mechanical syncs, and single-correct-answer
  tasks. With no leading number, autonomously decide N and gpt-pro from
  the question every time (N=1 is the bottom-rung anchor, never a lazy default);
  with an explicit number (e.g. `prism 2 1`), honor it verbatim and skip
  auto-sizing. There is no reasoning-effort knob. Scale above the anchor only
  when decision risk justifies the 7N-agent cost.
user-invocable: true
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - Grep
  - Glob
  - Skill
---

# Prism

**Claude-only.** If `ANTHROPIC_BASE_URL` contains `deepseek`, `xiaomimimo`, or `z.ai`, this skill is unavailable — stop and tell the user: "prism is Claude-only; a non-Claude session cannot orchestrate other models." Prism dispatches parallax via [[relay]], which itself refuses from non-Claude sessions.

Prism sends the **same complete question** to multiple independent agents. Each agent answers the **entire question end-to-end**. The only thing that changes between agents is the **lens**: what they prioritize and what tradeoffs they weigh more heavily.

## Core Principle

**Prism is redundancy, not division of labor.** Every agent gets the full question, full scope, and full deliverable. The lens changes **emphasis**, not **coverage**. If agents own different files, sections, or outputs, that is division of labor, not Prism.

Convergence across diverse lenses is high-confidence signal; divergence surfaces tradeoffs that need explicit resolution.

## Structure

| Tier | Tool | Role |
|------|------|------|
| Self | (none) | Your own analysis while agents run |
| Subagents | **Agent** | Same-model agents (Claude), one Agent call each |
| **Parallax — Codex** | **Bash** (`relay call --to codex`) | Cross-model agents via relay to GPT-5.5 (effort always `xhigh`) |
| **Parallax — Grok Build** | **Bash** (`relay call --to grok-build`) | Cross-model agents via relay to xAI Grok Build (effort always `high`) |
| **Parallax — Grok Composer** | **Bash** (`relay call --to grok-composer`) | Cross-model agents via relay to xAI Composer 2.5 (fast; no effort knob) |
| **Parallax — DeepSeek** | **Bash** (`relay call --to deepseek`) | Cross-model agents via relay to DeepSeek V4 Pro |
| **Parallax — MiMo** | **Bash** (`relay call --to mimo`) | Cross-model agents via relay to Xiaomi MiMo-V2.5-Pro |
| **Parallax — GLM** | **Bash** (`relay call --to glm`) | Cross-model agents via relay to Zhipu/z.ai GLM-5.2 (pinned to `max` reasoning, like DeepSeek) |
| **GPT-Pro (opt-in)** | **Bash** (`gpt-pro < prompt.md`) | Additive ChatGPT Pro Extended lenses via [[gpt-pro-relay]] — opt-in **Deep-Reasoning / Research-Grounded** tier; launcher **composed by `prepare`**, fired orchestrator-direct; **not** a relay peer / not in the parallax fan; slow + quota-burning; off by default (see GPT-Pro tier) |

**Symmetric baseline — all seven models at `N=1`** (the bottom-rung anchor, not a fire-without-thinking default): self + 1 Claude subagent + 1 each of Codex, Grok Build, Grok Composer, DeepSeek, MiMo, GLM = **7 dispatched + self** (8 perspectives). This shape is what an autonomous no-config decision *lands on* for the minimal case and what an explicit-but-partial config *fills omitted dimensions from* — a bare invocation always routes through the decision procedure (see **Choosing N and gpt-pro**) and never emits this by shortcut. Required dispatch: **`N` Agent calls + 1 backgrounded `prism-launch parallax` call that fans out the `6N` relay calls** (manual fallback: `6N` separate Bash relay calls). Self does not count. There is **no reasoning-effort choice** — Codex always runs at `xhigh`, Grok Build always at `high`, and the other peers have no knob. All seven models are always included at the chosen `N`; the only way to deviate — exclude a tier or give a tier its own count — is an explicit natural-language modification (see Invocation Shorthand). **GPT-Pro is the lone exception to "always included": it is a separate opt-in tier with its own count `M`, default `0`, never part of the symmetric `N` — added only via the optional second number (see Invocation Shorthand → GPT-Pro tier).**

### Invocation Shorthand

Two layers: a dead-simple positional form for the symmetric common case, and natural language for any deviation.

**Positional — `prism [N] [M] <question>`:**
- `N` — how many of **each** of the seven models (Claude subagents, Codex, Grok Build, Grok Composer, DeepSeek, MiMo, GLM). Integer `≥ 1`, default `1`; reject `0` (to drop tiers, use a natural-language exclusion). Total dispatched = `7N`; self does not count.
- `M` — how many **gpt-pro** lenses to add (the opt-in premium tier). Integer `≥ 0`, default `0`; **independent of `N`** (never dispatched unless given). Naming it is the cost consent — it burns real Pro quota and runs 5–20 min/lens (see GPT-Pro tier).

**There is no reasoning-effort token.** The two tunable tiers are fixed at their top setting on every run — **Codex `xhigh`, Grok Build `high`** — and the rest have no knob (Grok Composer none; DeepSeek/MiMo/GLM always at max). You never choose effort.

The parser consumes **up to two leading whitespace-delimited integers**, left-to-right: the first is `N`, the second is `M`. The first token that is **not** a bare integer begins the question; everything from there is verbatim question text. Examples: `prism 2 3 Why X?` → `N=2`, `M=3`, question "Why X?"; `prism 2 Why X?` → `N=2`, `M=0`; `prism migration plan` → question "migration plan".
- **Escape:** if the question's own first word is a bare integer, put `--` first — everything after `--` is question text (`prism -- 3 reasons to refactor?`). `--` is not a config token; it leaves zero config tokens, so the invocation routes to the autonomous decision (see **Config-presence gate**), not a pinned baseline.

Examples (a leading number skips auto-sizing; **no** number → autonomous decision):
- `prism Why does X?` — no number → autonomously decide `N` and `M` from the question.
- `prism 2 Why does X?` — explicit: 2 of each, no gpt-pro → 14 dispatched + self = 15 perspectives; no auto-sizing.
- `prism 2 3 Why does X?` — explicit: 2 of each **plus** 3 gpt-pro lenses → 14 + 3 + self = 18 perspectives.
- `prism 1 1 Bet-the-company call?` — 1 of each + 1 gpt-pro lens → 7 + 1 + self = 9 perspectives.
- `prism -- 2 reasons to refactor?` — the `--` makes the leading `2` question text, so the question is "2 reasons to refactor?" and `N`/`M` are decided autonomously.

**The second number is gpt-pro (`M`).** It adds `M` ChatGPT Pro Extended lenses via [[gpt-pro-relay]] on top of the normal lineup, independent of `N` and defaulting to `0` (never dispatched unless given). Accepted natural-language synonyms in the leading config zone are `<M> gpt-pro` and `plus <M> gpt-pro lenses`. Resolve it like any other config modifier, then dispatch per the GPT-Pro tier section.

**Natural-language modifications.** The positional form always dispatches all seven models symmetrically; to deviate, state it in words **in a leading config clause before the question** (config is parsed only up to where the question begins — a modifier buried *after* the question starts is treated as question text, not config). Treat a phrase as a modification only when it pairs a **tier name with a config action** (a count, or an exclusion word like no/skip/without); a bare tier name inside the question — e.g. *"why is there no DeepSeek fallback?"* — is **not** a modification, so do not strip or reinterpret it. Resolve the modifications into an explicit per-tier count before launch. Supported:
- **Exclude a model** — "no DeepSeek", "skip Grok Composer", "without mimo" → that tier's count = `0` (simply not dispatched; warn the user that dropping a whole lineage reduces cross-model diversity).
- **Per-model count** — "2 Codex, 1 of the rest", "3 Claude subagents" → the named tier overrides `N`; unnamed tiers keep `N`.
- **Combinations** — "2 of each but no Grok Composer".
- **Asymmetric example**: "2 of each, but no Grok Build or Grok Composer, and 2 DeepSeek" → Claude 2, Codex 2, Grok ×0, DeepSeek 2, MiMo 2, GLM 2. (Effort is never specified — Codex runs `xhigh`, Grok Build `high`, always.)

`N` (and the optional `M`) set the symmetric baseline; named modifications override specific tiers on top of it (an explicit exclusion overrides the "all seven always included" default; on conflicting clauses the more specific or later one wins). Resolve to a final per-tier table, then dispatch exactly that — every tier with resolved count > 0 MUST be dispatched at that count (do not skip, substitute, or defer; exception: `relay` unavailable → substitute a same-model subagent carrying that tier's lens and warn). You — the orchestrator — own resolving the shorthand and NL into the dispatch records; `prepare` then validates the *authored* dispatch file and emits the authoritative manifest counts, but it cannot know your intended `N`, so confirm the resolved shape matches your intent before running it (Pre-Launch Check #5).

### Config-presence gate (the routing decision)

Before anything else, the parser's result routes the invocation down exactly one of two paths — keyed on **what the parser resolved**, never on a re-reading of the raw string:

- **Any config token present** — a leading integer (`N`, or `N M`) *or* a leading natural-language modification (a tier name paired with a count or exclusion) → **honor it verbatim and skip auto-sizing.** `M` defaults to `0` and all seven tiers are included unless a modification says otherwise — a *stated default*, not an autonomous decision. Do not consult the decision table; do not "improve" the user's `N` or `M`. `prism 2 <q>` is `N=2`/`M=0`, full stop.
- **Zero config tokens** (the question begins immediately; `--` also lands here, since it leaves no tokens) → **autonomously decide** `N` and `M` per **Choosing N and gpt-pro**. Run that decision every time; the absence of a number is never permission to fire the baseline without reasoning.

A bare tier name *inside the question* ("why is there no DeepSeek fallback?") is **not** a config token (see Natural-language modifications) — it does not flip the gate to the explicit path.

### Choosing N and gpt-pro (decide autonomously — don't ask)

**This section runs only when the Config-presence gate routed you here — i.e. the invocation had no leading number.** (If the user gave any explicit number or modification, the gate already pinned the shape; honor it and skip this table.) On a bare question, pick `N` and `M` yourself — do not ask. Use the smallest run whose extra perspectives could change the action, confidence, or rollback plan. **Default down:** each `+1` to `N` adds a full seven-model slate and slower synthesis; never raise `N` just to "be thorough." **Start at the bottom rung and justify each step up:** land on the *lowest* row whose situation actually matches; if you cannot name the specific extra perspective an added agent would contribute, you are at the anchor. Auto-deciding is mandatory, but "decide" means *size to the question*, not *size up*.

| Situation | N |
|---|---|
| Bottom rung (anchor — start here) — a Prism-worthy decision one good pass could settle | 1 |
| Several viable options or stakeholder tradeoffs where breadth matters more than depth | 2 |
| Exceptional blast radius, or a decision still underdetermined after framing | 3 |
| Beyond N=3 | only on explicit user request or documented exceptional complexity — note the larger run shape in the launch status line, not as a gate |

**gpt-pro (default M=0 — usually skip):** gpt-pro is the opt-in premium tier on **two co-equal axes — Deep Reasoning and Research-Grounded Judgment** (top-tier reasoning, plus the only tier that browses by default in a front-loaded run). It spends real ChatGPT Pro quota and runs 5–20 min/lens, so the seven-model lineup is the default and gpt-pro is the rare exception — never the reflex for an ordinary Prism-worthy call. Auto-add **one** lens (`M=1`) only when the decision is genuinely high-stakes or hard-to-reverse **and** one of those two axes is the binding constraint: the hardest reasoning in the run, or live external research whose value is the research-plus-reasoning synthesis the standard tiers can't match. **"Needs the web" alone is not enough** — every tier browses, so route to gpt-pro only when research must be reasoned over at the strongest tier. Give gpt-pro the posture matching the binding axis: a **Deep-Reasoning** or **Research-Grounded** lens (see GPT-Pro tier). Use **`M=2`** (one Deep-Reasoning + one Research-Grounded) only for an exceptional, multi-faceted high-stakes call; never auto-add more than 2. You fire it yourself and just launch — do **not** pause for a confirmation or abort gate.

Note the resolved shape and its source (`<auto-sized|explicit> · N=<n>[, M=<m> gpt-pro (~5–20 min)] — <total> agents + self`) as a one-line status line as you launch — not a confirmation gate; never pause for the user to approve or redirect.

### Parallax (cross-model agents)

Parallax is dispatched via `relay` to **different models** (Codex, Grok Build, Grok Composer, DeepSeek, MiMo, GLM). Invoke `relay` directly — not via a subagent that calls relay. The value of each tier is model diversity:

- **Codex** — GPT-5.5 lineage, agentic code-review strength; prism always runs it at `xhigh`.
- **Grok Build** — xAI's independent lineage (`grok-build`), distinct from Anthropic/OpenAI; prism always runs it at `high`.
- **Grok Composer** — xAI's fast variant (`grok-composer-2.5-fast`), **same lineage as Grok Build**, no effort knob. Treat the two Grok tiers as **one vendor slot** for diversity lenses; reach for Composer for a fast xAI take.
- **DeepSeek** — an independent open-weight lineage (V4-Pro); always runs at `max` (DeepThink).
- **MiMo** — a third independent open-weight lineage (Xiaomi MiMo-V2.5-Pro); no effort knob.
- **GLM** — a fourth independent lineage (Zhipu/z.ai GLM-5.2), reached via z.ai's Anthropic-compatible endpoint; pinned to `max` reasoning (`reasoning_effort: max`, like DeepSeek), no prism effort knob.

**Tier strength and lens fit (heuristic for lens assignment, not a routing rule):** rough reasoning-capability ranking — **gpt-pro (when opted in) ≳ Claude ≈ Codex > {Grok Build (provisional, unbenchmarked — verify before the heaviest-reasoning lens), MiMo ≳ DeepSeek, GLM (provisional, unbenchmarked here)} > Grok Composer**. gpt-pro is the preferred home for **two co-equal premium posture families — Deep-Reasoning and Research-Grounded** — when present: every tier can reach the web (see below), so don't route to gpt-pro for browsing alone; route when the value is top-tier reasoning, or live research synthesized with top-tier reasoning (its reasoning-plus-research is the deepest, and it's the only tier browsing by default in a front-loaded run) — but it is opt-in, so never drop DeepSeek, MiMo, or GLM to make room for it, and discount gpt-pro+Codex *agreement* somewhat (both OpenAI-family, correlated blind spots) even though gpt-pro is its own tally lineage. Weaker tiers lose no value: each independent lineage catches blind spots the others share. This informs lens *placement*, not inclusion:

- **Subtle hard-reasoning lenses on risk-bearing questions** (Adversarial / Falsification / Disconfirming on a technical proposal where finding the non-obvious attack is the deliverable): prefer Claude subagent or Codex (which always runs at `xhigh`). If exactly one lens carries the heaviest reasoning load and it lands on a parallax tier, you've under-resourced the most decision-relevant role; when it must land on one anyway, prefer MiMo over DeepSeek.
- **Lenses where the value is a different prior** (Outsider, First-Principles, Reframe, Breadth-Weighted, Lateral-Generative, Stakeholder): give these to DeepSeek, MiMo, and GLM. Their independent lineages are the asset; raw reasoning depth is not the bottleneck.
- **Parallax lenses comparably hard:** no swap needed.
- **Never drop DeepSeek, MiMo, or GLM to "upgrade" a run.** Lineage diversity is non-substitutable; default tier inclusion is unchanged.

Assignment only — in synthesis, every tier's dissent keeps full cross-model weight (discount weak reasoning, never the model label). Revisit the ranking when the named model versions look stale.

Assign each tier a lens that maximizes diversity. **Default to orthogonal exploratory lenses** (Breadth-Weighted, Depth-Weighted, Outsider, First-Principles, Reframe) — these almost always extract more from cross-model diversity than a second attack angle. **Reach for an adversarial lens (Adversarial, Falsification, Disconfirming) only when it is much more valuable than another orthogonal lens would be** — i.e., the deliverable hinges on finding a non-obvious flaw, attack, or failure mode, and no other dispatched lens is already covering that ground. When that bar is met, put it on the parallax tier best suited to the reasoning load (see "Tier strength and lens fit"); otherwise skip it. When using multiple parallax tiers, give each a distinct lens — never assign the same lens to two of Codex, DeepSeek, MiMo, GLM, or the Grok tiers (that wastes a perspective). Treat grok-build + grok-composer as **one** vendor slot: don't give them two different diversity lenses as if independent (they share the xAI lineage). And don't stack two adversarial lenses unless the task genuinely demands independent attack frames.

Don't tailor the prompt body per peer — Prism sends the **same shared prompt** to every model (the launcher templates handle the only per-peer difference: Codex `<goal>` style vs CO-STAR XML), so you may skip the [[relay]] skill's per-peer prompting guides here. What matters is shared-prompt **quality** — an outcome-first shared packet (Full Question + Context) and sharp, distinct lens descriptions; optimize that, not per-model fit.

**Web access is not a dispatch concern — don't verify it.** Every peer can reach the web (WebFetch + WebSearch both work, save two minor gaps — DeepSeek's WebFetch and MiMo's WebSearch — neither load-bearing here; see [[relay]]). By default Prism front-loads all evidence in the shared packet (that's what Reference Materials is for), so agents reason over the provided Context rather than browsing — **but when the task requires live online research, each agent researches independently instead** (see the **Independent research for live-research tasks** rule under Shared Context). Either way, do **not** spend a dispatch-time step checking what the relay transport supports — it's settled and irrelevant to a well-built run.

**Relay call syntax (exact)** — the command shapes Prism must emit:

```bash
# Codex parallax (prism always uses --effort xhigh)
relay call --to codex --name <slug> --effort xhigh <<'BODY'
<prompt content here>
BODY

# Grok Build parallax (prism always uses --effort high)
relay call --to grok-build --name <slug> --effort high <<'BODY'
<prompt content here>
BODY

# Grok Composer parallax (no --effort — fast model, no effort knob)
relay call --to grok-composer --name <slug> <<'BODY'
<prompt content here>
BODY

# DeepSeek parallax (no --effort — always max)
relay call --to deepseek --name <slug> <<'BODY'
<prompt content here>
BODY

# MiMo parallax (no --effort — no effort knob)
relay call --to mimo --name <slug> <<'BODY'
<prompt content here>
BODY

# GLM parallax (no --effort — no effort knob)
relay call --to glm --name <slug> <<'BODY'
<prompt content here>
BODY
```

Use a lowercase slug for `--name` (e.g., `prism-adversarial`). Prism always passes Codex `--effort xhigh` and Grok Build `--effort high` (the top tier — no other value); never pass `--effort` or model flags on DeepSeek, MiMo, GLM, or Grok Composer (none has an effort knob). For all other invocation rules — `--name` required, `--to codex` as the default, non-empty heredoc, no model flags — follow the [[relay]] skill rather than restating them. For concurrency (backgrounding, timeouts), follow relay's Async / Parallel section.

**Inspecting Parallax results:** Read only the `.res.md` response file — never the `.log` sidecar (token-heavy stderr; the relay script's Bash output already surfaces failure diagnostics).

If `relay` is unavailable, replace all Parallax tiers with same-model subagents and warn the user. Each substitute carries the lens that tier was already assigned — do not re-decide by task category. Relay being unavailable does not change whether adversarial coverage is valuable for this question.

**Constraint leakage risk (CRITICAL):** Relay peers may recurse unless the anti-recursion rule is explicit, early, and repeated. You MUST:
1. Put the anti-recursion warning at the top of every launcher prompt, before the file-read instruction.
2. Preserve the Constraints section verbatim in the shared context file — do not summarize or abbreviate.
3. Ensure the prohibition appears in both each launcher (short form) and the shared file (full form).
4. Tell each peer to ignore loaded skill descriptions for the dispatching/side-effecting skills (prism, relay, gpt-pro-relay, deep-research) — read-only analysis skills stay available.

Without these redundant prohibitions, the peer treats the task as a fresh request and recurses.

**Effort for Parallax (fixed — no selection):** Codex always runs at `xhigh`, Grok Build always at `high`. There is no effort token and no per-run choice. Never emit Codex `high` or Grok Build `xhigh` (wrong per-tier word); DeepSeek/MiMo/GLM/Grok Composer never carry `--effort`.

### Subagents

Same-model agents dispatched via the Agent tool. Each gets a distinct lens. **Prism subagents are logical leaf nodes** — their prompts must forbid subagent spawning, dispatching-skill invocation (prism, relay, gpt-pro-relay, deep-research, any cross-model dispatch), and side effects, while permitting read-only analysis skills (see Constraints in the Shared Packet Template). Launch all agents concurrently before starting self-review.

### GPT-Pro tier (opt-in)

Dispatched only when the user gave a second number `M` > 0 (see Invocation Shorthand); default count `0`. gpt-pro is **orchestrator-direct**: `prism-launch` composes each launcher for you, but **you fire the `gpt-pro` calls yourself** (a shell script must never launch them, and they need the Bash-tool envelope + the cross-turn reattach lifecycle only the orchestrator can drive). It is **not** a relay peer and **not** in the `parallax` fan: never add it to `relay/peers.json` or the parallax batch — a 5–20 min gpt-pro lens would block the fast relay results, and relay's *read-a-file → write `.res.md`* contract is nothing like gpt-pro's *inline-everything → stdout → run-id-recovery* shape. `prism-launch` **composes and collects** gpt-pro (in `prepare`, `results`, `digest`); it never reimplements gpt-pro's transport, run-ids, reattach recovery, exit-code demux, or the macmini concurrency semaphore — those stay wholly in the [[gpt-pro-relay]] wrapper, which `prism-launch` shells out to (exactly as `parallax` shells to `relay`).

**Declare gpt-pro lenses in the dispatch file — `prepare` composes the launcher; you never hand-inline.** Add one `Type: gptpro` record per lens (`Lens` + `Lens-Desc`, optional `Posture: deep-reasoning|research-grounded`), plus the reference list to inline. gpt-pro runs in a web tab and **cannot read any local file**, so `prepare` (after it froze the packet) builds a self-contained launcher `<id>-gptpro-<slug>.md` = the committed `templates/launcher-gptpro.tmpl` header (carrying the instruction-inversion guard as line 1 + the lens) **+ the frozen packet verbatim + every reference file's contents** under `### <path>` headers **+ the grounding and calibration blocks** (from `templates/shared-gptpro-{grounding,calibration}.md`). Templated, not hand-retyped → no drift, no dropped guard.

```text
Shared-Packet: /tmp/prism-<id>.md
Reference: /abs/path/1            # authoritative inlining list (repeatable). Omitted → falls back to
Reference: /abs/path/2            # the packet's `### Reference Materials` bullets. `Reference: none` = packet only.

Type: gptpro
Lens: Deep-Reasoning
Lens-Desc: weigh the hardest end-to-end reasoning
Posture: deep-reasoning
```

`prepare` resolves the reference list (the dispatch `Reference:` keys are authoritative when present, else the packet's `### Reference Materials`), validates it **fail-closed** (no list at all, a directory entry, a missing/unreadable/whitespace path, or a single ref / composed prompt over gpt-pro's 1 MB cap each abort `prepare` *before* any quota), composes each launcher, and prints the exact backgrounded launch command per lens. The 1 MB overflow message says to shrink the shared packet for *all* agents, not to give gpt-pro a weaker context.

**Lenses:** gpt-pro has **two first-class posture families — Deep-Reasoning and Research-Grounded** (every tier can browse, but gpt-pro is strongest when the task needs top-tier reasoning, or live research synthesized with top-tier reasoning — see Tier strength and lens fit). Give it a Deep-Reasoning **or** Research-Grounded posture, each lens still answering the full question. Default pair for `M=2`: one Deep-Reasoning (`Depth-Weighted`, or `Falsification`/`Adversarial` on a risk-bearing question) + one `Research-Grounded` (web-tilted) — distinct axis families. For `M=1` pick the posture matching the binding axis (not reasoning by default); for `M≥3` add distinct postures (`First-Principles`, `Temporal`, `Empirical`), never copies. Names must stay distinct across the whole run.

**Launch** the exact line `prepare` printed — one backgrounded Bash call per lens, concurrently with the parallax fan and the Agent calls:

```bash
gpt-pro < /tmp/prism-<id>-gptpro-<slug>.md > /tmp/prism-<id>-gptpro-<slug>.res.md 2> /tmp/prism-<id>-gptpro-<slug>.log
```

with `run_in_background: true`, `timeout: 7260000` (fall back to `~/.claude/skills/gpt-pro-relay/scripts/gpt-pro` if not on PATH). Each is its **own** completion notification — `prepare`'s printed count already includes them. **Collect** with `prism-launch results <manifest>` and `prism-launch digest <manifest>`: both read the gpt-pro lane alongside parallax (a pending lens surfaces its `run_id` for reattach; gpt-pro is its own `GPT-Pro` digest lineage). **Recovery:** each gpt-pro Bash call is a *Bash* task, so reading its `.output` for the `run_id=` / `recover_with=` line is correct and required — the "never read a subagent's `.output`" rule does **not** apply here. Follow [[gpt-pro-relay]]'s exit-code table: 0 use it; 124/255 reattach with the literal run-id (`gpt-pro --run-id <id>`, same envelope); 1 inspect `reason`, don't blindly resubmit; 2 fix the call (no quota burned); 3 engine cap, terminal; 4 fresh-submit (only after a reattach proved never-landed). Up to `GPT_PRO_MAX_PARALLEL` (default 3) run in parallel; extra calls queue — **never raise the cap from prism** (account anti-abuse risk). When cleaning up, `prism-launch clean <id>` refuses to delete a lens whose `.log` shows a `run_id` but has no `.res.md` yet (a possibly-live worker) unless `--force`.

## Side-Effect Safety

Dispatched agents are **read-only** — no edits, commits, deploys, or external side effects. The only exception is the relay response file (`.res.md`) named in a `Reply:` directive. The primary agent may implement changes after synthesis if the user requested a deliverable.

## Shared Context

Build one shared evidence packet (Full Question + Context; `prepare` injects the canonical Constraints and How-to-answer) before composing prompts. Prefer compact digests over full file dumps. Write it to a temporary file once; every agent receives a short launcher prompt referencing this file plus its unique lens. If the packet cannot be duplicated cleanly across all agents, the task is too large for Prism.

**Reference materials (REQUIRED):** Before building the shared packet, identify all reference materials relevant to the question — CLAUDE.md files, READMEs, config files, documentation, skill definitions, style guides, or any file an agent would need to reason about the task. Include the **absolute paths** of these files in the Context section of the shared packet so every agent can read them. Agents cannot discover references on their own; if a path is not listed, the agent will not consult it.

**Independent research for live-research tasks:** When the task requires *online* research — current facts, fresh docs, version-specific behavior, anything not already settled in the repo or the packet — do **not** have the orchestrator research it once and front-load the findings. A single front-loaded evidence set makes every agent reason over identical sources, collapsing the cross-lens / cross-model diversity that is Prism's whole point into a shared-evidence monoculture. Instead, state the research need in the shared packet — the **exact** live question(s) to answer, plus any **common evidence floor** (the few authoritative sources/search targets every agent must consult and may *extend*, never replace) — and direct **each agent to research the live question independently, research to sufficiency rather than exhaustion** (a few authoritative sources suffice; the synthesizer weighs reasoning, not citation count), **and cite *and list* the sources it used** (every peer can browse — only DeepSeek's WebFetch and MiMo's WebSearch are missing, each keeping the other tool; see Parallax). This stays **redundancy, not division of labor** — every agent still answers the *whole* question end-to-end; only evidence-gathering is parallelized. The common floor keeps divergence comparable — it then means an agent found *more*, not that agents read disjoint facts — so divergence in *what* they find becomes signal, not just divergence in how they reason over fixed facts, and the listed sources let synthesis distinguish an information asymmetry from a genuine reasoning split and spot-check any fact a dissent rests on (Step 4 / Step 5). Still front-load **stable** context — repo files, CLAUDE.md, configs, the question itself — via Reference Materials; the carve-out is for *live* evidence only and is never an excuse to skip the shared packet. If a research-tilted lens lands on a tier that can't reach a needed source (e.g. a WebFetch-only page on DeepSeek), route that lens to a full-web tier or front-load that one source **for all agents** (label it a provided source, not independently-discovered evidence, so the packet stays identical) — never front-load it for the gapped tier alone, which would re-create the very asymmetry this rule manages.

### Shared Packet Template

Write this to `/tmp/prism-<unique-id>.md` using the Write tool (one call, before any dispatch). Use a unique identifier (e.g., timestamp + random suffix) to prevent collisions between concurrent Prism runs. **Write only Full Question + Context (with Reference Materials)** — `prism-launch prepare` injects the canonical `## Constraints` block (the verbatim read-only / anti-recursion text) and the `## How to answer` block (presentation guidance: verdict-first, cite sources, no preamble) when they're absent, so you never hand-copy them and they can't be fat-fingered.

```
## Full Question

{User's COMPLETE question/task, unchanged. Identical across all agents.}

## Context

{Shared evidence packet. Identical across all agents.}

### Reference Materials

{List absolute paths to every file relevant to the question — CLAUDE.md, READMEs, configs, docs, skill files, style guides, etc. Agents MUST read these before answering.}

- /path/to/relevant/file1
- /path/to/relevant/file2
- ...

### Live research (omit unless the task needs live online facts)

{If the answer depends on facts outside the repo/packet, name the EXACT question(s) each agent must research independently, plus any common-floor sources to start from. Do NOT front-load the findings. Each agent researches independently and cites + lists its sources. See the Independent research for live-research tasks rule.}
```

`prepare` appends the canonical `## Constraints` (from `templates/shared-constraints.md`) and `## How to answer` (from `templates/shared-how-to-answer.md`) if you omitted them — idempotent, so a re-run won't double either. (If you want a bespoke version of either, include that `##` section yourself and prepare leaves it untouched; Constraints additionally fails closed if a bespoke block drops the anti-recursion guard, How-to-answer carries no such safety load.) The packet is **frozen** once `prepare` runs — do not modify it after, since dispatched agents read it live. `Write` already confirms success, so no read-back is needed.

### Launcher Templates

Launcher prompts are committed template files in `templates/` alongside this SKILL.md, with `{{PLACEHOLDER}}` slots filled by `prism-launch` at dispatch time (see "Dispatch via prism-launch") — so the boilerplate is never hand-regenerated, only lens-specific values are emitted.

**Template files:**

| File | Used for | Slots |
|------|----------|-------|
| `templates/launcher-subagent.tmpl` | Agent tool (same-model subagents) | `SHARED_PACKET_PATH`, `LENS_NAME`, `LENS_DESC` |
| `templates/launcher-relay-codex.tmpl` | Bash relay, Codex (GPT `<goal>` style) | `SHARED_PACKET_PATH`, `LENS_NAME`, `LENS_DESC` |
| `templates/launcher-relay-costar.tmpl` | Bash relay, any CO-STAR peer (DeepSeek, MiMo, GLM, Grok Build, Grok Composer) | `SHARED_PACKET_PATH`, `LENS_NAME`, `LENS_DESC` |

There is **one relay template per prompting style**, not per peer — `prism-launch` selects it by the `template` field in `relay/peers.json` (Codex uses a GPT `<goal>` style; DeepSeek/MiMo/GLM/Grok share the CO-STAR `launcher-relay-costar.tmpl`). The anti-recursion warning is the top line of every template. Adding a relay target's **transport and launcher selection** is one `relay/peers.json` stanza — `prism-launch` validates and renders it registry-driven, no script edit needed; add a new template file only for a genuinely new prompting style. (A new **symmetric default tier** additionally needs the hardcoded surface updated: the scaffold peer loop, the `--preset` lens lists, and the `peershape` display order in `prism-launch`, plus the model/agent counts throughout these docs.)

### Dispatch via prism-launch

You do **not** render templates or hand-write relay heredocs. The `prism-launch` script (`~/.claude/skills/prism/scripts/prism-launch`) owns the cross-model half of dispatch: it renders every launcher from the templates, validates dispatch shape mechanically, and fans all relay calls out as **one** backgrounded process that waits for every peer and writes a single structured result.

**Invoke it by its absolute path** — `~/.claude/skills/prism/scripts/prism-launch` — not the bare name. The bare command is on PATH only when the shell inherited the `.zshenv`-injected PATH; a sandboxed/non-zsh/reset-env agent shell will not have it, and a bare-name miss must NOT trigger the manual fallback. The absolute path is the script's real install location, so its templates resolve correctly with no extra handling. (`prism-launch` resolves its sibling `relay` the same way — by install path, falling back to PATH — so `parallax` dispatches even when `relay` is not on PATH either.)

It cannot dispatch Claude subagents (only Claude can invoke the Agent tool, never `claude -p`) — so you still issue the subagent Agent-tool calls yourself.

**You write one line-oriented dispatch file with the Write tool** (one record per agent — never a shell heredoc), then run two commands. For the symmetric default, run `~/.claude/skills/prism/scripts/prism-launch scaffold --n <N>` first — it prints a ready-to-fill skeleton (correct records, canonical model order, and the fixed Codex `x` / Grok Build `h` effort tokens) so you only replace the `FILL` lens names + descriptions. Add `--preset review|design|diagnosis|compare|research|decision|writing` to also pre-fill seven lenses by task type (N=1) — then just edit them to taste. (Asymmetric runs — per-tier counts, exclusions — have no scaffold; author those records by hand.) The dispatch format is plain `Key: value` lines in blank-line-separated records: no braces, commas, quoting, or escaping, so a free-text lens description can't break it the way hand-authored JSON can. Authoring the config as raw JSON is no longer the default — writing literal text with the Write tool is what removes the escaping surface.

Write `/tmp/prism-<id>.dispatch` with the **Write tool**:

```text
Shared-Packet: /tmp/prism-<id>.md

Type: parallax
To: codex
Name: adversarial
Effort: x
Lens: Adversarial
Lens-Desc: weigh the strongest attacks on the proposal

Type: parallax
To: grok-build
Effort: h
Lens: First-Principles
Lens-Desc: weigh how this looks rebuilt from the goal up

Type: parallax
To: grok-composer
Lens: Pragmatist
Lens-Desc: weigh the fastest workable path

Type: parallax
To: deepseek
Lens: Falsification
Lens-Desc: weigh what evidence would prove this wrong

Type: parallax
To: mimo
Lens: Outsider
Lens-Desc: weigh how a newcomer would approach this

Type: parallax
To: glm
Lens: Temporal
Lens-Desc: weigh how this holds up over time — lifecycle, sequencing, reversibility

Type: subagent
Lens: Simplicity
Lens-Desc: weigh the approach that requires the fewest moving parts
```

This is the canonical default — all seven models at `N=1`. The two tunable tiers always carry the top effort: **Codex `Effort: x`** (xhigh) and **Grok Build `Effort: h`** (high) — there is no other value. (`prism-launch` accepts the single-letter or full word and normalizes `x`→`xhigh`, `h`→`high`.)

Format rules: `Shared-Packet:` appears once. Each record starts at `Type: parallax|subagent|gptpro`; blank lines separate records and `#` begins a comment. For `parallax`, `To:`/`Lens:`/`Lens-Desc:` are required, `Name:` is optional (defaults to the slugified lens), and `Effort:` is set only on the two tunable peers and is always the top tier — Codex `x` (`xhigh`), Grok Build `h` (`high`); `-` or omitted = none — DeepSeek/MiMo/GLM/Grok Composer take none. For `subagent`, only `Lens:`/`Lens-Desc:` are needed. For `gptpro`, `Lens:`/`Lens-Desc:` are required and `Posture:` (`deep-reasoning`/`research-grounded`) is optional — `To:`/`Name:`/`Effort:` are rejected; a top-level repeatable `Reference: <abs-path>` key (outside any record) is the authoritative inlining list for gpt-pro lenses (omit it to fall back to the packet's `### Reference Materials`; `Reference: none` = inline only the packet). Everything after the **first** `:` is the literal value, so quotes, colons, `>`, `<`, and single braces in a description are fine — except the reserved tokens `</` and `{{` (the injection guard), which `prepare` rejects with a rephrase hint.

```bash
# 1) prepare (foreground): compiles the dispatch file into the canonical config,
#    validates packet/shape/effort/injection, renders all launchers, writes
#    <id>-manifest.json. Fails loudly if anything is off.
~/.claude/skills/prism/scripts/prism-launch prepare --dispatch /tmp/prism-<id>.dispatch

# 2) parallax (ONE backgrounded Bash call, run_in_background: true): fans out all
#    relay calls, waits for all, writes <id>-result.json with per-peer status.
#    (prepare prints this command with the same absolute path — copy it from there.)
~/.claude/skills/prism/scripts/prism-launch parallax /tmp/prism-<id>-manifest.json
```

`prepare` normalizes the dispatch file into `/tmp/prism-<id>-config.normalized.json` (the canonical JSON, kept for audit) before validating. **`prepare --config <config.json>` remains supported** as the machine/escape-hatch interface — it accepts that same JSON shape directly, also written with the Write tool (literal content, never a heredoc). Both paths run identical validation, rendering, and manifest logic; `--dispatch` is just a literal-text front-end that removes the JSON-escaping surface.

`prepare` prints each subagent launcher's **contents inline** (delimited, with its path) — copy the contents straight into an Agent-tool call, no separate Read needed. It validates `lens`/`lens_desc` (rejecting `</` and `{{` as an injection guard; comparison operators like `>` are allowed), enforces distinct lens names and distinct relay `name`s, rejects `effort` on DeepSeek/MiMo/GLM/Grok Composer, and rejects a `shared_packet` path containing whitespace. `parallax` writes `<id>-result.json` (`{id, expected, succeeded, failed, results:[{to,name,status,res,log}]}`) and prints each peer's `.res.md` path to its own stdout — i.e. the backgrounded task's `.output` file, which is short and **safe to Read** for the paths. (Never Read a *subagent's* `.output` — that's the full JSONL transcript and overflows context; the subagent's result arrives in its completion notification instead.) On completion, `prism-launch results <manifest>` prints each peer's status + `.res.md` path from `<id>-result.json` (one structured view, exits non-zero if any failed) — then Read the `.res.md` files; the `log` field is relay's own diagnostics for a failed peer — never relay's token-heavy `.log` sidecar. Use `~/.claude/skills/prism/scripts/prism-launch parallax <manifest> --dry-run` to preview the exact relay commands without dispatching. Per-peer timeout defaults to 3600s (`PRISM_PEER_TIMEOUT`; set `=0` to disable the per-peer cap, leaving only the outer Bash-tool timeout) — deliberately generous, since a peer killed mid-run wastes every token it spent; set the backgrounded Bash call's `timeout` above that (e.g. `3660000`).

**Manual fallback (last resort — only if the script file is genuinely missing):** A bare-name "command not found" is NOT a trigger — re-invoke by the absolute path above. The manual flow applies only when `~/.claude/skills/prism/scripts/prism-launch` does not exist at all (a broken install). First try to repair the install (`cd ~/dotfiles && ./dotfiles.sh`); if that is not possible, render each launcher with `sed -e 's|{{SHARED_PACKET_PATH}}|...|g' -e 's|{{LENS_NAME}}|...|g' -e 's|{{LENS_DESC}}|...|g' templates/launcher-<kind>.tmpl`, then dispatch one `relay call --to <peer> --name prism-<slug>` heredoc per parallax tier (Codex `--effort xhigh`, Grok Build `--effort high`, no `--effort` on the rest; background each, `timeout: 3660000`). This is the degraded pre-`prism-launch` flow; prefer the script.

## Pre-Launch Checks

Run these checks before launching. If any fails, rewrite and re-check. **When dispatching via `prism-launch` (the default path), `prepare` enforces checks 1, 2, 5, and 6 mechanically and aborts on failure, and `parallax` enforces check 0 (relay availability) before dispatch — you still own the judgment checks 3 (redundancy) and 4 (lens quality), which require semantic reasoning a script cannot do.** The descriptions below remain authoritative for the manual fallback and for understanding what `prism-launch` verifies.

0. **Relay availability test (if any parallax tier > 0):** Run `command -v relay` to check if the relay command is in PATH. This is the sole test — do not glob for relay files or references to determine availability. If the command exists, relay is available.

1. **Shared-file test:** Verify the shared context file was written (the Write tool confirms this — no read-back needed). Confirm every rendered launcher references the same absolute file path. The shared file must be frozen before any dispatch.

2. **Slot-completion test:** After rendering all launcher prompts via `sed`, verify no `{{` placeholder tokens survive: `grep -c '{{' rendered_launcher`. Also confirm the shared packet path is absolute and identical across all rendered prompts, and that the anti-recursion warning is the first line of every launcher. For relay prompts (Codex, DeepSeek, MiMo, GLM, Grok Build, Grok Composer), verify the XML skeleton is well-formed (`<context>`, `<objective>` or `<goal>`, `<constraints>`, `<your_lens>` tags present).

3. **Redundancy test:** Swap any two agents' lenses. If the prompts become incoherent, you have divided labor (tell-tale signs: scope, evidence, tools, output format, or deliverables differ between prompts). This applies across tiers too — a Codex agent's lens and a DeepSeek agent's lens should be swappable in principle (only the prompt format differs).

4. **Lens quality test:**
   - Each lens name is a weighing posture (1-3 words), never a task or role.
   - For each lens, write one sentence naming the unique axis it covers; if two would produce the same emphasis, replace one.
   - **Select by axis family — one per family:** map each lens to its family in the Lens Axes table and field at most one lens per family. Two lenses from the same family are near-duplicates that fail the redundancy test in spirit even when their names differ; field a second from a family only when you can state how the two differ *on this task*. This is the primary guard against the over-served Reframe / Challenge / Delivery clusters — choose by axis, not by scanning names.
   - **Adversarial coverage is opt-in:** include an adversarial-family lens (Adversarial, Falsification, Disconfirming, Risk) only when the answer turns on surfacing a non-obvious flaw/attack/failure-mode no other lens is covering — name the specific risk first; if you can't, use an exploratory lens. A "risk-bearing" task (decision, design, code review, implementation, root-cause claim) does *not* automatically require one.
   - **Omission must also be deliberate:** if the task proposes, evaluates, or changes something and you include *no* adversarial-family lens, name which dispatched lens covers "what could go wrong"; if none does, add one (a failure-mode-tilted exploratory lens — e.g. Depth-Weighted on failure modes — suffices). Silent omission here is a check failure.
   - Never assign the same lens to two of Codex, DeepSeek, MiMo, GLM, or the Grok tiers.
   - If an adversarial lens carries the heaviest reasoning load on a subtle technical question, assign it to Claude or Codex (`xhigh`) rather than a parallax tier; if a parallax tier must take it, prefer MiMo over DeepSeek (see "Tier strength and lens fit").

5. **Dispatch-shape test (CRITICAL):** First resolve the config — every tier's count defaults to `N`, then apply any natural-language modifications (exclusions → `0`, per-tier counts). Total dispatched agents (Claude subagents + the six parallax tiers) must equal the resolved per-tier counts; self does not count. Enumerate planned calls by type — `--to codex`, `--to grok-build`, `--to grok-composer`, `--to deepseek`, `--to mimo`, `--to glm` each equal to that tier's resolved count, and Agent calls equal to the resolved Claude-subagent count. The default symmetric run is `N` of each: `6N` relay calls + `N` Agent calls. If `M` > 0, also `M` `Type: gptpro` records — `prepare` composes each into a `<id>-gptpro-<slug>.md` launcher (listed in the manifest's `gptpro[]`), and you fire `M` backgrounded `gpt-pro` Bash calls, separate from the parallax fan (not relay, not in `6N`+`N`). Confirm the `M` records and the resolved `Reference:` list inline the right files. If any count mismatches the resolved config, fix before launching. The most common failure is emitting fewer relay calls than the resolved parallax total.

6. **Effort test:** Effort is fixed — confirm Codex carries `--effort xhigh` and Grok Build `--effort high` (the only valid values; never Codex `high` or Grok Build `xhigh`). Never pass a raw `x`/`h` token to relay — map to the full word. DeepSeek, MiMo, GLM, and Grok Composer calls must NOT pass `--effort`.

## Lens Assignment

A lens is a **weighing posture**, not a task variant. Do not put the task noun in the lens name.

Choose lenses on **orthogonal tradeoff axes**. Before adding one, write one sentence explaining how it differs from every existing lens. If you cannot name a distinct axis, do not add it. The symmetric default dispatches seven agents (one per model), so aim for **seven distinct postures**; if the task can't support that many, exclude a tier via natural language rather than giving two agents the same lens. At `N ≥ 2` (multiple agents per model), give each copy a distinct lens where the task supports it; deliberate same-*posture* redundancy to reduce variance on a pivotal question is allowed, but each agent still needs a **distinct lens name** (e.g. `Adversarial-A` / `Adversarial-B`) — `prism-launch` rejects duplicate names. Note that `N=1` gives only one Claude subagent slot: when a risk-bearing question wants its adversarial lens on Claude or Codex (Check #4), either accept it on Codex (which always runs `xhigh`), bump `N`, or exclude a Parallax tier via NL to free a Claude slot.

On a **live-research task**, also weigh tier web-reach when placing research-tilted lenses: route them to full-web tiers, and avoid DeepSeek (no WebFetch) or MiMo (no WebSearch) when the needed source requires the missing tool — see the **Independent research for live-research tasks** rule (Shared Context).

### Lens Axes

Lenses are grouped into **axis families**. Two lenses in the *same* family are near-substitutes — fielding both wastes a slot and silently fails the redundancy test. **Pick at most one lens per family per run;** field two (or more) from one family only when each earns its slot by a distinct on-task emphasis (the redundancy test must still pass). Two task types legitimately do this: **research/exploration**, where probing the option/framing space *is* the deliverable, so several Reframe/Search lenses (`First-Principles` rebuild-from-goal vs `Outsider` another-field's-eyes vs `Lateral-Generative` pattern-break) are the point; and **writing**, where `Clarity` (is it clear) and `Audience` (fit to the reader) are distinct Human/Value emphases. Everywhere else, aim for seven different families. This is the unit of selection — **choose by axis, not by scanning names.**

| Axis family | What it weighs | Member lenses |
|---|---|---|
| **Search** | coverage vs depth | Breadth-Weighted · Depth-Weighted |
| **Reframe** | a different basis, prior, frame, or non-obvious option | First-Principles · Outsider · Reframe · Lateral-Generative |
| **Evidence** | empirical grounding and correctness | Empirical · Correctness |
| **Mechanism** | cause and effect | Causal |
| **Challenge** *(opt-in)* | attack, downside, disproof | Adversarial · Falsification · Disconfirming · Risk |
| **Human / Value** | affected parties and reception | Stakeholder · Audience · Clarity |
| **Delivery** | ship-ability, structural fit, and minimalism | Pragmatist · Simplicity · Structural |
| **Time** | lifecycle, sequencing, reversibility | Temporal |
| **Self** | holistic synthesis (orchestrator only) | Integrator |

Lenses added to close coverage gaps: **`Empirical`** (the measurement / base-rate axis — for "did X actually improve it?", perf, and A/B claims; no other lens demands a baseline + metric), **`Stakeholder`** (affected parties and second-order effects — distinct from `Audience`, which is only *reception*), **`Temporal`** (promoted from the old `Evolutionary`, now covering lifecycle *and* sequencing/reversibility), **`Lateral-Generative`** (deliberate novelty / "out-of-the-box" pattern-breaks, distinct from breadth), **`Reframe`** (merges the former `Alternative-Framing` + `Disconfirming-via-different-frame`), and **`Structural`** (the build-quality pole of Delivery: weighs the structurally-correct fix at the needed scope, rejecting *both* the expedient hack and scope-padding — distinct from `Simplicity`, which counts moving parts and can bless a hack, and the direct complement of `Pragmatist`, which optimizes for shipping under constraints). Retired as near-duplicates: `Expansionist` (→ `Lateral-Generative` / `Breadth-Weighted`) and `Feasibility` + `Executor` (→ `Pragmatist`; `Executor` was a role, not a posture). The menu stays **open** — mint a task-specific lens when you can name its axis in one sentence and slot it into (or beside) a family.

**`Disconfirming` vs `Reframe`:** these are not interchangeable. `Disconfirming` is adversarial (Challenge family) — it directly attacks a specific claim and is subject to the opt-in gate in the Lens quality test. `Reframe` is exploratory (Reframe family) — its value is an alternate prior or framing, not stress-testing — so it counts as an orthogonal default, not the adversarial slot. Do not relabel an attack posture as a frame to evade the opt-in gate.

### Suggested lenses by task type

Starting points — every lens still answers the full question. The symmetric default dispatches **seven** agents, so each set below is seven distinct postures; most span seven different axis families (research and writing deliberately field two from one family — see Lens Axes). The seven `prism-launch scaffold --preset` sets pre-fill these (Implementation has no preset — compose it by hand). The adversarial-family slot (italicized) is a *candidate*, not a default: keep it only if stress-testing is the binding constraint for this specific question (see Lens quality test); otherwise replace it with another family's lens.

- **Code review**: *Adversarial* + Correctness + Simplicity + Depth-Weighted + Temporal + Outsider + Stakeholder
- **Architecture / design**: First-Principles + *Adversarial* + Simplicity + Stakeholder + Temporal + Empirical + Breadth-Weighted
- **Implementation**: Correctness + Pragmatist + *Adversarial* + Depth-Weighted + Outsider + Temporal + Stakeholder
- **Diagnosis / root cause**: Causal + *Falsification* + Empirical + Depth-Weighted + Temporal + Outsider + Stakeholder
- **Option comparison**: First-Principles + Empirical + Simplicity + Stakeholder + Temporal + *Disconfirming* + Breadth-Weighted
- **Writing / communication**: Clarity + Audience + *Adversarial* + Simplicity + Outsider + Empirical + Depth-Weighted
- **Research / exploration**: First-Principles + Breadth-Weighted + Depth-Weighted + Outsider + Empirical + Lateral-Generative + Temporal
- **Decision / strategy**: First-Principles + Empirical + Stakeholder + Temporal + Pragmatist + *Disconfirming* + Breadth-Weighted

**Live-research note:** a preset picks *lenses*, not the research *mode* — a *Research / exploration* (or any) task whose answer depends on current external facts also triggers the **Independent research for live-research tasks** rule (Shared Context), so add the independent-research directive to the packet yourself.

Reach for **`Structural`** (Delivery) on architecture/implementation questions that hinge on the *durable structural fix vs. expedient hack* tradeoff (the "code is cheap" call) — swap it in for `Simplicity` when build quality is the binding constraint, or field it alongside `Pragmatist` to stage that tradeoff explicitly. It's one Delivery pole, so don't field it with `Simplicity`/`Pragmatist` as if independent.

## Execution

### Quick Start (the happy-path N=1 run)

Invoke `prism-launch` by its absolute path `~/.claude/skills/prism/scripts/prism-launch` (abbreviated `PL` below; see the absolute-path rule above).

1. **Write the packet** `/tmp/prism-<id>.md` — just `## Full Question` + `## Context` (with Reference Materials). No Constraints or How-to-answer; `prepare` injects them. If the answer depends on **live online facts** (not just repo/packet evidence), add a `### Live research` block naming what each agent must look up independently — don't front-load the findings (see the **Independent research for live-research tasks** rule).
2. **Scaffold the dispatch:** `PL scaffold --preset <task-type> --packet /tmp/prism-<id>.md` (or `--n 1` for blank slots). Edit the lenses, Write to `/tmp/prism-<id>.dispatch`.
3. **Prepare:** `PL prepare --dispatch /tmp/prism-<id>.dispatch` — prints the parallax command, the expected notification count, and each subagent launcher's contents.
4. **Launch concurrently:** one backgrounded `PL parallax <manifest>` Bash call + one Agent call per subagent (paste the inline launcher contents). Then wait for every notification.
5. **Collect + synthesize:** `PL results <manifest>` → Read each `.res.md` → synthesize. **Large or high-volume runs** (≥~12 dispatched, *or* fewer peers whose combined `.res.md` outputs would crowd synthesis context — verbose lenses, gpt-pro lenses present, already near a context limit): run `PL digest <manifest>` first, read the small lineage-tagged digest, then deep-read only the dissenting/weak/novel-rationale/tie-break `.res.md`. At N=1 the full reads are usually cheap — skip digest unless volume warrants. Optionally `PL clean <id>`.

The numbered steps below are the authoritative detail; the Quick Start is the shape.

### Step 1: Freeze context, compose, verify, launch

1. Build one canonical shared packet (Full Question + Context — `prepare` injects the Constraints and How-to-answer). Write it to `/tmp/prism-<unique-id>.md` with the Write tool. Decide whether the task needs **live online research**; if so, don't front-load the findings — add a `### Live research` block per the **Independent research for live-research tasks** rule (Shared Context).
2. Assign lenses (run the redundancy and lens-quality checks — these are yours to judge), then write the line-oriented dispatch file (`/tmp/prism-<id>.dispatch`) with the Write tool — `Shared-Packet:` plus one record per parallax peer and per subagent. See "Dispatch via prism-launch". (The `--config` JSON form is still accepted as an escape hatch.)
3. **`~/.claude/skills/prism/scripts/prism-launch prepare --dispatch /tmp/prism-<id>.dispatch`** (foreground). This compiles the dispatch file into the canonical config, validates the packet and records its path (it does not copy or hash it — do not mutate the packet after this point), renders all launchers, runs checks 1/2/5/6, and writes `<id>-manifest.json`. If it exits non-zero, fix the dispatch file and re-run — nothing has been dispatched.
4. Launch all dispatched agents concurrently (`run_in_background: true`). **Dispatch checklist:**
   - **Parallax — ONE backgrounded Bash call:** `~/.claude/skills/prism/scripts/prism-launch parallax /tmp/prism-<id>-manifest.json` (set the Bash tool `timeout` above `PRISM_PEER_TIMEOUT`, e.g. `3660000`). This fans out every Codex/DeepSeek/MiMo/GLM/Grok call, waits for all, and yields a single completion notification. Compose this call FIRST.
   - **Subagents:** one **Agent** tool call per subagent, using the launcher **contents `prepare` printed inline** as the prompt (the file path is shown only as a fallback). Never use `claude -p` for these.
   - **GPT-Pro (only if `M` > 0):** `prepare` already composed each launcher (from the `Type: gptpro` records) and printed the exact command — fire one backgrounded `gpt-pro < .../prism-<id>-gptpro-<slug>.md > ... 2> ...` Bash call per lens (`run_in_background: true`, `timeout: 7260000`). The launchers live in the manifest's `gptpro[]` (composed + collected by prism-launch), but the orchestrator still fires and reattaches them — see the GPT-Pro tier section.
   - The manifest's `counts` is the authoritative dispatch shape **for relay + subagents** — there is no per-relay-call count to reconcile by hand, because `prism-launch` emits exactly the configured calls. The gpt-pro count is tracked separately by the orchestrator.

Do not poll or sleep-loop — the system notifies you when agents finish. (A bare-name "command not found" is not a fallback trigger — invoke by the absolute path above. The manual `sed`+heredoc flow applies only if the script file is genuinely missing, per "Manual fallback" above.)

### Step 2: Self-review

While agents run, form your own position independently. Your lens is **Integrator Lens** — you weigh holistic coherence, feasibility, and alignment with the user's goals. Write your tentative recommendation before opening any agent output.

Since you composed the prompts and chose the lenses, your self-review is not fully independent. When dispatched agents diverge from your position, give their perspectives slightly more weight on points you may have anchored on during prompt design.

### Step 3: Wait for ALL agents (HARD GATE)

**Do not synthesize, summarize, or present results until EVERY dispatched agent — including all Parallax tiers and every GPT-Pro lens — has returned.** This is a hard gate, not a suggestion. Having "enough" subagents is never a reason to skip the remaining agents. The whole point of Parallax is model diversity — proceeding without it defeats the purpose of Prism. One peer finishing first (Codex, DeepSeek, MiMo, GLM, Grok, or the parallax batch) is never permission to ignore the others — and **gpt-pro is expected to be the last to return**, so "everything but gpt-pro is done" is the expected state, never a reason to synthesize.

**Parallax is slow, gpt-pro slowest** — relay calls routinely take 2-5x longer than subagents (DeepSeek at `max`, Codex `xhigh`, Grok Build `high` are slowest); a gpt-pro lens is 5–20 min. Do not diagnose, retry, report failure, or proceed while a background task is running. With `prism-launch parallax`, **all parallax peers finish under a single completion notification**; **each gpt-pro lens is its own notification** (it's a separate Bash call, not part of the batch). So the notification count = (1 per subagent) + (1 for the parallax batch, if any) + (1 per gpt-pro lens) — e.g. a `prism 1 2` run yields 4 (1 subagent + 1 parallax + 2 gpt-pro). **`prism-launch prepare` now prints the full count, including one per gpt-pro lens** — wait for exactly what it printed; under-waiting on the gpt-pro notifications is the exact gate violation to avoid. While waiting, work on your self-review (Step 2), then wait silently; do not synthesize partial results.

**Handling failures (after completion notification only):**

- **Relay transport failure:** After the parallax notification, run `prism-launch results <manifest>` (or read `<id>-result.json`) — any peer with `status: "error"` failed. Retry just that peer with `prism-launch parallax <manifest> --only <peer-name>` (backgrounded; it re-dispatches one peer by model/lens-name and merges the result back in — do not re-run the whole fan). Check the Bash output for the diagnosed cause; do not read the `.log` sidecar — it is extremely long and token-heavy.
- **Answer-quality failure** (empty, truncated, off-topic): Offer the user: (a) retry, (b) proceed with reduced perspectives, or (c) abort.
- **Only these post-notification failures justify proceeding without Parallax.** "It's taking a long time" is never a failure.

### Step 3.5: Safety check

Before synthesizing, check whether a dispatched agent violated read-only by writing to the working tree:

```bash
git diff --stat HEAD
```

**NEVER revert, restore, checkout, stash, reset, or clean the working tree — not even changes that look "unexpected" (HARD RULE).** `git diff` here is **read-only detection only**; you never "clean up" what it shows. The tree may hold *uncommitted* work that is **not yours**: the user's in-progress edits, or a **concurrent prism / Claude Code session** running in the same repo. Discarding it is **unrecoverable** — this is a real incident (a concurrent prism run wiped an uncommitted change it found but had not made), not a hypothetical.

If the diff shows changes, do **not** assume your agents made them, and do **not** auto-attribute or undo them — **flag them to the user and let them decide.** "Discard the offending agent's output" means *ignore that agent's `.res.md` text in synthesis* (it may have reasoned from a corrupted state); it is **never** a git operation on the tree. If you need a clean baseline, commit your *own* work first — never revert someone else's.

Scan each agent's output for recursion indicators: mentions of "dispatching," "subagent," "relay call," "Prism run," or synthesis-style structure (a model-tier tally, `Dissent:`/`Why:`/`Do now:` sections, or older `Consensus/Contested/Unique` sections). Flag matches for review — the agent may have spawned nested agents, producing contaminated reasoning.

### Step 4: Synthesize

Write a skim-first, verdict-led synthesis, not a lens-by-lens report — the reader should grasp the recommendation, confidence, and any cross-model dissent in seconds. The verdict line carries those three; the body carries the reasoning.

**Default budget: ~100-150 words in the visible main path.** If you're writing more, you're hedging or scaffolding — compress. Deliverables are bounded by the artifact; the optional appendix is uncounted.

**Large or high-volume runs — read digests first, deep-read selectively.** Every agent ends its answer with a `## Digest` block (the canonical How-to-answer template requires it). When reading every full `.res.md` into context would degrade synthesis — by default at ~12+ dispatched (N≥2), but also a smaller run whose combined outputs are large (verbose lenses, gpt-pro lenses present, already near a context limit; dispatched count is a proxy for the real driver, output token volume) — run `~/.claude/skills/prism/scripts/prism-launch digest <manifest>` to extract each parallax peer's digest into one small lineage-tagged file; read that plus each subagent's digest (already in your conversation) to form the verdict and by-lineage tally, then deep-read the full `.res.md` **only** for peers whose digest dissents, looks weak/off-topic, advances a materially novel rationale or `Dissent/caveat` even while its Position aligns, or is the tie-breaker. The digest **compacts inputs, it never decides** — you still compute the verdict, confidence, and tally yourself, and you must read a dissenter's raw words before capping confidence on it. For a small run (N=1) the full outputs are usually cheap to read directly; skip the digest step unless output volume already strains synthesis.

**Default skeleton — the verdict line is fixed and always first; the body below it flexes by mode (see Mode adaptation):**

1. **Verdict line** — one line, the first thing the eye hits. Fixed token order, `·`-separated:

   `<verdict, aim ≤12 words> · conf: <High|Moderate|Low> · <n>/<total> agree[ · ⚠ dissent]`

   - `<n>/<total>` counts **perspectives that returned, including self** (the default `N=1` run is `/8`: self + 7 dispatched; **add each returned gpt-pro lens** — `prism 2 2` that fully returns is `/17`: self + 14 + 2) — *not* dispatched-only, *not* lineages. A gpt-pro lens that failed terminally does **not** count toward `total`; name the missing perspective rather than silently shrinking the denominator. The tally below counts *lineages*; the two denominators intentionally differ. (Self is a perspective here even though it does not count toward *dispatch* shape elsewhere.)
   - For an **exploratory question** with no proposition to vote on, swap `<n>/<total> agree` for `<n>/<total> aligned` (or `· converging` / `· divergent`) and let the verdict line state the synthesized finding rather than a recommendation. Confidence is still shown.
   - Confidence is **always shown** — the *absence* of a `⚠ dissent` clause is itself the all-clear signal.
   - The `⚠ dissent` clause appears **only** when a dispatched agent dissents. On a cross-model break the tally and Dissent line already name the peers, so the verdict clause stays a bare `⚠ dissent`; name a peer inline (`⚠ DeepSeek dissent`) only for a minor dissent that has no tally. `⚠` is the only routine glyph — reserve it for dissent; never decorate confidence or the verdict with emoji or boxes.
   - Deliverable: the verdict line points at the artifact (`See migration plan below · conf: High · 8/8 agree`), which follows immediately.
   - **Render the header as a compact two-column table whenever it is dense — independent of whether the run converged.** "Dense" is any one of: the verdict needs more than ~12 words, there is a caveat or secondary item to carry, or there is a dissent note. Convergence does **not** license the single line — a converged run with a long verdict or a caveat still tables. A caveat gets its **own row**; never pack it into the verdict clause. Same fields, same content, far more readable:

     | Summary | Detail |
     |---|---|
     | **Verdict** | NO-SHIP as-is — fix the cluster, then ship |
     | **Confidence** | High |
     | **Consensus** | 6 reviewers convergent — 1 severity split, 1 finding discounted |
     | **Caveat** | 1 latent high-severity item to resolve first *(omit row if none)* |
     | **Dissent** | DeepSeek+MiMo, same direction *(omit the row when there is none)* |

     Use the single `·`-separated line **only** when verdict + confidence + tally genuinely fit one short line — a converged run with a ≤12-word verdict and no caveat. When in doubt, table it.

2. **Model-tier tally** — one line, **only on a cross-model break** (a parallax lineage dissents). Group by model lineage (not by lens): each dispatched lineage with `✓` (aligned) or `⚠` (dissented), then the takeaway.

   `Claude ✓  Codex ✓  DeepSeek ⚠  MiMo ⚠   → 2 independent lineages dissent, same direction`

   Omit on full convergence (all `✓` — the header's `n/n agree` already says so) and on an intra-lineage split (a by-lineage tally cannot show a split *inside* one lineage — use the `Tradeoff:` line instead). List only the lineages actually dispatched (treat the two Grok tiers as one `Grok` lineage; gpt-pro is its **own** `GPT-Pro` lineage, kept separate from Codex despite the shared OpenAI family). A lineage that ran several agents collapses to one `✓`/`⚠`: mark `⚠` if **any** member raised a cross-model dissent you could not refute (a lineage's dissent is never averaged away by its other members agreeing), and resolve its aligned position by strongest reasoning, not majority vote. This tally is the **one sanctioned exception** to the per-lens-attribution ban below: it attributes by *lineage* (the load-bearing cross-model signal), never lens-by-lens.

3. **Dissent** — its own labeled line **on a cross-model break**, placed above Why: the peer(s), the *specific* argument, and what would resolve it ("DeepSeek+MiMo: shared state needed for atomic txns — bounded by the spike gate; revisit if p99 > 50ms"). With **two or more distinct dissents**, a `Peer(s) | Argument | Resolution / trigger` table beats stacked lines. When dissent is minor, fold it into a Why bullet instead. Never compress dissent to a bare model name — the argument and its resolution path are the signal.

4. **Why** — 2-4 tight bullets of decisive reasoning. Each bullet is conclusion **plus** its basis ("Removes the shared-state layer — root cause of 3/5 recent incidents"), never a bare label ("simpler"). Fold confidence basis in when it helps.

5. **Do now** — 1-3 verb-first actions, often a single arrow chain (`spike B → kill the A RFC → freeze schema`). Skip if the verdict is itself the action.

**Mode adaptation (the verdict line never moves; the body flexes):**

| Mode | Tally | Dissent line | Body |
|------|-------|--------------|------|
| **Converged** — all perspectives agree | omit | omit | Why (+ Do now). Often 3-5 lines total. |
| **Material disagreement** — ≥2 agents oppose on the core question (not peripheral caveats), not following lineage cleanly | omit | fold into Why | `Tradeoff:` (the two options + what each optimizes) before Do now |
| **Cross-model break** — subagents converge, a parallax or gpt-pro lineage dissents | **mandatory** | **leads the body**, above Why | cap confidence at Moderate |
| **Deliverable** | per the run | per the run | artifact right after the verdict line; Why = design rationale; Do now = integration/review |

- On a **cross-model break**, two or more cross-model peers (Codex, DeepSeek, MiMo, GLM, Grok, **gpt-pro**) dissenting in the *same direction* is an especially strong signal — say so. The Moderate cap fires when any **external non-Claude lineage** dissents — a parallax lineage **or gpt-pro**. One caveat about browsing: when a dissent turns on a *cited external fact the other agents never had* — gpt-pro in a default front-loaded run (the only tier browsing there), or any tier on a live-research run where each researched independently and surfaced different sources — that is an **information asymmetry, not a shared-blind-spot signal** — spot-check the cited source, propagate the fact, and re-judge rather than reflexively capping; cap only when the dissent is a genuine reasoning disagreement over the same evidence.
- **All-subagent run** (no parallax dispatched — e.g. every cross-model tier excluded via natural language): a cross-model break is impossible, so within-Claude splits are **Material disagreement** however clean the split looks — no tally, no Moderate cap. Flag the missing cross-model diversity, since the `⚠`-absence all-clear cannot mean cross-model corroboration here.
- **`Tradeoff:`** (material disagreement) is an option comparison — render it as a small table, not prose:

  | Option | Optimizes | Cost / risk |
  |--------|-----------|-------------|
  | A | … | … |
  | B | … | … |

**Banned in the main path:**

- Per-lens attribution ("the Simplicity lens noted…", "Agent A said…"). The model-tier **tally line is the sole exception** (by lineage, not lens). Deeper per-lens notes go in an optional `<details>Per-lens detail</details>` appendix at the very bottom — only if the user asked, or disagreement is deep enough to need a lens-level audit.
- Synthesis narration ("Weighing the perspectives…", "After considering the arguments…"). The verdict line and Why carry the reasoning.
- Generic contingencies ("if requirements change"). Only concrete, observable triggers.
- Routine chrome: emoji beyond the reserved `⚠`, ASCII-art boxes, traffic-light symbols. Use words for confidence and `✓`/`⚠` in the tally. A plain `→` (or `then`) as a prose separator in a Do-now chain or a tally takeaway is fine — it is text, not chrome.
- Standalone `Confidence and basis` / `Key dissent` / `Contingencies` sections. Their content folds into the verdict line, Dissent line, and Why — and only when decision-relevant.

**Cross-model weighting (internal — surfaces through the verdict line, tally, and Why):**

- Judge each answer on its reasoning and evidence, not on the fact that an agent produced it (discount weak reasoning, never the model label). Discarding a shallow, wrong-premise, off-topic, or unsupported answer entirely is valid — say so in Why when a notable perspective is set aside.
- Ignore any self-reported confidence a dispatched agent volunteers (numeric, %, or High/Med/Low) — prism confidence is computed by the orchestrator from cross-model agreement + reasoning quality, never from an agent's self-score, so a confident-but-shallow lens must not outweigh a well-reasoned dissent. Treat a volunteered score only as a cue to read the caveat beside it; do not instruct dispatched agents to self-score.
- Same-model convergence is discounted (shared training = shared blind spots); parallax (cross-model) confirmation or dissent carries outsized weight — model diversity is prism's entire point.
- A single well-reasoned point can beat consensus driven by shared priors. If you cannot articulate why dissent is wrong, downgrade confidence on the verdict line rather than expanding dissent into a paragraph.

Agents advise; they do not vote. The tally shows lineage alignment, not the decision rule — convergence is evidence, not a vote.

### Step 5: Grounding check

Re-read the user's original question. Verify:

- Your synthesis answers it directly. If they asked for a deliverable, you produced one.
- The header leads — the single `·`-separated verdict line only when it fits one short line, otherwise the two-column table (dense = verdict >~12 words, a caveat, or a dissent note) — in fixed field order (`verdict · conf: … · n/total agree[ · ⚠ dissent]`), with confidence shown and any caveat in its own row, not the verdict.
- On a cross-model break, the tally line and a dedicated Dissent line are present and sit above Why; on a material disagreement a `Tradeoff:` line carries the split (no tally); on full convergence all three are omitted.
- No per-lens summary appears in the main path — the model-tier tally is by lineage, not lens; lens-by-lens notes live only in an optional appendix.
- Every retained dissent, caveat, or trigger changes a decision, confidence level, or next action.
- **Live-research runs:** before treating divergence as a reasoning split, compare the agents' listed sources — a dissent resting on a fact the others never had is an *information asymmetry* (propagate the fact and re-judge), not a shared-blind-spot signal; spot-check decision-changing sources and confirm each material external claim is cited.

Optionally delete all Prism temp files with `~/.claude/skills/prism/scripts/prism-launch clean <id>` (or `rm -f /tmp/prism-<unique-id>*`) — both clear the whole `/tmp/prism-<unique-id>` prefix: shared context (`.md`), dispatch file (`.dispatch`), normalized/config JSON, manifest, rendered launchers, parallax out logs, and result sentinel.

## Guards

- **No recursion (HARD RULE):** Dispatched agents must never spawn child agents or invoke any dispatching skill (prism, relay, gpt-pro-relay, deep-research, or any cross-model dispatch tool). Read-only analysis skills are permitted. The Constraints section and launcher prompts both enforce this — do not weaken or omit either. For Parallax, keep the anti-recursion warning at the top of every heredoc (Codex, DeepSeek, MiMo, GLM, Grok launchers); the orchestrator-composed gpt-pro launcher carries the same guard as its first line (plus the instruction-inversion clause — see GPT-Pro tier).
- **No contamination:** Write the shared context file and compose all launcher prompts before any launch. Do not modify the shared file or revise prompts after seeing early agent outputs.
- **No all-same-model dispatch (HARD RULE):** The dispatched parallax peers must equal the resolved parallax counts — `6N` by default (`N` each of Codex, Grok Build, Grok Composer, DeepSeek, MiMo, GLM), minus any tier excluded by natural language. Via `prism-launch`, the manifest's `counts` derives this from the config, and the single `parallax` call emits exactly those peers — so the historical "forgot a relay call" failure cannot occur. In the manual fallback, the total count of Bash relay calls must equal that sum; if the planned dispatch has zero relay calls but any configured count is non-zero, fix before launching.
- **No early synthesis (HARD RULE):** Do not synthesize until every dispatched agent has returned its completion notification. "Subagents are done, Codex relay is still running" or "Codex came back, DeepSeek is still running" are not reasons to proceed — they are the expected state. Proceeding without any tier's results voids the entire Prism run.
- **No side effects:** Dispatched agents must not edit files, commit, push, or invoke any skill with side effects (e.g., push, xurl, todo, goal-drive). Read-only analysis skills are allowed. The only permitted write is the relay response file (.res.md).
- **No working-tree reverts (HARD RULE):** Neither the orchestrator nor any dispatched agent may run a git command that discards or hides uncommitted work — `git restore`, `git checkout <path>` / branch switch, `git reset`, `git stash`, `git clean`, `git rm`. The repo routinely holds the user's *or a concurrent prism/Claude session's* uncommitted changes; reverting them is unrecoverable (this is a real incident, not hypothetical). Only read-only git is allowed: `git status`, `git diff`, `git log`, `git show`. To get a clean baseline, commit your own work — never undo someone else's. See Step 3.5.

## Degrees of Freedom

The core principle (redundancy, not division of labor), the launcher-template structure, and the hard completion gate are load-bearing — do not relax them. Flexible: lens choices, synthesis body framing, agent count beyond the minimum, pre-launch check order.

**Synthesis adaptation:** the verdict line is fixed and always first (Step 4); the body below it flexes — merge, reorder, or add task-specific sections when the task calls for it. The verdict line stays put regardless, so the first-glance scan always works.

## When to Use Prism

Use Prism when a task benefits from diverse, redundant judgment and the shared context fits cleanly across all agents.

Skip Prism for trivial lookups, deterministic transforms, single-correct-answer tasks, or tasks requiring parallel mutations of shared state.

Once you've decided to use it, resolve config via the **Config-presence gate**: with an explicit number, honor the parsed shape verbatim (omitted dimensions fall to `N=1`/`M=0`); with none, autonomously pick `N` and `M` per **Choosing N and gpt-pro** (anchored at `N=1`, scaling only when decision risk justifies the cost).
