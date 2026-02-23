# openclaw-build

> From rough idea to shipped code, through a structured agent pipeline.

You describe what you want to build. Your agent asks clarifying questions, proposes
a plan, writes a spec, gets your approval — then hands off to a coding agent that
runs until it's done.

Two tools, one pipeline:

```
idea → prd-writer → PRD.md → ralph (coding-loops) → shipped code
```

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-compatible-orange)](https://openclaw.ai)

---

## The two parts

### 1. `prd/` — PRD Writer (spec phase)

An OpenClaw skill that turns a rough idea into a build-ready spec through conversation.

Five phases, two approval gates:
```
Understand → Plan → [Approve] → Spec → [Approve] → Handoff
```

The agent asks 3–7 clarifying questions, proposes a lightweight architecture plan,
gets your approval, writes a detailed PRD to `projects/[name]/PRD.md`, gets your
approval again, then hands off to the Ralph loop.

**Say any of these to start:**
> "spec this", "write a PRD", "build me X", "/spec"

### 2. `loops/` — Ralph Coding Loops (build phase)

Persistent Codex/Claude Code sessions with retry, memory between iterations,
and completion notification.

Instead of one long session that stalls or dies, many short fresh-context iterations
that pick up from git history and `.ralphy/progress.txt`. The agent that built 108
tasks across 3 projects in 4 hours.

**Decision table:**

| Size | Approach | Engine |
|------|----------|--------|
| Bug fix / tweak | Inline: `ralphy --codex "Fix the bug"` | Codex |
| Small feature | Inline with detail | Codex |
| Medium feature (4–10 tasks) | PRD from prd-writer | Codex or Claude |
| UI/UX, styling | PRD | Claude Code |
| Full-stack app | PRD + parallel | Both |

---

## 👤 For Humans

**The problem:** AI coding agents stall, drift, or silently die mid-task. And before
you even get to coding, you spend 30 minutes re-explaining context to a blank
session every time.

**What this does:**
- PRD Writer: structured conversation → approved spec → file on disk. No more
  re-explaining the same idea five different ways.
- Ralph loops: short sessions, fresh context each time, memory via files. Agent
  picks up exactly where it left off. You get notified when done.

**Install:**
```bash
# Install skills
git clone https://github.com/bkochavy/openclaw-build.git \
  ~/.openclaw/workspace/skills/openclaw-build

# Install the Ralph monitor daemon
bash ~/.openclaw/workspace/skills/openclaw-build/loops/install.sh
```

**Quick start:**
```bash
# Tell your agent to spec something
"spec a rate limiting API endpoint"

# After PRD is approved, launch Ralph
ralphy --codex --prd projects/rate-limiter/PRD.md
```

---

## 🤖 For Agents

### Starting a PRD session
Read `prd/SKILL.md`. Trigger on: "spec this", "write a PRD", "build me X", "/spec".
Five phases. Do NOT skip Phase 1 (understand). Do NOT generate PRD without Gate 1
approval of the Master Plan. Write PRD to `projects/[name]/PRD.md`.

### Launching a Ralph loop
Read `loops/SKILL.md`. Use the tmux launch template. Always include the completion
wake hook. Wire ralph-monitor via `loops/install.sh` for automatic stall detection
and completion notification.

### Full pipeline handoff
After PRD Gate 2 approval:
1. `ralphy --init` in the project directory
2. Inject standard rules from `loops/SKILL.md`
3. Launch tmux session with PRD and wake hook
4. Monitor via ralph-monitor (auto-notifies on done/stall)

---

## Requirements

| Tool | Required for | Install |
|------|-------------|---------|
| OpenClaw | everything | [openclaw.ai](https://openclaw.ai) |
| `ralphy-cli` | build phase | `npm install -g ralphy-cli` |
| `codex` or `claude` | build phase | respective CLIs |
| `tmux` | build phase | `brew install tmux` / `apt install tmux` |
| `jq` | ralph-monitor | `apt install jq` |

---

## Templates

- `loops/templates/PRD.md.template` — task checklist format compatible with Ralph
- `loops/templates/AGENTS.md.template` — conventions file Codex reads automatically
- `loops/templates/CLAUDE.md.template` — same for Claude Code
