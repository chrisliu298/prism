# Prism

**A skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://github.com/openai/codex) that strengthens any output through parallel multi-agent deliberation.**

> *White light looks simple until it hits a prism — then you see every color was there all along. One question, many angles, nothing hidden.*

Prism sends the same complete question to multiple independent agents, each answering from a different analytical lens. Convergence across diverse lenses is high-confidence signal; divergence surfaces tradeoffs that need explicit resolution.

Invoke with `/prism` or ask your agent to "use prism" on any task.

Prism was built by the process it teaches. Every revision — naming, protocol design, lens calibration, this README — was reviewed and improved by running `/prism` on itself: multiple agents deliberating from different lenses, then synthesizing into a stronger version. The skill sharpens itself.

## Table of Contents

- [Why](#why)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Usage](#usage)
- [Lenses](#lenses)
- [Peer Review](#peer-review)
- [Parallax (Cross-Model)](#parallax-cross-model)
- [Contributors](#contributors)

---

## Why

A single agent gives you one model's perspective. Prism gives you multiple:

- **Catch blind spots** — independent agents examining the same problem from different angles find issues that any single perspective misses
- **Surface tradeoffs** — disagreement between agents reveals decisions that need explicit resolution rather than implicit assumption
- **Build confidence** — convergence across diverse lenses is stronger signal than a single agent's certainty

### Why not just ask twice?

Asking the same question twice gets you the same biases twice. Prism assigns each agent a different **lens** — a weighing posture that changes what they emphasize, not what they skip. Every agent still answers the full question end-to-end.

---

## How It Works

```
┌──────────────────────────────────────────────────────┐
│  User question + shared context                      │
├───────────┬──────────┬──────────┬────────────────────┤
│   Self    │ Agent 1  │ Agent 2  │    Parallax        │
│ Integra-  │ Lens: A  │ Lens: B  │    Lens: C         │
│   tor     │          │          │   (cross-model     │
│           │          │          │    via /relay)     │
├───────────┴──────────┴──────────┴────────────────────┤
│  Synthesis: recommendation, confidence, dissent, gaps │
└──────────────────────────────────────────────────────┘
```

Self is the primary agent (the one you're talking to). It uses the **Integrator Lens** — weighing holistic coherence, feasibility, and alignment with your goals — and forms its own position while dispatched agents run in parallel.

1. **Freeze context** — build one shared evidence packet with all information needed
2. **Compose prompts** — word-for-word identical question and context across all agents, only the lens line differs
3. **Verify** — run pre-launch checks (redundancy, lens quality, count)
4. **Launch all concurrently** — subagents + Parallax in parallel, then self-review
5. **Wait for ALL** — no partial synthesis
6. **Peer review** *(optional, `r` flag)* — anonymize outputs, dispatch reviewer agents to critique
7. **Synthesize** — recommendation first, then confidence basis, key dissent, contingencies

**Default: 4 perspectives** — self + 2 subagents + 1 Parallax via [Relay](https://github.com/chrisliu298/relay). Override counts with positional args (e.g., `prism 3 2 h` for 3 subagents, 2 Parallax, high effort).

### Core rules

These are load-bearing constraints — everything else (lens choices, agent count above the minimum, synthesis format) is flexible guidance:

- **Redundancy, not division of labor** — every agent answers the full question end-to-end. If agents get different files, tasks, or deliverables, that is not Prism.
- **Identical prompts** — the Full Question and Context sections must be word-for-word identical across all dispatched agents. Only the lens line differs.

---

## Installation

Clone into your agent's skills directory:

**Claude Code:**

```bash
git clone https://github.com/chrisliu298/prism.git ~/.claude/skills/prism
```

**Codex:**

```bash
git clone https://github.com/chrisliu298/prism.git ~/.codex/skills/prism
```

### Recommended: install Relay for Parallax

Prism's Parallax tier dispatches a cross-model agent via [Relay](https://github.com/chrisliu298/relay). Without Relay, Parallax falls back to a same-model adversarial agent — functional but with reduced model diversity.

```bash
git clone https://github.com/chrisliu298/relay.git ~/.claude/skills/relay
```

---

## Usage

Tell your agent to deliberate:

> "Use prism to review my auth middleware changes"

> "I need a prism analysis on whether to use SQL or NoSQL for this"

Or invoke directly with `prism` — also available to subagents.

### Example output

After all agents return, Prism synthesizes their findings:

```
## Recommendation
Refactor to gateway-level validation with opaque tokens. Fix the timing
side-channel on line 45. Add integration tests for the token refresh flow.

## Confidence and basis
High confidence. All 4 agents agree on gateway-level validation. The cross-model
agent (Codex via Parallax) independently confirmed opaque tokens — stronger
signal than same-model convergence alone.

## Key dissent
Agents 1 and 3 recommended JWT for simpler client integration. Weighed lower
because the security audit timeline doesn't allow the additional attack surface
of self-contained tokens.

## Contingencies
Revisit JWT if the audit deadline extends past Q3. The timing side-channel
in token comparison (line 45) was caught only by Parallax — verify no similar
patterns exist in adjacent auth code.
```

### What makes a good Prism task?

- Non-trivial decisions with real tradeoffs
- Ambiguous problems where reasonable people disagree
- High-stakes changes where a missed issue is costly
- Architecture and design choices
- Code reviews of complex changes

### What to skip Prism for

- Trivial lookups or deterministic transforms
- Single-correct-answer tasks (what's the syntax for X?)
- Tasks requiring parallel mutations of shared state
- Tasks where the relevant context can't fit into one shared evidence packet for every agent

---

## Lenses

A lens is a **weighing posture**, not a task variant. Every agent answers the full question — the lens changes what they emphasize.

### Suggested lenses by task type

| Task type | Lenses |
|-----------|--------|
| Code review | Correctness + Simplicity + Adversarial |
| Architecture / design | Evolutionary + Simplicity + Contrarian |
| Implementation | Correctness + Pragmatist + Contrarian |
| Diagnosis / root cause | Causal + Falsification + Risk |
| Option comparison | Simplicity + Feasibility + Contrarian |
| Writing / communication | Clarity + Audience + Contrarian |
| Research / exploration | Breadth-Weighted + Depth-Weighted + Disconfirming |
| Decision / strategy | First-Principles + Contrarian + Expansionist + Outsider + Executor |

The skill includes pre-launch checks that prevent common mistakes:

1. **Redundancy test** — ensures agents aren't dividing labor
2. **Lens quality test** — ensures lenses are distinct weighing postures with at least one adversarial
3. **Count test** — ensures the right number of agents are dispatched

---

## Peer Review

Enable with the `r` flag to add an anonymous review round after initial agents return:

```
prism r Should we migrate to a microservices architecture?
```

Two reviewer agents read anonymized outputs and answer three questions: which perspective is strongest, which has the biggest blind spot, and what did all perspectives miss. The "collective gap" question consistently surfaces the highest-value insights.

Perspective files are created from existing on-disk artifacts via shell copy — no expensive re-emission through the model.

---

## Parallax (Cross-Model)

Parallax is the cross-model tier of Prism. It dispatches one agent via [Relay](https://github.com/chrisliu298/relay) to a **different model** — different training, different reasoning patterns, different blind spots.

### How it works

When running from Claude Code, Parallax calls Codex via Relay. When running from Codex, Parallax calls Claude Code. The Parallax agent receives the same full question and context as every other agent — only the lens differs.

### Why model diversity matters

Same-model agents share systematic biases from training. A cross-model perspective catches issues that no amount of same-model redundancy will surface. Assign Parallax a lens that maximizes diversity (e.g., if subagents have Correctness and Simplicity, give Parallax Contrarian or Disconfirming).

### Without Relay

If Relay is not installed, Prism replaces Parallax with a same-model agent using a **structurally adversarial lens** (Contrarian, Falsification, Disconfirming). This partially compensates for missing model diversity. The user can also opt out of Parallax explicitly.

---

## Contributors

- [@chrisliu298](https://github.com/chrisliu298)
- **Claude Code** — protocol design and synthesis framework
- **Codex** — lens calibration and cross-model validation
