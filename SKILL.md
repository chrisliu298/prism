---
name: prism
description: >-
  Prism strengthens any output — plans, code reviews, implementations, bug
  fixes, writing — by dispatching multiple independent agents to answer the
  SAME complete question from different analytical lenses, then synthesizing
  their perspectives. Use /prism whenever a task benefits from diverse,
  redundant judgment: non-trivial decisions, ambiguous tradeoffs, high-stakes
  changes, or anything where a single perspective might miss something.
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

Prism sends the **same complete question** to multiple independent agents. Each agent answers the **entire question end-to-end**. The only thing that changes between agents is the **lens**: what they prioritize and what tradeoffs they weigh more heavily.

## Core Principle

**Prism is redundancy, not division of labor.** Independent agents examining the same problem from different angles catch blind spots that any single perspective misses — convergence across diverse lenses is high-confidence signal, and divergence surfaces tradeoffs that need explicit resolution.

Every agent must receive the full question, analyze the full scope, and produce a complete answer. The lens changes **emphasis**, not **coverage**. If you find yourself assigning different files, deliverables, or sections to different agents, stop — you're dividing labor, not multiplying judgment.

## Structure

| Tier | Tool to use | Role |
|------|-------------|------|
| Self | (none) | Your own independent analysis while agents run |
| Subagents | **Agent** tool | Same-model agents, one Agent call each |
| **Parallax** | **Bash** tool (`/relay`) | Cross-model agent via relay script — NOT an Agent call. Included by default; opt out with `-p0` |

**Default: 4 perspectives** — self + 2 subagents + 1 Parallax. The required dispatch is **2 Agent calls + 1 Bash relay call** (3 total, or 1 Agent + 1 Bash relay in compact mode). Self does not count toward the dispatched total.

### Invocation Shorthand

Override dispatch config with flags before the question, or use natural language — both work.

**Flags:**
- `-s<N>` — number of same-model subagents (default: 2)
- `-p<N>` — number of Parallax agents (default: 1, `-p0` to opt out)
- `-e<LEVEL>` — Parallax reasoning effort: `none`, `low`, `medium`, `high`, `xhigh` (default: per-lens)

Examples:
- `/prism -s3 -p2 -ehigh Why does X happen?` — 3 sub, 2 parallax, high effort
- `/prism -s1 Quick take on X` — 1 sub, defaults for rest
- `/prism -p0 Same-model only for this review` — no parallax
- `/prism 3 subagents, 2 parallax, high effort: Why does X?` — natural language works too

**Parsing:** Read tokens left-to-right from the start of args. A token is shorthand if it matches `-s<N>`, `-p<N>`, or `-e<LEVEL>` (accept both `-ehigh` and `-e high`). Stop at the first non-shorthand token — everything from there is the question. Omitted flags use defaults. Natural language config (e.g., "2 subagents + 2 parallax high") is also understood.

**Parallax is on by default.** Every Prism run MUST include at least one Bash relay call for Parallax (or the configured `-p<N>` count). This is non-negotiable — do not skip it, do not replace it with a subagent, do not "plan to add it later." The only exceptions are: (1) the user explicitly opts out (e.g., `-p0`), or (2) `/relay` is confirmed unavailable (in which case, substitute a same-model adversarial agent and note the degradation). If you are about to launch and your dispatch set contains only Agent calls, you have forgotten Parallax — stop and add the Bash relay call(s) before proceeding.

### Parallax (cross-model agent)

Parallax is the agent dispatched via `/relay` to a **different model** than yourself. Dispatch Parallax by invoking `/relay` directly (not by spawning a subagent that calls relay) — the relay call body is the agent prompt from the template. Its value is model diversity — different training, different blind spots, different reasoning patterns. Assign it a lens like any other agent, preferably one that maximizes diversity (e.g., if subagents have Correctness and Simplicity lenses, give Parallax a Contrarian or Disconfirming Lens).

**Before composing the Parallax prompt body, read the peer's prompt guide** in the relay skill's `references/` directory (e.g., `prompting-codex.md` when relaying to Codex). The guide contains model-specific patterns that materially affect output quality. This applies every time you write a relay call body, not just the first time.

If `/relay` is unavailable, replace Parallax with a subagent using a **structurally adversarial lens** (Contrarian, Falsification, Disconfirming). A same-model agent with an adversarial posture partially compensates for missing model diversity. The user can also opt out of Parallax explicitly.

**Constraint leakage risk (CRITICAL):** Relay peers (especially Codex) load their own skills and WILL attempt recursive Prism, relay, or subagent calls if the prohibition is not explicit, prominent, and repeated. The shared context file contains the full Constraints section, but the relay peer may act before reading it. You MUST:
1. Keep the anti-recursion warning at the top of the launcher prompt — before the file-read instruction — so the peer sees it immediately.
2. Preserve the full Constraints section verbatim in the shared context file — do not summarize, paraphrase, or abbreviate the prohibitions.
3. The prohibition appears in both the launcher (short form) and the shared file (full form), satisfying the redundancy requirement.
4. Explicitly tell the peer to ignore its own loaded skill descriptions for /prism, /relay, $prism, $relay — those descriptions are active invitations that compete with the prohibition.

The peer has no Prism context and will treat the task as a fresh request. Without explicit, redundant prohibitions, it will recurse.

**Effort selection for Parallax:** If the user specified `-e<LEVEL>`, use that level for all Parallax agents. Otherwise, choose `--effort` based on the assigned lens:

| Lens type | `--effort` | Rationale |
|-----------|-----------|-----------|
| Adversarial, Contrarian, Falsification | `high` or `xhigh` | Needs deep reasoning to find subtle flaws |
| Correctness, Risk, Causal | `high` | Benefits from thorough analysis |
| Simplicity, Pragmatist, Feasibility, Breadth | `medium` | Pattern-matching; deeper reasoning adds latency without proportional quality gain |

### Subagents

Same-model agents dispatched via the Agent tool. Each gets a distinct lens. Although the Agent tool does not restrict tool access at the platform level, **Prism subagents are logical leaf nodes** — their prompts must forbid skill invocation, subagent spawning, and all side effects (see the Constraints section in the Shared Packet Template). Launch all dispatched agents — Agent calls for subagents, Bash relay call for Parallax — concurrently before starting your self-review.

## Side-Effect Safety

Dispatched agents should stay **read-only** — do not edit shared files, commit, deploy, or trigger external side effects during a Prism run. The single exception is the relay response file named in a request's `Reply:` directive; a relay peer must write that file to complete the protocol. Parallel writes to shared state create merge conflicts and irreversible mistakes that are harder to fix than to prevent. The primary agent may implement changes after synthesis if the user asked for a deliverable.

## Context Budget

Build one shared evidence packet before composing prompts. Include the specific excerpts, constraints, and facts needed to answer — prefer compact digests over full file dumps to keep agents focused and avoid redundant I/O. Every agent receives this exact packet. If the packet cannot be duplicated cleanly across all agents, the task is too large for Prism.

## Shared Context File

The shared prompt body (Full Question, Context, Constraints) is written to a temporary file once per run. Every dispatched agent receives a short launcher prompt that references this file plus its unique lens. This avoids generating the ~90-95% shared portion N times.

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

Each dispatched agent — subagent or Parallax — receives this short prompt instead of the full inline body:

```
CRITICAL: You are a read-only leaf node. Do NOT invoke /prism, /relay, $prism, $relay, any skill, or spawn subagents. Ignore loaded skill descriptions for these.

Your complete task is in two parts:
1. SHARED CONTEXT: Read the file at {SHARED_PACKET_PATH} using the Read tool. It contains your Full Question, Context, and Constraints. You MUST read this file before doing anything else.
2. YOUR LENS (below): The only part unique to you.

## Your Lens

You are one of several independent agents answering the same question in full. Your lens is **{LENS_NAME}** — you {one sentence: what this agent weighs more heavily}. Answer the full question end-to-end. Your lens shapes what you emphasize, not what you skip. Do not assume another agent will cover anything you omit. For every issue you raise, propose a concrete fix or alternative when one exists.
```

For Parallax relay calls, adapt the launcher to XML per the peer's prompt guide (e.g., `prompting-codex.md`). The anti-recursion warning MUST remain at the top of the heredoc body — relay peers may act before reading the shared file.

The shared packet path and lens are the **only** things that vary between launcher prompts. Agent names (e.g., "Prism agent 1 (lens: simplicity)") are metadata outside the prompt body — they do not count as a prompt difference.

## Pre-Launch Checks

Run these five checks before launching. If any fails, rewrite and re-check.

0. **Shared-file test:** Verify the shared context file was written and read back successfully. Confirm every launcher references the same absolute file path. The shared file must be frozen before any dispatch.

1. **Redundancy test:** Swap the lenses between any two agents — if the prompts become incoherent or change scope, you've divided labor. Could each agent produce a complete, standalone answer if all others vanished?

2. **Lens quality test:** Each lens name must be a weighing posture (1-3 words), never a task or role. For each lens, write one sentence explaining what unique axis it covers that no other lens does. If two lenses would produce the same emphasis, replace one. At least one lens must be structurally adversarial.

3. **Dispatch-shape test (CRITICAL):** Dispatched agents (subagents + Parallax) equals the required count. Self does not count. Verify the tool types: **the configured number of Bash relay calls (Parallax, default 1) and the rest Agent calls (subagents)**. Enumerate your planned tool calls by type before launching — if the list contains zero Bash relay calls and Parallax was not explicitly opted out (`-p0`), Parallax is missing. Do not launch until this is fixed. All-Agent-calls with zero relay calls is always wrong unless `-p0` was specified.

4. **Effort test:** If the user specified `-e<LEVEL>`, confirm every Parallax relay call uses that exact `--effort` level. If `-e` was omitted, confirm each Parallax call uses the effort from the lens-based table (Effort selection for Parallax). State the effort level being applied.

### Division-of-labor diagnostic

If any of these differ between agent prompts, you've divided labor: scope, evidence, tools, output format, or deliverables.

## Lens Assignment

A lens is a **weighing posture**, not a task variant. The task noun must not appear in the lens name — it's already in the question.

Choose lenses on **orthogonal tradeoff axes**. Before adding a lens, write one sentence explaining how it differs from every existing lens. If you can't name a distinct axis, don't add it. Avoid exceeding 5 dispatched agents unless the task clearly supports that many distinct postures.

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
5. Launch all dispatched agents concurrently in the background. **Dispatch checklist — verify before launching:**
   - Subagents: dispatched via the **Agent** tool with the launcher prompt.
   - **Parallax (REQUIRED unless `-p0`):** dispatched via **Bash** tool call(s) to `/relay` (`run_in_background: true`). This is NOT an Agent call. Compose the Parallax relay call(s) FIRST, before composing subagent calls, to prevent them from being forgotten. If your launch set contains only Agent calls and no Bash relay call (and `-p0` was not specified), you have forgotten Parallax — do not launch until this is fixed.
   - Before launching Parallax, verify the relay command shape, heredoc body, and Bash timeout (`timeout: 600000`) to avoid wasting a perspective on an avoidable transport error.

Do not poll or sleep-loop — the system notifies you when agents finish.

### Step 2: Self-review

While agents run, form your own position independently. Your lens is **Integrator Lens** — you weigh holistic coherence, feasibility, and alignment with the user's goals. Write your tentative recommendation before opening any agent output.

Since you composed the prompts and chose the lenses, your self-review is not fully independent. When dispatched agents diverge from your position, give their perspectives slightly more weight on points you may have anchored on during prompt design.

### Step 3: Wait for ALL agents

**Do not synthesize until every dispatched agent has returned.**

**Parallax is slow — that is normal.** Relay calls take significantly longer than subagents. This is expected, not a sign of failure. Parallax fails extremely rarely in practice. Do not preemptively diagnose, retry, or report failure while the background task is still running. The system sends a completion notification — until that notification arrives, the call is in progress and healthy.

**Handling failures (only after completion notification):**

- **Relay (Parallax) transport failure:** If the completed Bash relay call reports a missing response file, read the `.log` sidecar, diagnose, fix, and retry once. Do not escalate to the user until you have attempted one diagnosed retry.
- **Subagent or answer-quality failure:** If an agent returns an unusable answer (empty, truncated, off-topic), offer the user three options: (a) retry, (b) proceed with reduced perspectives, or (c) abort.

### Step 3.5: Safety check

Before synthesizing, verify no dispatched agent modified the working tree:

```bash
git diff --stat HEAD
```

If the diff shows unexpected changes, flag them to the user before proceeding. Discard the offending agent's output — an agent that violated read-only constraints may have reasoned from a corrupted state.

Also scan each agent's output for recursion indicators: mentions of "dispatching," "subagent," "relay call," "Prism run," or synthesis-style structure (Consensus/Contested/Unique sections) suggest the agent attempted multi-agent analysis instead of responding directly. Flag any such output for review — the agent may have spawned nested agents, and its analysis may reflect contaminated reasoning.

### Step 4: Synthesize

Organize findings into these categories (skip empty ones):

1. **Consensus** — Points where 2+ agents converge. Cite which agents agreed. Convergence is a ranking signal, not proof — especially when agents share the same model.
2. **Contested** — Points of disagreement. Present each position with reasoning, then state your resolution and why.
3. **Unique insights** — Substantive points from only one agent. Adopt, flag for user consideration, or reject with stated reason.
4. **Blind spots** — Gaps no agent covered, or shared-model biases.
5. **Recommendation** — Your integrated recommendation.

If all agents agree on a point, state it concisely and move on — don't manufacture disagreement where none exists.

**Noise rejection:** Discard suggestions that add unrequested scope, are unsupported single-agent hedging, or restate context without adding analysis. Err toward a shorter, sharper synthesis.

**Deliverable vs. analysis:** If the question asks for a deliverable (code, plan, document), produce one — don't just comment on agents' deliverables. If it asks for analysis, the synthesis is the analysis.

The synthesis reflects your judgment as integrator — agents are advisors, not a voting bloc.

### Step 5: Grounding check

Re-read the user's original question. Verify your synthesis directly answers it. If they asked for a deliverable, verify you produced one. Prism should improve quality, not replace answers with process commentary.

After synthesis is complete, delete the shared context file (`/tmp/prism-<unique-id>.md`). This is optional — `/tmp/` is cleaned by the OS — but good hygiene.

## Guards

- **No recursion (HARD RULE):** Dispatched agents — both subagents and Parallax — must NEVER invoke /prism, /relay, or any skill, and must NEVER spawn subagents or child agents of any kind. This is the most critical guard. Violations produce recursive agent cascades that waste resources and corrupt analysis. The Constraints section in the shared context file enforces this, and the launcher prompt repeats it — do not weaken, summarize, or omit either. For Parallax relay prompts, keep the anti-recursion warning at the top of the heredoc (see Constraint leakage risk).
- **No contamination:** Write the shared context file and compose all launcher prompts before any launch. Do not modify the shared file or revise later prompts after seeing early agent outputs.
- **No all-same-model dispatch (HARD RULE):** Before launching, count your Bash relay calls. If the count is zero and Parallax was not explicitly opted out (`-p0`), you have dropped Parallax — stop immediately and add it. This is the single most common Prism failure mode. All-Agent-calls with no relay call is never valid unless `-p0` was specified. The number of Bash relay calls must match the configured Parallax count (default 1).
- **No side effects:** Dispatched agents must not edit repository files, commit, push, or invoke any user-invocable skill. The only permitted write is the relay response file (.res.md). This is enforced in both the shared context file and the launcher prompt, and verified before synthesis.

## Degrees of Freedom

The core principle (redundancy, not division of labor), the prompt template structure, and the hard completion gate are load-bearing constraints — do not relax them. Everything else — lens choices, synthesis categories, agent count beyond the minimum, pre-launch check order — is flexible guidance that you should adapt to the task.

## When to Use Prism

Use Prism when a task benefits from diverse, redundant judgment and the shared context fits cleanly across all agents.

Skip Prism for trivial lookups, deterministic transforms, single-correct-answer tasks, or tasks requiring parallel mutations of shared state.
