# openclaw-build

![openclaw-build](https://raw.githubusercontent.com/bkochavy/openclaw-build/main/.github/social-preview.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-compatible-orange)](https://openclaw.ai)

AI coding agents stall three tasks in, silently drift off-spec, or die mid-session with no trace of what happened. You restart, re-explain everything from scratch, and hope this time sticks.

**openclaw-build** is the fix. You describe what you want. Your agent interviews you, writes a spec, gets your sign-off, then hands off to a build loop that runs until every task is checked off — with retry, memory, and notifications built in.

```
💡 Idea → 🎤 Interview → 📋 PRD.md → 🔄 Build Loop → ✅ Shipped
```

## Disambiguation: openclaw-build vs openclaw-prd-writer

| Repo | Scope | Use it when |
|------|-------|-------------|
| **`openclaw-build`** | **Full pipeline**: spec interview + PRD + build loop | You want end-to-end execution from idea to shipped tasks |
| [`openclaw-prd-writer`](https://github.com/bkochavy/openclaw-prd-writer) | **Standalone spec phase** only | You only want the interview/PRD workflow without automated build runs |

If you already have `openclaw-build`, you do not need `openclaw-prd-writer` separately.

---

## 👤 For Humans

### Why this exists

Most agent runs fail the same way: context drifts, sessions die, and task state gets lost between retries. openclaw-build keeps the workflow grounded in a checked PRD, short restartable runs, and explicit approval gates so your agent can recover and continue instead of starting over.

There are two phases, and you control both:

**Phase 1 — Spec.** Tell your agent "spec this" or "build me X." It interviews you — restates your idea, asks clarifying questions as polls, proposes an architecture plan. Two approval gates: one before it writes the spec, one before it starts building. Nothing happens without your say-so.

**Phase 2 — Build.** Instead of one long session that accumulates garbage context and degrades, the build runs as many short iterations. Each one reads the project's git log and memory files to pick up exactly where the last left off. The PRD checklist is the source of truth — when every box is checked, the build is done. A monitor daemon watches sessions and pings you when something finishes or stalls, using zero API tokens.

### What you get

- **Two approval gates** — nothing gets specced or built without your explicit sign-off
- **Engine choice** — Codex for backend, Claude Code for UI, Sonnet for cost-sensitive work
- **Parallel execution** across git worktrees for independent tasks
- **Cross-model review** — Codex builds, Claude audits (and vice versa)
- **Per-project memory** so each iteration picks up where the last left off
- **PRD preflight** catches malformed tasks before wasting tokens
- **Iteration caps** for safe unattended/AFK runs
- **GitHub integration** — work through labeled issues directly
- **Monitor daemon** for completion and stall detection (zero tokens)
- Works with OpenClaw channels: WhatsApp, Telegram, Discord, iMessage, Signal, Slack (plus CLI workflows)

### Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/bkochavy/openclaw-build/main/install.sh | bash
```

OpenClaw must already be installed and onboarded first:

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

#### Requirements

| Tool | Why | Install |
|------|-----|---------|
| `openclaw` | runtime + system events | `curl -fsSL https://openclaw.ai/install.sh \| bash` |
| `ralphy` (`ralphy-cli`) | PRD-driven build loop runner | `npm i -g ralphy-cli` |
| `codex` or `claude` | coding engine backend for runs | install either CLI and authenticate |
| `tmux` | detached long-running sessions | `brew install tmux` or `apt install tmux` |
| `node` 18+ | required runtime for toolchain and scripts | [nodejs.org](https://nodejs.org) |
| `bash` | installer + monitor scripts | pre-installed on most systems |

### Quick start

```bash
# 1. Tell your agent what to build
"spec a rate limiting API endpoint"

# 2. Answer the interview, approve the plan, approve the PRD

# 3. Agent hands off automatically — or launch manually:
ralphy --codex --prd projects/rate-limiter/PRD.md
```

### Which engine

| Work type | Flag | Why |
|-----------|------|-----|
| Backend, APIs, logic | `--codex` | Stronger at correctness |
| UI, styling, design | `--claude` | Better visual judgment |
| Cost-sensitive | `--sonnet` | Cheaper, still capable |

---

## 🤖 For Agents

Everything below is written for autonomous consumption. Read `prd/SKILL.md` and `loops/SKILL.md` for complete runbooks.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/bkochavy/openclaw-build/main/install.sh | bash
```

### PRD phase

**Triggers:** "spec this", "write a PRD", "build me X", "plan this feature", "/spec"

**Pipeline:** Understand (restate + ask 3–7 clarifying questions) → Plan (architecture, present for approval — Gate 1) → Spec (write `projects/[name]/PRD.md`, present for approval — Gate 2) → Handoff (`ralphy --init`, launch tmux session with completion hook).

**Task format:** One `- [ ]` per task, no nesting, 3–5 min each. Include `## Verification Commands` with typecheck/test/lint. Always write to disk, never just paste in chat.

### Build phase

**Launch (tmux + completion hook):**
```bash
tmux -S ~/.tmux/sock new -d -s SESSION \
  "cd /path/to/repo && [ -f PRD.md ] || { echo '[ERROR] PRD.md not found'; exit 1; } && \
   ralphy --codex --verbose --prd PRD.md -- -c model_reasoning_effort=\"high\"; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'Session SESSION finished (exit '\$EXIT_CODE').' --mode now; \
   sleep 999999"
```

**Always:** `--verbose` on every run. Codex reads high effort from `~/.codex/config.toml`. Claude requires `-- --effort high` on every invocation — no persistent config, so omitting silently downgrades.

**PRD preflight (before every launch):**
```bash
rg -n '^- \[ \] ' PRD.md >/dev/null || { echo '[ERROR] no valid top-level tasks'; exit 1; }
rg -n '^- \[\]' PRD.md >/dev/null && { echo '[ERROR] malformed checkbox'; exit 1; }
rg -n '^[[:space:]]+- \[ \] ' PRD.md >/dev/null && { echo '[ERROR] nested checkboxes'; exit 1; }
```

**Project memory (first time per project):**
```bash
cd /path/to/repo && ralphy --init
ralphy --add-rule "Read .ralphy/progress.txt FIRST for context from previous iterations"
ralphy --add-rule "After completing your task, APPEND learnings to .ralphy/progress.txt"
ralphy --add-rule "Run ALL verification commands before marking a task complete"
ralphy --add-rule "Make a git commit with a descriptive message after each completed task"
```

**Parallel:** `ralphy --codex --parallel --max-parallel 3 --verbose --prd PRD.md -- -c model_reasoning_effort="high"`

**AFK runs:** Always set `--max-iterations` to 1.5–2x task count. Without it, a confused agent loops indefinitely.

**Cross-model review:**
```bash
ralphy --claude --verbose -- --effort high "Review last 10 commits. Write REVIEW.md."
ralphy --codex --verbose -- -c model_reasoning_effort="high" "Review last 10 commits. Write REVIEW.md. Fix critical issues."
```

**Three-phase pipeline** (full-stack apps): Split into `FRONTEND-PRD.md` (Claude for UI), `BACKEND-PRD.md` (Codex for APIs), `INTEGRATION-PRD.md` (Codex to wire together). Run sequentially.

**GitHub:** `ralphy --codex --github owner/repo --github-label ralph --verbose`

**Session management:**
```bash
tmux -S ~/.tmux/sock list-sessions                          # List sessions
tmux -S ~/.tmux/sock capture-pane -t SESSION -p | tail -20  # Check progress
tmux -S ~/.tmux/sock kill-session -t SESSION                # Kill session
```

### Flag reference

| Flag | Effect |
|------|--------|
| `--verbose` | Detailed output — always use |
| `--codex` / `--claude` / `--sonnet` | Engine selection |
| `--prd FILE` | Tasks from checklist (must be before `--`) |
| `--parallel` | Concurrent tasks via worktrees |
| `--max-parallel N` | Concurrency limit (default 3) |
| `--sandbox` | Sandboxes instead of worktrees |
| `--max-iterations N` | Hard cap for AFK safety |
| `--max-retries N` | Retries per task (default 3) |
| `--dry-run` | Preview without executing |
| `--fast` | Skip tests/lint (not for production) |
| `--create-pr` | Open PR when done |
| `--github owner/repo` | Work through GitHub issues |
| `--sync-issue N` | Push PRD to GitHub issue |
| `--init` | Initialize project config |
| `--add-rule "..."` | Add rule to `.ralphy/config.yaml` |

After `--`: Codex takes `-c model_reasoning_effort="high"`, Claude takes `--effort high`.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Agent exits immediately | Check `~/.codex/log/codex-tui.log` — usually expired auth |
| Wrong task count | Count `- [ ]` manually — nested checkboxes inflate the number |
| Port in use | Add `lsof -ti:PORT \| xargs kill -9` as first PRD task |
| `--prd` ignored | Placed after `--` — ralphy flags go before the separator |
| Merge conflicts | Use YAML `parallel_group` for conflicting tasks |

---

## Templates

- `loops/templates/PRD.md.template` — task checklist compatible with ralphy
- `loops/templates/AGENTS.md.template` — conventions for Codex
- `loops/templates/CLAUDE.md.template` — conventions for Claude Code
