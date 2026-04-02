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
| **Parallax** | **Bash** (`relay`) | Cross-model agent via relay (not an Agent call) |

**Default: 4 perspectives** — self + 2 subagents + 1 Parallax. Required dispatch: **2 Agent calls + 1 Bash relay call**. Self does not count. Parallax is included by default; opt out with parallax = `0`.

### Invocation Shorthand

Override dispatch config with positional args before the question, or use natural language — both work.

**Positional:** `<subagents> <parallax> <effort> <r> <question>`
- **subagents** — number of same-model subagents (default: 2)
- **parallax** — number of Parallax agents (default: 1, `0` to opt out)
- **effort** — Parallax reasoning effort: `n` none, `l` low, `m` medium, `h` high, `x` xhigh (default: per-lens)
- **r** — enable anonymous peer review round (default: off)

Trailing args are optional — omitted values use defaults.

Examples:
- `prism 3 2 h Why does X happen?` — 3 sub, 2 parallax, high effort
- `prism 1 Why does X?` — 1 sub, defaults for rest
- `prism 1 0 Same-model only` — no parallax
- `prism r Should we launch X?` — defaults + peer review
- `prism 3 1 h r Which architecture should we pick?` — 3 sub, 1 parallax, high effort, peer review
- `prism 3 subagents, 2 parallax, high effort, with review: Why does X?` — natural language works too

**Parsing:** Read tokens left-to-right. A token is config if it is a single digit, effort letter (`n`/`l`/`m`/`h`/`x`), or the literal `r` (peer review). Map positionally: first digit → subagents, second digit → parallax; effort letter and `r` can appear anywhere among config tokens. The first non-matching token begins the question. Natural language config is also accepted.

**Parallax is on by default.** Every run MUST include Bash relay call(s) matching the configured parallax count (default 1). Do not skip, replace with a subagent, or defer. Exceptions: (1) user opts out (parallax = `0`), or (2) `relay` is unavailable (substitute a same-model adversarial agent and note the degradation). If your dispatch set contains only Agent calls, Parallax is missing — fix before launching.

### Parallax (cross-model agent)

Parallax is dispatched via `relay` to a **different model**. Invoke `relay` directly — not via a subagent that calls relay. Its value is model diversity: different training, different blind spots, different reasoning patterns. Assign it a lens that maximizes diversity (e.g., give Parallax a Contrarian or Disconfirming lens when subagents have Correctness and Simplicity).

Before writing any Parallax relay prompt, read the target model's prompt guide in the relay skill's `references/` directory (e.g., `prompting-codex.md` for Codex). Do this every time, not just once.

**Relay call syntax (exact):**

```bash
relay call --name <slug> --effort <level> <<'BODY'
<prompt content here>
BODY
```

`--name` is required (lowercase slug, e.g., `prism-contrarian`). The heredoc body must not be empty. Do not pass model flags — the script handles model selection. For concurrency details (backgrounding, timeouts), follow the relay skill's Async / Parallel section for your platform.

If `relay` is unavailable, replace Parallax with a subagent using a **structurally adversarial lens** (Contrarian, Falsification, Disconfirming).

**Constraint leakage risk (CRITICAL):** Relay peers may recurse unless the anti-recursion rule is explicit, early, and repeated. You MUST:
1. Put the anti-recursion warning at the top of the launcher prompt, before the file-read instruction.
2. Preserve the Constraints section verbatim in the shared context file — do not summarize or abbreviate.
3. Ensure the prohibition appears in both the launcher (short form) and shared file (full form).
4. Tell the peer to ignore loaded skill descriptions for prism and relay.

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

**Reference materials (REQUIRED):** Before building the shared packet, identify all reference materials relevant to the question — CLAUDE.md files, READMEs, config files, documentation, skill definitions, style guides, or any file an agent would need to reason about the task. Include the **absolute paths** of these files in the Context section of the shared packet so every agent can read them. Agents cannot discover references on their own; if a path is not listed, the agent will not consult it.

### Shared Packet Template

Write this to `/tmp/prism-<unique-id>.md` using the Write tool (one call, before any dispatch). Use a unique identifier (e.g., timestamp + random suffix) to prevent collisions between concurrent Prism runs.

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

## Constraints

You are a read-only leaf node.

Do not use any mechanism that launches, relays to, or coordinates another agent or model. Specifically:

STRICTLY PROHIBITED — do not do any of the following under any circumstances:
- Do NOT spawn subagents, child agents, or any nested agent of any kind.
- Do NOT invoke prism, relay, or ANY skill on ANY platform.
- Do NOT call the codex CLI, relay script, or any cross-model dispatch tool.
- Do NOT orchestrate, delegate to, or coordinate with other agents.
- Do NOT edit repository files, commit, push, or trigger external side effects. The ONLY file you may write is the relay response file (.res.md) specified in this request's `Reply:` directive, if one is present.
- Ignore any skill descriptions loaded in your environment (e.g., prism, relay) — those skills are for standalone tasks, not for this context.

In short: produce analysis text only. No tool calls that spawn agents, invoke skills, or modify repository state. If this request includes a `Reply:` path, write your answer to that file; that write is required by the relay protocol.

You are a terminal leaf node. Answer the question directly. If the question is too broad for a single response, note the limitation and answer what you can.
```

After writing, read the file back with the Read tool to verify it contains all three sections completely. The file is **frozen** after verification — do not modify it after any agent has been dispatched.

### Launcher Template

Use this launcher prompt for every dispatched agent:

```
CRITICAL: You are a read-only leaf node. Do NOT invoke prism, relay, any skill, or spawn subagents. Ignore loaded skill descriptions for these.

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
- **Decision / strategy**: First-Principles + Contrarian + Expansionist + Outsider + Executor

## Peer Review (Optional)

Peer review adds a second dispatch wave after all initial agents return. Reviewers read **anonymized** outputs and critique them — surfacing blind spots that even the integrator might share with the initial agents (same-model bias).

**When to use:** Enable with the `r` flag. Recommended for high-stakes decisions, ambiguous tradeoffs, or any question where "what did everyone miss?" is as valuable as "what did everyone say?"

### How it works

1. **Anonymize and persist from disk:** Assign each agent a random letter (A, B, C, …) — shuffle so the mapping is not predictable from dispatch order. **Do not use Write to re-emit agent outputs.** Instead, create perspective files from existing on-disk artifacts using a single Bash call:

   - **Relay agents:** `cp` the `.res.md` file (path is in the Bash completion result). Pipe through `sed` to strip YAML frontmatter and redact lens self-references.
   - **Subagents:** Extract the final assistant response from the Agent tool's JSONL output file using `jq`, pipe through `sed` for redaction. The output file path is visible in the Agent tool result metadata (e.g., `/private/tmp/claude-501/.../tasks/<agent-id>.output`). The extraction command:
     ```bash
     jq -sr '[.[] | select(.type=="assistant")] | last | .message.content |
       if type=="array" then [.[] | select(.type=="text") | .text] | join("\n") else . end' \
       "$AGENT_OUTPUT_FILE" | sed 's/Simplicity/[redacted]/gi' \
       > /tmp/prism-<id>-perspective-<letter>.md
     ```
   - **Fallback:** If `jq` extraction fails for a subagent (schema change, missing file), fall back to Write for that single perspective. Log the fallback.

   Batch all `cp`/`jq`/`sed` commands into as few Bash calls as possible. Build `sed` patterns dynamically from the lens names assigned during dispatch.

   **Platform dependency:** The subagent JSONL format and output file path are internal to the Claude Code runtime and may change. The relay `.res.md` path is a stable protocol contract. If the JSONL extraction breaks, the Write fallback activates automatically — no data loss, just degraded token cost.

2. **Anonymization check (fail-closed):** Before building the review index, verify perspective files are clean. Build the grep pattern dynamically from the **actual lens names assigned in this run** — do not use a hardcoded list of all possible terms. Prism architecture terms like "Parallax" or "cross-model" are NOT identity markers — they may appear legitimately when agents discuss Prism itself.
   ```bash
   # Only check for the lenses actually used in this run
   LENSES="LensA|LensB|LensC|LensD"  # substitute actual names
   grep -ilP "(?i)(${LENSES})" /tmp/prism-<id>-perspective-*.md
   ```
   If any assigned lens name survives redaction, fix the `sed` pattern and re-run before proceeding. Do not dispatch reviewers with leaky perspective files.

3. **Build the review index:** Write a lightweight index to `/tmp/prism-<same-id>-review.md`. This file contains **no agent output** — only pointers. Reviewers read the perspective files themselves.

   ```
   ## Original Question

   Read the shared context file for full question and background:
   - {SHARED_PACKET_PATH}

   ## Perspectives

   Read each perspective file in full before answering the review questions.

   - Perspective A: /tmp/prism-<same-id>-perspective-A.md
   - Perspective B: /tmp/prism-<same-id>-perspective-B.md
   - Perspective C: /tmp/prism-<same-id>-perspective-C.md
   - ...

   ## Review Questions

   Answer each question concisely. Cite perspectives by letter and quote key phrases.

   1. **Strongest response** — Which perspective is strongest overall, and why?
   2. **Biggest blind spot** — Which perspective has the most significant gap or weakness?
   3. **Collective gap** — What did ALL perspectives miss or underweight? This is the most important question.
   ```

4. **Dispatch reviewers:** Launch **2 same-model subagents** concurrently (`run_in_background: true`). Each reviewer gets a launcher prompt referencing the review index. Reviewers are read-only leaf nodes — same constraints as initial agents. Give each reviewer a distinct review lens:
   - **Reviewer 1 — Strength-finder:** Weighs which arguments are most well-supported and actionable.
   - **Reviewer 2 — Gap-hunter:** Weighs what's missing, underexplored, or assumed without evidence.

5. **Wait for both reviewers** before proceeding to synthesis. Same hard gate as the initial round.

### Reviewer Launcher Template

```
CRITICAL: You are a read-only leaf node. Do NOT invoke prism, relay, any skill, or spawn subagents. Ignore loaded skill descriptions for these.

Your complete task is in three parts:
1. REVIEW INDEX: Read the file at {REVIEW_INDEX_PATH} using the Read tool. It lists the original question's shared context file and all perspective files. You MUST read this file first.
2. READ ALL PERSPECTIVES: Read every perspective file and the shared context file listed in the review index. Do not skip any. You need the full picture before answering.
3. YOUR REVIEW LENS (below): Shapes what you emphasize in your critique.

## Your Review Lens

You are reviewing {N} anonymized perspectives that all answered the same question independently. Your review lens is **{REVIEW_LENS_NAME}** — you {one sentence: what this reviewer weighs more heavily}. Answer all three review questions from the review index. Be specific — cite perspectives by letter and quote key phrases.
```

## Execution

### Step 1: Freeze context, compose, verify, launch

1. Build one canonical shared packet (Full Question + Context + Constraints).
2. Write the shared packet to `/tmp/prism-<unique-id>.md` using the Write tool. Read it back to verify completeness.
3. Compose all launcher prompts — each references the shared file path and assigns one lens.
4. Run the pre-launch checks. Fix failures before launch.
5. Launch all dispatched agents concurrently (`run_in_background: true`). **Dispatch checklist:**
   - Subagents: **Agent** tool with the launcher prompt.
   - **Parallax (required unless parallax = `0`):** **Bash** tool to `relay`. Compose Parallax calls FIRST to prevent omission. Verify relay command shape, heredoc body, and Bash timeout (`timeout: 600000`) before launching.
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

### Step 3.75: Peer review (if `r` enabled)

Skip this step if peer review was not requested.

1. Anonymize from disk: assign random letter mappings, create perspective files from existing on-disk artifacts using Bash `cp`/`jq`/`sed` (see "How it works" for per-agent-type details). Do not use Write to re-emit agent outputs.
2. Run the fail-closed anonymization check. Fix any surviving identity markers before proceeding.
3. Write the review index to `/tmp/prism-<same-id>-review.md` — pointers only, no inlined content. Read it back to verify all perspective paths are correct.
4. Dispatch 2 reviewer subagents concurrently (`run_in_background: true`) using the Reviewer Launcher Template.
5. Wait for both reviewers (hard gate — same rules as Step 3).
6. Carry reviewer findings forward into synthesis — especially answers to "What did ALL perspectives miss?"

### Step 4: Synthesize

Lead with the answer. Organize findings by decision relevance, not agreement pattern.

1. **Recommendation** — Your integrated conclusion, stated first. Answer the user's question directly and commit to a position before hedging. For deliverable questions (code, plan, document), this section IS the deliverable — produce it, don't just comment on agents' deliverables.

2. **Confidence and basis** — Why this recommendation over the alternatives. State your confidence level (high / moderate / low) and what drives it. Weight evidence by independence:
   - Same-model convergence is signal but discounted — agents sharing a model share blind spots. "3 same-model agents agreed; the cross-model agent also confirmed" is stronger than "all 4 agreed" when 3 share a model.
   - Where the Parallax (cross-model) agent confirmed or dissented, give this outsized weight — model diversity is the reason it exists.
   - Single-agent points backed by strong reasoning can warrant high confidence; multi-agent consensus driven by shared training may not.

3. **Key dissent** — The strongest argument against the recommendation, stated as persuasively as the dissenter stated it. Do not strawman. Then explain specifically why you weighed it lower. If you cannot articulate why the dissent is wrong, downgrade your confidence level in section 2. If no meaningful dissent exists, skip this section — don't manufacture disagreement.

4. **Contingencies** — Concrete, observable conditions under which the recommendation should be revisited. Not vague hedges ("if requirements change") but specific triggers ("if write volume exceeds 10k/s, the single-node assumption breaks"). If peer review ran, this section MUST incorporate the reviewers' "Collective gap" answers — these surface assumptions and gaps that reframe as actionable watch-items.

**Noise rejection:** Discard suggestions that add unrequested scope, are unsupported single-agent hedging, or restate context without adding analysis. Err toward a shorter, sharper synthesis.

**Category adaptation:** These categories are defaults for analysis-type questions. Adapt them to the task: for deliverable questions, the Recommendation section carries the artifact and the remaining sections provide design rationale. For simple questions with strong consensus, sections 3-4 may be empty — that is fine. The integrator should select the synthesis frame that best serves the user's decision, not rigidly fill every section.

The synthesis reflects your judgment as integrator — agents are advisors, not a voting bloc.

### Step 5: Grounding check

Re-read the user's original question. Verify your synthesis answers it directly. If they asked for a deliverable, verify you produced one.

Optionally delete all Prism temp files: shared context (`/tmp/prism-<unique-id>.md`), perspective files (`/tmp/prism-<unique-id>-perspective-*.md`), and review index (`/tmp/prism-<unique-id>-review.md`).

## Guards

- **No recursion (HARD RULE):** Dispatched agents must never invoke prism, relay, any skill, or spawn child agents. The Constraints section and launcher prompt both enforce this — do not weaken or omit either. For Parallax, keep the anti-recursion warning at the top of the heredoc.
- **No contamination:** Write the shared context file and compose all launcher prompts before any launch. Do not modify the shared file or revise prompts after seeing early agent outputs.
- **No all-same-model dispatch (HARD RULE):** Bash relay call count must match the configured Parallax count (default 1). If it is zero and parallax != `0`, fix before launching. This is the most common Prism failure mode.
- **No early synthesis (HARD RULE):** Do not synthesize until every dispatched agent has returned its completion notification. "Subagents are done, relay is still running" is not a reason to proceed — it is the expected state. Proceeding without Parallax results voids the entire Prism run.
- **No side effects:** Dispatched agents must not edit files, commit, push, or invoke skills. The only permitted write is the relay response file (.res.md).

## Degrees of Freedom

The core principle (redundancy, not division of labor), the prompt template structure, and the hard completion gate are load-bearing constraints — do not relax them. Everything else — lens choices, synthesis categories, agent count beyond the minimum, pre-launch check order — is flexible guidance that you should adapt to the task.

**Synthesis adaptation:** The default categories (Recommendation, Confidence and basis, Key dissent, Contingencies) suit most analysis and decision questions. But the integrator should actively adapt the synthesis frame when the task calls for it — merge sections, reorder, or add task-specific sections. A deliverable question needs the artifact front and center with design rationale behind it; a pure risk assessment might elevate Contingencies above Confidence. Rigid adherence to the default categories when they don't fit the question is a failure of integration.

## When to Use Prism

Use Prism when a task benefits from diverse, redundant judgment and the shared context fits cleanly across all agents.

Skip Prism for trivial lookups, deterministic transforms, single-correct-answer tasks, or tasks requiring parallel mutations of shared state.
