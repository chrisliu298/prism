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
| Parallax | **Bash** tool (`/relay`) | Cross-model agent via relay script — NOT an Agent call |

**Default: 4 perspectives** — self + 2 subagents + 1 Parallax. The required dispatch is **2 Agent calls + 1 Bash relay call** (3 total, or 1 Agent + 1 Bash relay in compact mode). Self does not count toward the dispatched total. Parallax (the Bash relay call) is always included unless the user explicitly opts out or `/relay` is unavailable.

### Parallax (cross-model agent)

Parallax is the agent dispatched via `/relay` to a **different model** than yourself. Dispatch Parallax by invoking `/relay` directly (not by spawning a subagent that calls relay) — the relay call body is the agent prompt from the template. Its value is model diversity — different training, different blind spots, different reasoning patterns. Assign it a lens like any other agent, preferably one that maximizes diversity (e.g., if subagents have Correctness and Simplicity lenses, give Parallax a Contrarian or Disconfirming Lens).

**Before composing the Parallax prompt body, read the peer's prompt guide** in the relay skill's `references/` directory (e.g., `prompting-codex.md` when relaying to Codex). The guide contains model-specific patterns that materially affect output quality. This applies every time you write a relay call body, not just the first time.

If `/relay` is unavailable, replace Parallax with a subagent using a **structurally adversarial lens** (Contrarian, Falsification, Disconfirming). A same-model agent with an adversarial posture partially compensates for missing model diversity. The user can also opt out of Parallax explicitly.

**Effort selection for Parallax:** Choose `--effort` based on the assigned lens:

| Lens type | `--effort` | Rationale |
|-----------|-----------|-----------|
| Adversarial, Contrarian, Falsification | `high` or `xhigh` | Needs deep reasoning to find subtle flaws |
| Correctness, Risk, Causal | `high` | Benefits from thorough analysis |
| Simplicity, Pragmatist, Feasibility, Breadth | `medium` | Pattern-matching; deeper reasoning adds latency without proportional quality gain |

### Subagents

Same-model agents dispatched via the Agent tool. Those agents can still invoke skills; "same-model" describes how they are spawned, not a limit on tool access. Each gets a distinct lens. Launch all dispatched agents — Agent calls for subagents, Bash relay call for Parallax — concurrently before starting your self-review.

## Side-Effect Safety

Dispatched agents should stay **read-only** — do not edit shared files, commit, deploy, or trigger external side effects during a Prism run. Parallel writes to shared state create merge conflicts and irreversible mistakes that are harder to fix than to prevent. The primary agent may implement changes after synthesis if the user asked for a deliverable.

## Context Budget

Build one shared evidence packet before composing prompts. Include the specific excerpts, constraints, and facts needed to answer — prefer compact digests over full file dumps to keep agents focused and avoid redundant I/O. Every agent receives this exact packet. If the packet cannot be duplicated cleanly across all agents, the task is too large for Prism.

## Agent Prompt Template

Every dispatched agent — subagents and Parallax — uses this structure:

```
## Full Question

{User's COMPLETE question/task, unchanged. Identical across all agents.}

## Context

{Shared evidence packet. Identical across all agents.}

## Your Lens

You are one of several independent agents answering the same question in full. Your lens is **{LENS_NAME}** — you {one sentence: what this agent weighs more heavily}. Answer the full question end-to-end. Your lens shapes what you emphasize, not what you skip. Do not assume another agent will cover anything you omit. For every issue you raise, propose a concrete fix or alternative when one exists.

## Constraints

You are a read-only analyst. Do not edit files, write files, commit, push, or invoke any skills (/push, /relay, /atomic-push, /publish-skill, or any other slash command). Do not spawn further subagents. Your output is analysis text only.
```

The Full Question and Context sections must be **word-for-word identical** across all prompts. The only allowed difference is the lens name and its one-sentence explanation. Agent names (e.g., "Prism agent 1 (lens: simplicity)") are metadata outside the prompt body — they do not count as a prompt difference.

## Pre-Launch Checks

Run these three checks before launching. If any fails, rewrite and re-check.

1. **Redundancy test:** Swap the lenses between any two agents — if the prompts become incoherent or change scope, you've divided labor. Could each agent produce a complete, standalone answer if all others vanished?

2. **Lens quality test:** Each lens name must be a weighing posture (1-3 words), never a task or role. For each lens, write one sentence explaining what unique axis it covers that no other lens does. If two lenses would produce the same emphasis, replace one. At least one lens must be structurally adversarial.

3. **Dispatch-shape test:** Dispatched agents (subagents + Parallax) equals the required count (default 3, or 2 in compact mode). Self does not count. Verify the tool types: exactly 1 Bash relay call (Parallax) and the rest Agent calls (subagents). If all dispatches are Agent calls, Parallax is missing — stop and fix.

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

1. Write one canonical Context block with all evidence needed.
2. Compose all agent prompts using the template.
3. Run the three pre-launch checks. Fix failures before launch.
4. Launch all dispatched agents concurrently in the background. **Dispatch checklist — verify before launching:**
   - Subagents: dispatched via the **Agent** tool.
   - Parallax: dispatched via a **Bash** tool call to `/relay` (`run_in_background: true`). This is NOT an Agent call. If your launch set contains only Agent calls and no Bash relay call, you have forgotten Parallax — stop and fix.
   - Before launching Parallax, verify the relay command shape, heredoc body, and Bash timeout (`timeout: 600000`) to avoid wasting a perspective on an avoidable transport error.

Do not poll or sleep-loop — the system notifies you when agents finish.

### Step 2: Self-review

While agents run, form your own position independently. Your lens is **Integrator Lens** — you weigh holistic coherence, feasibility, and alignment with the user's goals. Write your tentative recommendation before opening any agent output.

Since you composed the prompts and chose the lenses, your self-review is not fully independent. When dispatched agents diverge from your position, give their perspectives slightly more weight on points you may have anchored on during prompt design.

### Step 3: Wait for ALL agents

**Do not synthesize until every dispatched agent has returned.**

**Handling failures — diagnose before escalating:**

- **Relay (Parallax) transport failure:** If the Bash relay call fails (missing response file), the peer failed before producing output. Read the `.log` sidecar printed in the error output, diagnose the cause, fix the invocation, and retry once. Common fixes: increase Bash timeout (`timeout: 600000` in Claude Code), fix heredoc formatting, correct the relay command. Do not escalate to the user until you have attempted a diagnosed retry.
- **Subagent or answer-quality failure:** If an agent returns an unusable answer (empty, truncated, off-topic) after the call itself succeeded, report the issue and offer the user three options: (a) retry the failed agent, (b) proceed with reduced perspectives, or (c) abort. A missing perspective changes synthesis quality.

### Step 3.5: Safety check

Before synthesizing, verify no dispatched agent modified the working tree:

```bash
git diff --stat HEAD
```

If the diff shows unexpected changes, flag them to the user before proceeding. Discard the offending agent's output — an agent that violated read-only constraints may have reasoned from a corrupted state.

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

## Guards

- **No recursion:** Do not invoke Prism from within a Prism agent.
- **No contamination:** Compose all prompts before any launch. Do not revise later prompts after seeing early agent outputs.
- **No all-same-model dispatch:** If every dispatched call is an Agent tool call, you have dropped Parallax. Stop and add the Bash relay call before launching. Three Agent calls is never a valid default Prism dispatch.
- **No subagent nesting:** Dispatched agents must not spawn further subagents or invoke skills that spawn agents (/prism, /relay, /lbreview). Prism agents are leaf nodes.
- **No side effects:** Dispatched agents must not edit files, write files, commit, push, or invoke any user-invocable skill. This is enforced in the agent prompt template and verified before synthesis.

## Degrees of Freedom

The core principle (redundancy, not division of labor), the prompt template structure, and the hard completion gate are load-bearing constraints — do not relax them. Everything else — lens choices, synthesis categories, agent count beyond the minimum, pre-launch check order — is flexible guidance that you should adapt to the task.

## When to Use Prism

Use Prism when a task benefits from diverse, redundant judgment and the shared context fits cleanly across all agents.

Skip Prism for trivial lookups, deterministic transforms, single-correct-answer tasks, or tasks requiring parallel mutations of shared state.
