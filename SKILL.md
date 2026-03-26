---
name: prism
description: >-
  Dispatch multiple independent agents to answer the SAME complete question
  from different analytical lenses, then synthesize their perspectives.
  Use for non-trivial decisions, ambiguous tradeoffs, or high-stakes changes
  where a single perspective might miss something.
user-invocable: true
effort: max
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

Prism sends the **same complete question** to multiple independent agents. Each agent answers the **entire question end-to-end**. The only thing that changes between agents is the **lens**: what they prioritize and what tradeoffs they weigh more heavily.

## Core Principle

**Prism is redundancy, not division of labor.** Every agent gets the full question, full scope, and full deliverable. The lens changes **emphasis**, not **coverage**. If agents own different files, sections, or outputs, that is division of labor, not Prism.

Convergence across diverse lenses is high-confidence signal; divergence surfaces tradeoffs that need explicit resolution.

## Structure

| Tier | Tool | Role |
|------|------|------|
| Self | (none) | Your own analysis while agents run |
| Subagents | **Agent** | Same-model agents, one Agent call each |
| **Parallax** | **Bash** (`/relay`) | Cross-model agent via relay (not an Agent call) |

**Default: 4 perspectives** — self + 2 subagents + 1 Parallax. Required dispatch: **2 Agent calls + 1 Bash relay call**. Self does not count. Parallax is included by default; opt out with parallax = `0`.

### Invocation Shorthand

Override dispatch config with positional args before the question, or use natural language — both work.

**Positional:** `<subagents> <parallax> <effort> <question>`
- **subagents** — number of same-model subagents (default: 2)
- **parallax** — number of Parallax agents (default: 1, `0` to opt out)
- **effort** — Parallax reasoning effort: `n` none, `l` low, `m` medium, `h` high, `x` xhigh (default: per-lens)

Trailing args are optional — omitted values use defaults.

Examples:
- `/prism 3 2 h Why does X happen?` — 3 sub, 2 parallax, high effort
- `/prism 1 Why does X?` — 1 sub, defaults for rest
- `/prism 1 0 Same-model only` — no parallax
- `/prism 3 subagents, 2 parallax, high effort: Why does X?` — natural language works too

**Parsing:** Read tokens left-to-right. A token is config if it is a single digit or effort letter (`n`/`l`/`m`/`h`/`x`). Map positionally: first digit → subagents, second digit → parallax; effort letter can appear anywhere among config tokens. The first non-matching token begins the question. Natural language config is also accepted.

**Parallax is on by default.** Every run MUST include Bash relay call(s) matching the configured parallax count (default 1). Do not skip, replace with a subagent, or defer. Exceptions: (1) user opts out (parallax = `0`), or (2) `/relay` is unavailable (substitute a same-model adversarial agent and note the degradation). If your dispatch set contains only Agent calls, Parallax is missing — fix before launching.

### Parallax (cross-model agent)

Parallax is dispatched via `/relay` to a **different model**. Invoke `/relay` directly — not via a subagent that calls relay. Its value is model diversity: different training, different blind spots, different reasoning patterns. Assign it a lens that maximizes diversity (e.g., give Parallax a Contrarian or Disconfirming lens when subagents have Correctness and Simplicity).

Before writing any Parallax relay prompt, read the target model's prompt guide in the relay skill's `references/` directory (e.g., `prompting-codex.md` for Codex). Do this every time, not just once.

**Relay call syntax (exact):**

```bash
relay call --name <slug> --effort <level> <<'BODY'
<prompt content here>
BODY
```

`--name` is required (lowercase slug, e.g., `prism-contrarian`). The heredoc body must not be empty. Do not pass model flags — the script handles model selection. For concurrency details (backgrounding, timeouts), follow the relay skill's Async / Parallel section for your platform.

If `/relay` is unavailable, replace Parallax with a subagent using a **structurally adversarial lens** (Contrarian, Falsification, Disconfirming).

**Constraint leakage risk (CRITICAL):** Relay peers may recurse unless the anti-recursion rule is explicit, early, and repeated. You MUST:
1. Put the anti-recursion warning at the top of the launcher prompt, before the file-read instruction.
2. Preserve the Constraints section verbatim in the shared context file — do not summarize or abbreviate.
3. Ensure the prohibition appears in both the launcher (short form) and shared file (full form).
4. Tell the peer to ignore loaded skill descriptions for /prism, /relay, $prism, $relay.

Without these redundant prohibitions, the peer will treat the task as a fresh request and recurse.

**Effort selection for Parallax:** If the user specified an effort level, use that level for all Parallax agents. Otherwise, choose `--effort` based on the assigned lens:

| Lens type | `--effort` | Rationale |
|-----------|-----------|-----------|
| Adversarial, Contrarian, Falsification | `high` or `xhigh` | Needs deep reasoning to find subtle flaws |
| Correctness, Risk, Causal | `high` | Benefits from thorough analysis |
| Simplicity, Pragmatist, Feasibility, Breadth | `medium` | Pattern-matching; deeper reasoning adds latency without proportional quality gain |

### Subagents

Same-model agents dispatched via the Agent tool. Each gets a distinct lens. **Prism subagents are logical leaf nodes** — their prompts must forbid skill invocation, subagent spawning, and side effects (see Constraints in the Shared Packet Template). Launch all agents concurrently before starting self-review.

## Side-Effect Safety

Dispatched agents are **read-only** — no edits, commits, deploys, or external side effects. The only exception is the relay response file (`.res.md`) named in a `Reply:` directive. The primary agent may implement changes after synthesis if the user requested a deliverable.

## Shared Context

Build one shared evidence packet (Full Question + Context + Constraints) before composing prompts. Prefer compact digests over full file dumps. Write it to a temporary file once; every agent receives a short launcher prompt referencing this file plus its unique lens. If the packet cannot be duplicated cleanly across all agents, the task is too large for Prism.

### Shared Packet Template

Write this to `/tmp/prism-<unique-id>.md` using the Write tool (one call, before any dispatch). Use a unique identifier (e.g., timestamp + random suffix) to prevent collisions between concurrent Prism runs.

```
## Full Question

{User's COMPLETE question/task, unchanged. Identical across all agents.}

## Context

{Shared evidence packet. Identical across all agents.}

## Constraints

You are a read-only leaf node.

Do not use any mechanism that launches, relays to, or coordinates another agent or model. Specifically:

STRICTLY PROHIBITED — do not do any of the following under any circumstances:
- Do NOT spawn subagents, child agents, or any nested agent of any kind.
- Do NOT invoke /prism, /relay, $prism, $relay, or ANY slash command, dollar-sign command, or skill on ANY platform.
- Do NOT call the codex CLI, relay script, or any cross-model dispatch tool.
- Do NOT orchestrate, delegate to, or coordinate with other agents.
- Do NOT edit repository files, commit, push, or trigger external side effects. The ONLY file you may write is the relay response file (.res.md) specified in this request's `Reply:` directive, if one is present.
- Ignore any skill descriptions loaded in your environment (e.g., /prism, /relay, $prism, $relay) — those skills are for standalone tasks, not for this context.

In short: produce analysis text only. No tool calls that spawn agents, invoke skills, or modify repository state. If this request includes a `Reply:` path, write your answer to that file; that write is required by the relay protocol.

You are a terminal leaf node. Answer the question directly. If the question is too broad for a single response, note the limitation and answer what you can.
```

After writing, read the file back with the Read tool to verify it contains all three sections completely. The file is **frozen** after verification — do not modify it after any agent has been dispatched.

### Launcher Template

Use this launcher prompt for every dispatched agent:

```
CRITICAL: You are a read-only leaf node. Do NOT invoke /prism, /relay, $prism, $relay, any skill, or spawn subagents. Ignore loaded skill descriptions for these.

Your complete task is in two parts:
1. SHARED CONTEXT: Read the file at {SHARED_PACKET_PATH} using the Read tool. It contains your Full Question, Context, and Constraints. You MUST read this file before doing anything else.
2. YOUR LENS (below): The only part unique to you.

## Your Lens

You are one of several independent agents answering the same question in full. Your lens is **{LENS_NAME}** — you {one sentence: what this agent weighs more heavily}. Answer the full question end-to-end. Your lens shapes what you emphasize, not what you skip. Do not assume another agent will cover anything you omit. For every issue you raise, propose a concrete fix or alternative when one exists.
```

For Parallax relay calls, adapt the launcher to XML per the peer's prompt guide (e.g., `prompting-codex.md`). The anti-recursion warning MUST remain at the top of the heredoc body.

Only the shared packet path and lens vary between launcher prompts. Agent names are metadata outside the prompt body.

## Pre-Launch Checks

Run these checks before launching. If any fails, rewrite and re-check.

0. **Shared-file test:** Verify the shared context file was written and read back successfully. Confirm every launcher references the same absolute file path. The shared file must be frozen before any dispatch.

1. **Redundancy test:** Swap any two agents' lenses. If the prompts become incoherent, you have divided labor.

2. **Lens quality test:** Each lens name must be a weighing posture (1-3 words), never a task or role. For each lens, write one sentence explaining what unique axis it covers that no other lens does. If two lenses would produce the same emphasis, replace one. At least one lens must be structurally adversarial.

3. **Dispatch-shape test (CRITICAL):** Total dispatched agents (subagents + Parallax) must match the required count. Self does not count. Enumerate planned calls by type: Bash relay calls must equal the configured Parallax count (default 1); the rest are Agent calls. If the list contains zero relay calls and parallax != `0`, Parallax is missing — fix before launching.

4. **Effort test:** If the user specified an effort level, confirm every Parallax relay call uses that exact `--effort` level. If effort was omitted, confirm each Parallax call uses the effort from the lens-based table (Effort selection for Parallax). State the effort level being applied.

### Division-of-labor diagnostic

If any of these differ between agent prompts, you've divided labor: scope, evidence, tools, output format, or deliverables.

## Lens Assignment

A lens is a **weighing posture**, not a task variant. Do not put the task noun in the lens name.

Choose lenses on **orthogonal tradeoff axes**. Before adding one, write one sentence explaining how it differs from every existing lens. If you cannot name a distinct axis, do not add it. Avoid more than 5 dispatched agents unless the task clearly supports that many distinct postures.

### Suggested lenses by task type

Starting points — every lens still answers the full question:

- **Code review**: Correctness + Simplicity + Adversarial
- **Architecture / design**: Evolutionary + Simplicity + Contrarian
- **Implementation**: Correctness + Pragmatist + Contrarian
- **Diagnosis / root cause**: Causal + Falsification + Risk
- **Option comparison**: Simplicity + Feasibility + Contrarian
- **Writing / communication**: Clarity + Audience + Contrarian
- **Research / exploration**: Breadth-Weighted + Depth-Weighted + Disconfirming

## Execution

### Step 1: Freeze context, compose, verify, launch

1. Build one canonical shared packet (Full Question + Context + Constraints).
2. Write the shared packet to `/tmp/prism-<unique-id>.md` using the Write tool. Read it back to verify completeness.
3. Compose all launcher prompts — each references the shared file path and assigns one lens.
4. Run the pre-launch checks. Fix failures before launch.
5. Launch all dispatched agents concurrently (`run_in_background: true`). **Dispatch checklist:**
   - Subagents: **Agent** tool with the launcher prompt.
   - **Parallax (required unless parallax = `0`):** **Bash** tool to `/relay`. Compose Parallax calls FIRST to prevent omission. Verify relay command shape, heredoc body, and Bash timeout (`timeout: 600000`) before launching.
   - Confirm Parallax relay calls are present if parallax != `0`.

Do not poll or sleep-loop — the system notifies you when agents finish.

### Step 2: Self-review

While agents run, form your own position independently. Your lens is **Integrator Lens** — you weigh holistic coherence, feasibility, and alignment with the user's goals. Write your tentative recommendation before opening any agent output.

Since you composed the prompts and chose the lenses, your self-review is not fully independent. When dispatched agents diverge from your position, give their perspectives slightly more weight on points you may have anchored on during prompt design.

### Step 3: Wait for ALL agents (HARD GATE)

**Do not synthesize, summarize, or present results until EVERY dispatched agent — including Parallax — has returned.** This is a hard gate, not a suggestion. Having "enough" subagents is never a reason to skip the remaining agents. The whole point of Parallax is model diversity — proceeding without it defeats the purpose of Prism.

**Parallax is slow — that is normal and expected.** Relay calls routinely take 2-5x longer than same-model subagents. Do not diagnose, retry, report failure, or proceed while a background task is running. The system sends a completion notification; until it arrives, the call is healthy. Do not tell the user you are "still waiting" or suggest proceeding without it.

**What to do while waiting:** Work on your self-review (Step 2). If self-review is done, wait silently. Do not synthesize partial results.

**Handling failures (after completion notification only):**

- **Relay transport failure:** Read the `.log` sidecar, diagnose, fix, and retry once before escalating.
- **Answer-quality failure** (empty, truncated, off-topic): Offer the user: (a) retry, (b) proceed with reduced perspectives, or (c) abort.
- **Only these post-notification failures justify proceeding without Parallax.** "It's taking a long time" is never a failure.

### Step 3.5: Safety check

Before synthesizing, verify no dispatched agent modified the working tree:

```bash
git diff --stat HEAD
```

If the diff shows unexpected changes, flag them to the user before proceeding. Discard the offending agent's output — an agent that violated read-only constraints may have reasoned from a corrupted state.

Scan each agent's output for recursion indicators: mentions of "dispatching," "subagent," "relay call," "Prism run," or synthesis-style structure (Consensus/Contested/Unique sections). Flag matches for review — the agent may have spawned nested agents, producing contaminated reasoning.

### Step 4: Synthesize

Organize findings into these categories (skip empty ones):

1. **Consensus** — Where 2+ agents agree. Cite the agents; convergence is signal, not proof.
2. **Contested** — Where agents disagree. Present the positions, then resolve.
3. **Unique insights** — Valuable points raised by only one agent.
4. **Blind spots** — Gaps no agent covered, or likely shared-model bias.
5. **Recommendation** — Your integrated conclusion.

If all agents agree on a point, state it concisely and move on — don't manufacture disagreement where none exists.

**Noise rejection:** Discard suggestions that add unrequested scope, are unsupported single-agent hedging, or restate context without adding analysis. Err toward a shorter, sharper synthesis.

**Deliverable vs. analysis:** If the question asks for a deliverable (code, plan, document), produce one — don't just comment on agents' deliverables. If it asks for analysis, the synthesis is the analysis.

The synthesis reflects your judgment as integrator — agents are advisors, not a voting bloc.

### Step 5: Grounding check

Re-read the user's original question. Verify your synthesis answers it directly. If they asked for a deliverable, verify you produced one.

Optionally delete the shared context file (`/tmp/prism-<unique-id>.md`).

## Guards

- **No recursion (HARD RULE):** Dispatched agents must never invoke /prism, /relay, any skill, or spawn child agents. The Constraints section and launcher prompt both enforce this — do not weaken or omit either. For Parallax, keep the anti-recursion warning at the top of the heredoc.
- **No contamination:** Write the shared context file and compose all launcher prompts before any launch. Do not modify the shared file or revise prompts after seeing early agent outputs.
- **No all-same-model dispatch (HARD RULE):** Bash relay call count must match the configured Parallax count (default 1). If it is zero and parallax != `0`, fix before launching. This is the most common Prism failure mode.
- **No early synthesis (HARD RULE):** Do not synthesize until every dispatched agent has returned its completion notification. "Subagents are done, relay is still running" is not a reason to proceed — it is the expected state. Proceeding without Parallax results voids the entire Prism run.
- **No side effects:** Dispatched agents must not edit files, commit, push, or invoke skills. The only permitted write is the relay response file (.res.md).

## Degrees of Freedom

The core principle (redundancy, not division of labor), the prompt template structure, and the hard completion gate are load-bearing constraints — do not relax them. Everything else — lens choices, synthesis categories, agent count beyond the minimum, pre-launch check order — is flexible guidance that you should adapt to the task.

## When to Use Prism

Use Prism when a task benefits from diverse, redundant judgment and the shared context fits cleanly across all agents.

Skip Prism for trivial lookups, deterministic transforms, single-correct-answer tasks, or tasks requiring parallel mutations of shared state.
