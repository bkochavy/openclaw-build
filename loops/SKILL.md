---
name: coding-agent-loops
description: Run AI coding agents (Codex, Claude Code) in persistent tmux sessions with Ralph retry loops and completion hooks. Handles everything from quick one-liner fixes to multi-phase app builds. Use for ANY coding task — the skill decides whether it needs a PRD, inline task, parallel execution, or the full pipeline.
---

# Coding Agent Loops

Run AI coding agents in persistent, self-healing sessions with automatic retry, monitoring, and completion notification.

## When to Use What (Read This First)

Not everything needs a PRD. Not everything needs a pipeline. Match the tool to the job:

| Size | Approach |
|------|----------|
| **Bug fix / tweak** | Inline: `ralphy --codex "Fix the bug in auth.ts"` |
| **Small feature** (1-3 files) | Inline with detail: `ralphy --codex "Add rate limiting to /api, 100 req/min"` |
| **Medium feature** (4-10 tasks) | PRD: `ralphy --codex --prd PRD.md` |
| **Large build** (10+ tasks) | PRD + parallel: `ralphy --codex --parallel --prd PRD.md` |
| **Full-stack app** (15+ tasks, UI + API) | Consider three-phase pipeline (see below) |

| Work type | Engine |
|-----------|--------|
| **UI/UX, styling, components, design** | `--claude` (Claude Code) |
| **Backend, APIs, logic, data, infra** | `--codex` (Codex) |
| **General / don't care** | `--codex` (faster, default) |
| **Cheaper tasks (not critical)** | `--sonnet` (Claude Sonnet) |

**Decision rules:** 1-2 sentence description → inline, no PRD. 4+ distinct steps → write a PRD. 40%+ independent tasks → add `--parallel`. Three-phase pipeline → full-stack apps only.

**Task sizing:** Target 3-5 min/task. >7 min means it's too big — split it. Baseline: 72 tasks across 6 sessions averaged 4.9 min/task.

## Core Concept

Instead of one long agent session that stalls or dies, run many short sessions in a loop. Each iteration starts fresh — no accumulated context window. The agent picks up where it left off via **structured memory files** and git history. This is the "Ralph loop" pattern.

**Why fresh context?** After 3-5 iterations, models accumulate noise from past failures. Token processing slows. Output quality degrades ("context rot"). Fresh starts with external memory files avoid this.

**Memory between iterations:** `.ralphy/progress.txt` (append-only learnings), `.ralphy/config.yaml` (project rules), `CLAUDE.md`/`AGENTS.md` (conventions auto-read by CLIs), git history, PRD checklist state.

## Prerequisites

- `tmux`, stable socket at `~/.tmux/sock` (macOS reaps `/tmp`)
- `ralphy-cli` v4.7.2+: `npm install -g ralphy-cli`
- Engine: `codex` (Codex CLI) or `claude` (Claude Code)
- `jq` for `ralph-monitor.sh`

## Setting up ralph-monitor

Install once per machine:

```bash
./install.sh
```

This installs `scripts/ralph-monitor.sh` to `~/.openclaw/bin/ralph-monitor.sh`, creates `~/.openclaw/ralph-monitor.json` if missing, and schedules it every 10 minutes (launchd on macOS, systemd-user timer on Linux).

## Project Setup (Before First PRD Run)

Not needed for inline tasks. Required before first PRD-based launch:

```bash
cd /path/to/repo
ralphy --init
ralphy --add-rule "Read .ralphy/progress.txt FIRST for context from previous iterations"
ralphy --add-rule "After completing your task, APPEND learnings to .ralphy/progress.txt"
ralphy --add-rule "Update CLAUDE.md or AGENTS.md if you discover new project patterns"
ralphy --add-rule "Run ALL verification commands before marking a task complete"
ralphy --add-rule "Make a git commit with a descriptive message after each completed task"
ralphy --add-rule "Before starting any server, kill existing processes on the target port: lsof -ti:PORT | xargs kill -9 2>/dev/null || true"
```

Then edit `.ralphy/config.yaml` (project name, language, framework, test/lint/build commands, boundaries for files agents should never touch). Template at `skills/coding-agent-loops/templates/`.

Create `CLAUDE.md` (for Claude Code) or `AGENTS.md` (for Codex) from templates in `skills/coding-agent-loops/templates/`.

## The tmux Launch Template

**All Ralph launches use this template.** Replace `SESSION`, `REPO`, `GUARD`, and `RALPHY_CMD`:

```bash
tmux -S ~/.tmux/sock new -d -s SESSION \
  "cd REPO && GUARD \
   export RALPH_TELEGRAM_CHAT_ID=\"\${RALPH_TELEGRAM_CHAT_ID:-}\"; \
   RALPHY_CMD; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'RALPH POST-COMPLETION: Session SESSION finished (exit '\$EXIT_CODE') in REPO. Run the Post-Completion Protocol from AGENTS.md now: verify tests, commit, install/link if needed, smoke test, and notify the operator.' --mode now; \
   sleep 999999"
```

**GUARD** (include for PRD launches, omit for inline):
```bash
[ -f PRD.md ] || { echo '[ERROR] PRD.md not found in '$(pwd); exit 1; };
```

**Why each part matters:**
- PRD guard → catches the #1 false start (wrong directory)
- `echo EXITED:` → triggers the monitor daemon
- `openclaw system event` → immediate wake notification
- `sleep 999999` → keeps output readable (monitor auto-kills after 30 min)

### RALPHY_CMD by scenario

| Scenario | RALPHY_CMD |
|----------|------------|
| **Inline fix** | `ralphy --codex --verbose -- -c model_reasoning_effort=\"high\" 'Fix the auth bug'` |
| **PRD (Codex)** | `ralphy --codex --verbose --prd PRD.md -- -c model_reasoning_effort=\"high\"` |
| **PRD (Claude)** | `ralphy --claude --verbose --prd PRD.md -- --effort high` |
| **PRD + parallel** | `ralphy --codex --parallel --max-parallel 3 --verbose --prd PRD.md -- -c model_reasoning_effort=\"high\"` |
| **AFK with cap** | `ralphy --codex --max-iterations 30 --verbose --prd PRD.md -- -c model_reasoning_effort=\"high\"` |
| **Browser tasks** | `ralphy --claude --browser --verbose --prd PRD.md -- --effort high` |

**⚠️ CRITICAL: `--prd` and `--yaml` go BEFORE `--`.** Everything after `--` is passed to the engine. Putting ralphy flags after `--` is a silent failure — the engine ignores them and ralphy runs without a PRD.

**Effort is always high:** Codex has it in `~/.codex/config.toml` globally. Claude needs `-- --effort high` every time. Shell aliases `ralphy-codex` and `ralphy-claude` (in `~/.zshrc`) include these.

## Launch Protocol (Non-Negotiable)

1. **Pick the right approach** — re-read "When to Use What" above.
2. **Log it** in today's `life/YYYY-MM-DD.md` (session name, repo, PRD, start time).
3. **Project setup** if first PRD run in this repo (see above).
4. **Run PRD preflight (mandatory):** validate task parsing before launch (see preflight section below).
5. **Dry-run is optional and timed:** use only as a smoke check with timeout. If it loops, kill it and continue after preflight passes.
   - Example: `perl -e 'alarm 8; exec @ARGV' ralphy --codex --dry-run --prd PRD.md`
   - If it times out but preflight is clean, launch the real run.
6. **Port cleanup** for server projects (as PRD task 1 or `.ralphy/config.yaml` rule).
7. **Launch** the tmux session (see template above).
8. **Verify alive:** `tmux -S ~/.tmux/sock has-session -t <name> && echo "running" || echo "dead"`
9. **Never tell the user "launched" without confirming step 8.**

After launch, `ralph-monitor.sh` handles monitoring (10 min interval, zero tokens): detects completion → fires notification, detects stalls (30+ min same output) → fires warning, auto-kills completed sessions after 30 min.

## PRD Preflight (Required Before Launch)

Use preflight to catch parser issues without relying on `--dry-run` behavior:

```bash
# 1) Must parse at least one top-level task
rg -n '^- \[ \] ' PRD.md >/dev/null || { echo '[ERROR] no valid top-level tasks'; exit 1; }

# 2) Reject malformed checkboxes (common cause of "No tasks remaining")
rg -n '^- \[\]' PRD.md >/dev/null && { echo '[ERROR] malformed checkbox "- []"'; exit 1; }

# 3) Reject nested checkboxes (creates wrong task counts)
rg -n '^[[:space:]]+- \[ \] ' PRD.md >/dev/null && { echo '[ERROR] nested checkboxes found'; exit 1; }

# 4) Warn on pre-checked tasks unless intentionally resuming
rg -n '^- \[[xX]\] ' PRD.md >/dev/null && echo '[WARN] pre-checked tasks found (resume mode?)'
```

If you want immutable run state, copy the PRD before launch:
```bash
cp PRD.md RUN-PRD-$(date +%Y%m%d-%H%M%S).md
```

## Parallel Execution

### Built-in (`--parallel`)
Add `--parallel --max-parallel 3` to any PRD launch. Ralphy creates git worktrees for independent tasks, runs concurrently, auto-merges. A 20-task PRD with 60% independent tasks: ~100 min → ~40 min.

### YAML with explicit parallel groups (best control)
```yaml
tasks:
  - title: Set up project structure
    parallel_group: 1
  - title: Create User model
    parallel_group: 2
  - title: Create Post model
    parallel_group: 2  # same group = concurrent
  - title: Build auth endpoints
    parallel_group: 3  # waits for group 2
  - title: Write integration tests
    parallel_group: 4
```
Launch: `ralphy --codex --parallel --verbose --yaml tasks.yaml -- -c model_reasoning_effort="high"`

YAML > markdown for parallel: explicit groups vs ralphy guessing dependencies.

### PRD folder mode
Split by concern (`prd/01-setup.md`, `prd/02-models.md`, etc.):
`ralphy --codex --parallel --verbose --prd ./prd/ -- -c model_reasoning_effort="high"`

### Sandboxes (faster for large repos)
`ralphy --codex --parallel --sandbox --max-parallel 4 --verbose --prd PRD.md -- -c model_reasoning_effort="high"`
Symlinks `node_modules`/`.git`, copies only source. Much faster than worktrees for large dependency trees.

### Manual parallel (different engines)
Use separate tmux sessions with the template above — one for `--claude --prd PRD-ui.md`, one for `--codex --prd PRD-api.md`. Stagger launches by 2 min to avoid API burst.

### When to parallelize
✅ UI components, multi-service, test suites, model/migration creation
❌ Sequential dependencies (auth → routes → admin), single-file fixes

## PRD Format

### ⚠️ Critical: Checkbox Parsing Rules

Ralphy's markdown parser treats **every** `- [ ]` in the entire file as a task. It does NOT understand nesting or sections. This means:

**NEVER use `- [ ]` for anything except top-level tasks.** Acceptance criteria, sub-items, notes — use `- ` (plain bullets), numbered lists, or bold text. One `- [ ]` = one task. No exceptions.

```markdown
❌ WRONG (creates 5 tasks instead of 1):
- [ ] Build auth system
  - [ ] Add login endpoint
  - [ ] Add JWT validation
  - [ ] Write tests
  - [ ] npm test passes

✅ RIGHT (creates 1 task):
- [ ] Build auth system with login endpoint, JWT validation, and tests. Run npm test.
```

**Each task = one line.** Keep it under ~200 chars. Put context in a `## Context` section above the tasks (ralphy passes the full PRD to the agent, not just the task title).

### When to use YAML instead of Markdown

Use `--yaml tasks.yaml` when:
- Tasks need multi-sentence descriptions (markdown gets messy)
- You want explicit parallel groups
- You have 15+ tasks (YAML is easier to maintain)

```yaml
tasks:
  - title: "Build auth — login endpoint with JWT, bcrypt passwords, refresh tokens. Write tests. npm test && npm run typecheck."
    parallel_group: 1
  - title: "Build dashboard — React components for metrics, charts, user table. npm test && npm run typecheck."
    parallel_group: 1
```

**YAML caveats:**
- `--dry-run` may infinite-loop with long titles (known ralphy bug as of v4.7.2). If task count looks correct in the first few lines, skip dry-run.
- The `description` field works in JSON format but not reliably in YAML. Put everything in `title`.
- Titles must be unique across all tasks.

### TDD by default
Every logic task needs test-first:
```markdown
- [ ] Write failing tests for user auth endpoint
- [ ] Implement auth endpoint to pass tests
- [ ] Run full test suite — all tests pass
```
Skip TDD only for: config changes, copy edits, formatting, static files.

### Include verification commands
```markdown
## Verification Commands
- Typecheck: `npx tsc --noEmit`
- Tests: `npm test`
- Lint: `npx eslint .`
```
Should match `.ralphy/config.yaml` commands.

### Server projects — port cleanup as task 1
```markdown
- [ ] Kill any existing process on port 8080: `lsof -ti:8080 | xargs kill -9 2>/dev/null || true`
```

### Iteration limits for AFK runs
`--max-iterations` = 1.5-2× your task count. Template at `skills/coding-agent-loops/templates/PRD.md.template`.

## Post-Loop Review (Cross-Model)

After completion, review with a DIFFERENT model — one builds, another reviews:
- **Codex reviews Claude's work:** `ralphy --codex --verbose -- -c model_reasoning_effort="high" "Review last 10 commits for bugs, missing error handling, security issues. Write REVIEW.md. Fix critical issues."`
- **Claude reviews Codex's work:** `ralphy --claude --verbose -- --effort high "Review last 10 commits for UX issues, edge cases, simplification opportunities. Write REVIEW.md."`

Always for production/security-sensitive code. Skip for prototypes.

## Three-Phase Build Pipeline (Optional — Full-Stack Only)

**When:** Full-stack app, 15+ tasks, frontend/backend are distinct concerns. **Not for:** single-concern projects, small features, fixes.

| Phase | Engine | PRD | Use for |
|-------|--------|-----|---------|
| 1. Frontend | `--claude` | `FRONTEND-PRD.md` | UI, components, styling, design |
| 2. Backend | `--codex` | `BACKEND-PRD.md` | APIs, logic, data, auth |
| 3. Integration | `--codex` | `INTEGRATION-PRD.md` | Wire together, e2e, polish |

Launch sequentially (each builds on previous). Use the tmux template with appropriate `RALPHY_CMD`.

**Phase 1 setup:** Install Anthropic's `frontend-design` + `webapp-testing` skills into `.claude/skills/` for premium UI output.

## GitHub Integration

```bash
ralphy --codex --github owner/repo --github-label ralph --verbose   # Work through labeled issues
ralphy --codex --sync-issue 42 --github owner/repo --prd PRD.md     # Sync PRD → issue
```

## Session Management

```bash
tmux -S ~/.tmux/sock capture-pane -t my-task -p | tail -20   # Check progress
tmux -S ~/.tmux/sock list-sessions                            # List all
tmux -S ~/.tmux/sock kill-session -t my-task                  # Kill one
```

## Ralphy CLI Reference

| Flag | Purpose |
|------|---------|
| `--verbose` | Detailed output — **always use** |
| `--codex` / `--claude` / `--sonnet` | Engine selection |
| `--prd PRD.md` | Task file (**must go before `--`**) |
| `--yaml FILE` / `--json FILE` | Alt task formats (**must go before `--`**) |
| `"inline task"` | Single task string (no PRD) |
| `--parallel` | Enable parallel via worktrees |
| `--max-parallel <n>` | Max concurrent agents (default: 3) |
| `--sandbox` | Sandboxes instead of worktrees (faster) |
| `--no-merge` | Skip auto-merge after parallel |
| `--max-iterations <n>` | Cap iterations (safety for AFK) |
| `--max-retries <n>` | Retries per task (default: 3) |
| `--dry-run` | Preview tasks without executing |
| `--browser` | Enable browser automation |
| `--fast` | Skip tests + lint (**never for production**) |
| `--branch-per-task` | One branch per task |
| `--create-pr` / `--draft-pr` | Auto-create PRs |
| `--github owner/repo` | Work from GitHub issues |
| `--sync-issue <n>` | Sync PRD to GitHub issue |
| `--init` / `--config` / `--add-rule` | Project setup |

**Engine passthrough** (after `--`):
- Codex: `-c model_reasoning_effort="high"`
- Claude: `--effort high`

## Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| EADDRINUSE | Old server on port | Port cleanup as PRD task 1 or `.ralphy/config.yaml` rule |
| PRD not found | Wrong `cd` directory | `[ -f PRD.md ]` guard in tmux command (in template) |
| Session sprawl | No cleanup | Monitor auto-kills after 30 min. Manual: `tmux kill-session` |
| Task >7 min, agent stuck | Task too broad | Split it and rerun preflight |
| Network retries add 5-10 min | API disconnections | `--max-retries 2`, `--max-parallel 2` |
| Parallel merge conflicts | Same file modified | `--no-merge` + manual, or YAML `parallel_group` |
| `--prd` silently ignored | Flag after `--` separator | **Always put `--prd` BEFORE `--`** |
| Git identity warnings | No git config | `git config --global user.name/email` |
| PATH not found in tmux | Incomplete env | Prepend `/opt/homebrew/bin:` to PATH |
| Agent re-discovers patterns | No progress file | Check `.ralphy/progress.txt` exists, rules include append |
| PRD creates wrong # of tasks | `- [ ]` used for sub-items/criteria | Only use `- [ ]` for top-level tasks. Use plain `- ` or numbers for everything else |
| `--dry-run` infinite loops | Known ralphy dry-run path issues (v4.7.2) | Use mandatory preflight + timed dry-run (or skip dry-run) |
| 93 tasks instead of 21 | Nested checkboxes in PRD | Flatten — one `- [ ]` per task, no nesting |

## Troubleshooting

- **Agent exits immediately:** Check `~/.codex/log/codex-tui.log`. May need `codex auth login`.
- **"No config found":** Run `ralphy --init`.
- **Tasks marked done, nothing committed:** Verify `git log --oneline -3` and `git diff --stat`.
- **Rate limits (429s):** Reduce `--max-parallel` or stagger launches.
- **Monitor not running:** `launchctl list | grep ralph-monitor`. Reload plist.
- **Monitor not detecting completion:** Ensure `echo "EXITED: $EXIT_CODE"` is in tmux command.
- **Wrong task count:** Count `- [ ]` lines in your PRD — that's your task count. If it doesn't match what ralphy reports, you have nested checkboxes or stray `- [ ]` in non-task sections.

## Key Principles

1. **Match tool to task** — inline for fixes, PRD for multi-step, pipeline for full-stack only.
2. **Always tmux** with `~/.tmux/sock`. Never `&` in exec.
3. **Always `--verbose`**, always high effort.
4. **Always guard PRD** in tmux commands (`[ -f PRD.md ]`).
5. **Always run PRD preflight.** Treat `--dry-run` as optional smoke test with timeout, not a gate.
6. **Always completion hook** (EXITED echo + system event + sleep).
7. **Always log** in daily notes before launching.
8. **Default `--parallel`** for 40%+ independent tasks.
9. **Verify before declaring done** — `git log`, `git diff`, run verification.
10. **TDD by default** — skip only for config/docs/assets.
11. **`--prd` goes BEFORE `--`** — engine flags go after, ralphy flags go before.
12. **Cross-model review** for production code.
13. **3-5 min/task target** — bigger = split it.
