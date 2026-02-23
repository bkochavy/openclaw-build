# openclaw-build
![openclaw-build](https://raw.githubusercontent.com/bkochavy/openclaw-build/main/.github/social-preview.png)


> From rough idea to shipped code, through a structured agent pipeline.

You describe what you want to build. Your agent interviews you, proposes an architecture plan, writes a spec file, gets your sign-off, then hands off to a coding agent that runs until every task is done — with retry, memory, and notifications built in.

```
💡 Idea → 🎤 Interview → 📋 PRD.md → 🔄 Ralph Loop (Codex ↔ Claude Code) → ✅ Shipped
```

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-compatible-orange)](https://openclaw.ai)

---

## 👤 For Humans

### The problem

AI coding agents stall, drift, or silently die mid-task. And before you even start coding, you spend 20 minutes re-explaining your idea to a blank context window every time. The output is inconsistent because the spec only exists in chat history that disappears.

### What this fixes

**Phase 1 — PRD Writer** (`prd/SKILL.md`)

Say any of these to your agent:
> "spec this", "write a PRD", "build me X", "plan this feature", "/spec"

Your agent runs a structured interview: restates the idea, asks 3–7 clarifying questions (as polls or buttons), proposes a lightweight architecture plan, and waits for your approval before writing anything. After you approve the plan, it writes a detailed spec to `projects/[name]/PRD.md` and waits for a second approval before handing off to build.

Two gates. Nothing gets specced or built without your explicit sign-off.

**Phase 2 — Ralph Coding Loops** (`loops/SKILL.md`)

Instead of one long agent session that accumulates noise and degrades, many short fresh ones. Each iteration reads the project's git log and memory files to pick up exactly where the last one left off. The PRD checklist is the source of truth — when every box is checked, the build is done.

A monitor daemon (`ralph-monitor.sh`) watches sessions every 10 minutes with zero API tokens. It notifies you when a session completes or stalls.

### Features

**PRD Writer:**
- 5-phase pipeline: Understand → Plan → Approve → Spec → Approve → Handoff
- Two approval gates — nothing proceeds without confirmation
- Polls and inline buttons for mobile-friendly clarification
- Writes spec to disk as a file you own and can edit
- Hands off directly to coding loops when approved
- Works on any channel (Telegram, Discord, iMessage, etc.)

**Coding Loops:**
- Codex and Claude Code as interchangeable engines — pick based on task type
- Inline tasks (no PRD) or PRD-driven checklists
- Parallel execution across git worktrees
- Per-project memory via `.ralphy/progress.txt` and `AGENTS.md`/`CLAUDE.md`
- PRD preflight validation catches malformed checkboxes before wasting tokens
- Iteration cap (`--max-iterations`) as a safety ceiling for unattended runs
- Sandbox mode for large repos with heavy dependency trees
- Three-phase build pipeline for full-stack apps (Claude Code for UI, Codex for backend + integration)
- Cross-model review: after Codex builds something, Claude audits it and vice versa
- GitHub issues integration — work through labeled issues directly
- `ralph-monitor.sh` daemon for completion + stall detection (zero tokens)
- Completion hook fires an OpenClaw system event the moment a session finishes

### Install

```bash
# Clone into your OpenClaw workspace skills folder
git clone https://github.com/bkochavy/openclaw-build.git \
  ~/.openclaw/workspace/skills/openclaw-build

# Install the Ralph monitor daemon (macOS launchd or Linux systemd)
bash ~/.openclaw/workspace/skills/openclaw-build/loops/install.sh
```

### Quick start

```bash
# 1. Ask your agent to spec something
"spec a rate limiting API endpoint"

# 2. Answer the interview questions, approve the plan, approve the PRD

# 3. Agent hands off — or launch manually:
ralphy --codex --prd projects/rate-limiter/PRD.md
```

### Which engine to use

| Work type | Engine | Why |
|-----------|--------|-----|
| Backend, APIs, data, logic | `--codex` | Stronger at correctness and structure |
| UI, components, styling, design | `--claude` | Better visual judgment |
| Anything else | `--codex` | Faster default |
| Low-priority or cost-sensitive | `--sonnet` | Cheaper, still capable |

### Parallel and multi-phase builds

For PRDs with independent tasks:
```bash
ralphy --codex --parallel --prd PRD.md -- -c model_reasoning_effort="high"
```

For full-stack apps, split into three sequential PRDs:
- Phase 1: `FRONTEND-PRD.md` — Claude Code for UI
- Phase 2: `BACKEND-PRD.md` — Codex for APIs and data
- Phase 3: `INTEGRATION-PRD.md` — Codex to wire it together

### Cross-model review

After any significant build, have the opposite engine review:
```bash
# Claude reviews Codex output
ralphy --claude --verbose -- --effort high "Review last 10 commits for UX issues, edge cases, simplification opportunities. Write REVIEW.md."

# Codex reviews Claude output  
ralphy --codex --verbose -- -c model_reasoning_effort="high" "Review last 10 commits for bugs, missing error handling, security issues. Write REVIEW.md. Fix critical issues."
```

### Requirements

| Tool | Required for | Install |
|------|-------------|---------|
| OpenClaw | everything | [openclaw.ai](https://openclaw.ai) |
| `ralphy-cli` | build phase | `npm install -g ralphy-cli` |
| `codex` or `claude` | build phase | respective CLIs |
| `tmux` | build phase | `brew install tmux` / `apt install tmux` |
| `jq` | ralph-monitor | `apt install jq` |

---

## 🤖 For Agents

### PRD phase — full runbook

**Triggers:** "spec this", "write a PRD", "build me X", "plan this feature", "/spec"

**Read:** `prd/SKILL.md` — contains the complete 5-phase pipeline with exact rules.

**Pipeline overview:**
1. **Understand** — restate the idea, identify unknowns, ask 3–7 clarifying questions as polls or buttons. Never skip this phase even if the idea seems clear.
2. **Plan** — write a Master Plan (overview, architecture, task groups, goal-backward criteria). Present for approval. Gate 1: do NOT write the PRD without approval.
3. **Spec** — write a detailed PRD to `projects/[name]/PRD.md`. Every task = one `- [ ]` checkbox with verifiable acceptance criteria. Present for approval. Gate 2: do NOT hand off without approval.
4. **Handoff** — run `ralphy --init` in the project directory, inject standard rules, launch tmux session with completion hook.

**PRD file location:** `projects/[name]/PRD.md` — always write to disk, never just paste in chat.

**Task format:**
- One `- [ ]` per task, no nesting
- Each task should take 3–5 minutes to complete
- Include a `## Verification Commands` section with typecheck, test, lint commands
- For server projects: make port cleanup (`lsof -ti:PORT | xargs kill -9`) the first task

---

### Build phase — full runbook

**Read:** `loops/SKILL.md` — contains all launch patterns, flag reference, and troubleshooting.

**Basic launch (tmux session with completion hook):**
```bash
tmux -S ~/.tmux/sock new -d -s SESSION_NAME \
  "cd /path/to/repo && [ -f PRD.md ] || { echo '[ERROR] PRD.md not found'; exit 1; } && \
   ralphy --codex --verbose --prd PRD.md -- -c model_reasoning_effort=\"high\"; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'Session SESSION_NAME finished (exit '\$EXIT_CODE').' --mode now; \
   sleep 999999"
```

**Always use:**
- `--verbose` on every run
- High effort: Codex gets it from `~/.codex/config.toml` globally. Claude requires `-- --effort high` on every invocation — there is no persistent config for Claude, so forgetting this flag silently downgrades output quality.
- The `sleep 999999` at the end keeps output readable after the agent finishes

**Verify it launched:**
```bash
tmux -S ~/.tmux/sock has-session -t SESSION_NAME && echo "running" || echo "dead"
```

**PRD preflight (run before every launch):**
```bash
rg -n '^- \[ \] ' PRD.md >/dev/null || { echo '[ERROR] no valid top-level tasks'; exit 1; }
rg -n '^- \[\]' PRD.md >/dev/null && { echo '[ERROR] malformed checkbox'; exit 1; }
rg -n '^[[:space:]]+- \[ \] ' PRD.md >/dev/null && { echo '[ERROR] nested checkboxes'; exit 1; }
```

**Project memory setup (first time per project):**
```bash
cd /path/to/repo && ralphy --init
ralphy --add-rule "Read .ralphy/progress.txt FIRST for context from previous iterations"
ralphy --add-rule "After completing your task, APPEND learnings to .ralphy/progress.txt"
ralphy --add-rule "Run ALL verification commands before marking a task complete"
ralphy --add-rule "Make a git commit with a descriptive message after each completed task"
```

**Parallel execution:**
```bash
ralphy --codex --parallel --max-parallel 3 --verbose --prd PRD.md -- -c model_reasoning_effort="high"
```

**AFK/unattended runs** — always set an iteration cap:
```bash
ralphy --codex --prd PRD.md --max-iterations 30 -- -c model_reasoning_effort="high"
```
Set to 1.5–2× your task count. Without it, a confused agent can loop indefinitely.

**Three-phase pipeline:**
```bash
# Phase 1: UI (Claude Code)
tmux -S ~/.tmux/sock new -d -s myapp-frontend \
  "cd /path/to/app && ralphy --claude --verbose --prd FRONTEND-PRD.md -- --effort high; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'Phase 1 done (exit '\$EXIT_CODE').' --mode now; sleep 999999"

# Phase 2: Backend (Codex) — start after Phase 1 completes
tmux -S ~/.tmux/sock new -d -s myapp-backend \
  "cd /path/to/app && ralphy --codex --verbose --prd BACKEND-PRD.md -- -c model_reasoning_effort=\"high\"; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'Phase 2 done (exit '\$EXIT_CODE').' --mode now; sleep 999999"

# Phase 3: Integration (Codex) — start after Phase 2 completes
tmux -S ~/.tmux/sock new -d -s myapp-integration \
  "cd /path/to/app && ralphy --codex --verbose --prd INTEGRATION-PRD.md -- -c model_reasoning_effort=\"high\"; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'Phase 3 done (exit '\$EXIT_CODE').' --mode now; sleep 999999"
```

**Cross-model review:**
```bash
# Claude reviews Codex output (focus: UX, edge cases, complexity)
ralphy --claude --verbose -- --effort high "Review last 10 commits for UX issues, edge cases, simplification opportunities. Write REVIEW.md."

# Codex reviews Claude output (focus: bugs, security, error handling)
ralphy --codex --verbose -- -c model_reasoning_effort="high" "Review last 10 commits for bugs, missing error handling, security issues. Write REVIEW.md. Fix critical issues."
```

**GitHub integration:**
```bash
ralphy --codex --github owner/repo --github-label ralph --verbose     # Work through labeled issues
ralphy --codex --sync-issue 42 --github owner/repo --prd PRD.md       # Push PRD to a GitHub issue
```

**Session management:**
```bash
tmux -S ~/.tmux/sock list-sessions                        # List all active sessions
tmux -S ~/.tmux/sock capture-pane -t SESSION -p | tail -20  # Check progress
tmux -S ~/.tmux/sock kill-session -t SESSION              # Kill a session
```

**Monitoring:**
```bash
launchctl list | grep ralph-monitor      # macOS: verify monitor is running
systemctl --user status ralph-monitor    # Linux: verify monitor is running
cat /tmp/ralph-monitor.log               # Recent monitor activity
```

**Flag reference:**

| Flag | What it does |
|------|-------------|
| `--verbose` | Detailed output — always use |
| `--codex` / `--claude` / `--sonnet` | Engine selection |
| `--prd FILE` | Load tasks from markdown checklist (must be before `--`) |
| `--yaml FILE` | Load tasks from YAML (must be before `--`) |
| `--parallel` | Run independent tasks concurrently via git worktrees |
| `--max-parallel N` | Concurrent agent limit (default 3) |
| `--sandbox` | Sandboxes instead of worktrees (faster for large repos) |
| `--no-merge` | Skip auto-merge after parallel |
| `--max-iterations N` | Hard cap on total iterations (safety for AFK) |
| `--max-retries N` | Retries per task (default 3) |
| `--dry-run` | Preview tasks without executing |
| `--fast` | Skip tests and lint (never for production) |
| `--branch-per-task` | Separate branch per task |
| `--create-pr` | Open a PR when done |
| `--github owner/repo` | Work through GitHub issues |
| `--sync-issue N` | Push PRD to a GitHub issue |
| `--init` | Initialize project config |
| `--add-rule "..."` | Add a rule to `.ralphy/config.yaml` |

After `--`: Codex takes `-c model_reasoning_effort="high"`, Claude takes `--effort high`.

**Common problems:**

| Problem | Fix |
|---------|-----|
| Agent exits immediately | Check `~/.codex/log/codex-tui.log` — usually expired auth (`codex auth login`) |
| Wrong task count | Count `- [ ]` lines manually — nested checkboxes inflate the number |
| Port already in use | Add `lsof -ti:PORT \| xargs kill -9` as the first PRD task |
| `--prd` silently ignored | It was placed after `--`. Ralphy flags go before the separator |
| Merge conflicts in parallel | Use YAML `parallel_group` to keep conflicting tasks sequential |
| Monitor not firing | Confirm `echo "EXITED: $EXIT_CODE"` is in the tmux command |
| `--dry-run` hangs | Known issue in ralphy v4.7.2. Skip dry-run if preflight passes |

---

## Templates

- `loops/templates/PRD.md.template` — task checklist format compatible with ralphy
- `loops/templates/AGENTS.md.template` — conventions file Codex reads automatically
- `loops/templates/CLAUDE.md.template` — same for Claude Code
