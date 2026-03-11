# Prism

**A skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex) that strengthens any output through parallel multi-agent deliberation.**

Prism sends the same complete question to multiple independent agents, each answering from a different analytical lens. Convergence across diverse lenses is high-confidence signal; divergence surfaces tradeoffs that need explicit resolution.

Invoke with `/prism` or ask your agent to "use prism" on any task.

Co-authored by Claude Code and Codex.

## Table of Contents

- [Why](#why)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Usage](#usage)
- [Lenses](#lenses)
- [Parallax (Cross-Model)](#parallax-cross-model)
- [Safety](#safety)
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
┌─────────────────────────────────────────────────┐
│  User question + shared context                 │
├─────────┬──────────┬──────────┬─────────────────┤
│  Self   │ Agent 1  │ Agent 2  │   Parallax      │
│ (you)   │ Lens: A  │ Lens: B  │   Lens: C       │
│         │          │          │   (cross-model  │
│         │          │          │    via /relay)  │
├─────────┴──────────┴──────────┴─────────────────┤
│  Synthesis: consensus, contested, unique, gaps  │
└─────────────────────────────────────────────────┘
```

1. **Freeze context** — build one shared evidence packet with all information needed
2. **Compose prompts** — same question + same context + different lens per agent
3. **Launch all concurrently** — subagents + Parallax in parallel, then self-review
4. **Wait for ALL** — hard completion gate, no partial synthesis
5. **Synthesize** — consensus, contested points, unique insights, blind spots, recommendation

**Default: 4 perspectives** — self + 2 subagents + 1 Parallax (cross-model via [Relay](https://github.com/chrisliu298/relay)).

---

## Installation

### Quick install (npx)

```bash
npx skills add chrisliu298/prism
```

This installs the skill for all supported agents (Claude Code, Codex) using the [skills CLI](https://github.com/vercel-labs/skills).

### Manual install (curl)

**Claude Code:**

```bash
mkdir -p ~/.claude/skills/prism
curl -sL https://raw.githubusercontent.com/chrisliu298/prism/main/SKILL.md \
  -o ~/.claude/skills/prism/SKILL.md
```

**Codex CLI:**

```bash
mkdir -p ~/.codex/skills/prism
curl -sL https://raw.githubusercontent.com/chrisliu298/prism/main/SKILL.md \
  -o ~/.codex/skills/prism/SKILL.md
```

### Recommended: install Relay for Parallax

Prism's Parallax tier dispatches a cross-model agent via [Relay](https://github.com/chrisliu298/relay). Without Relay, Parallax falls back to a same-model adversarial agent — functional but with reduced model diversity.

```bash
npx skills add chrisliu298/relay
```

---

## Usage

Tell your agent to deliberate:

> "Use prism to review my auth middleware changes"

> "I need a prism analysis on whether to use SQL or NoSQL for this"

Or invoke directly with `/prism`.

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

The skill includes pre-launch checks that prevent common mistakes:

1. **Redundancy test** — ensures agents aren't dividing labor
2. **Lens quality test** — ensures lenses are distinct weighing postures with at least one adversarial
3. **Count test** — ensures the right number of agents are dispatched

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

## Safety

- **Read-only agents** — dispatched agents do not edit files, commit, deploy, or trigger side effects during a Prism run
- **Hard completion gate** — synthesis only begins after ALL agents return; no partial results
- **No recursion** — Prism cannot be invoked from within a Prism agent
- **No contamination** — all prompts are composed before any launch; no revising later prompts after seeing early outputs

---

## Contributors

- [@chrisliu298](https://github.com/chrisliu298)
- **Claude Code** — protocol design and synthesis framework
- **Codex** — lens calibration and cross-model validation
