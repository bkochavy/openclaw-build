---
name: openclaw-build-loops
description: Build software through short, repeating AI agent sessions that recover automatically and track progress through memory files and git commits. Supports Codex and Claude Code as interchangeable engines.
---

# Build Loops

## What This Does

Ralph loops replace a single marathon coding session with many brief ones. Each cycle spins up a fresh agent that reads the project's memory files and git log to understand what happened before, completes the next unchecked task in a PRD, commits the result, and exits. If the agent crashes or gets stuck, the loop restarts it automatically. A background monitor watches every session and sends you a notification when work finishes or progress stalls. The PRD checklist is the source of truth: when every box is checked, the build is done.

## When to Use It

**By task scope:**

Scope | What to do
--- | ---
One-line fix or small bug | Inline: `ralphy --codex "Fix the auth bug"`
Feature touching 1-3 files | Inline with detail: `ralphy --codex "Add rate limiting to /api, 100 req/min"`
4-10 distinct steps | Write a PRD, launch with `--prd PRD.md`
10+ steps, many independent | PRD with `--parallel`
Full-stack app (UI + backend) | Split into separate PRDs per concern

**By work type:**

Work | Engine
--- | ---
UI, styling, design, components | `--claude`
Backend, APIs, data, logic | `--codex`
Anything else | `--codex` (faster default)
Low-priority, cost-sensitive | `--sonnet`

Rule of thumb: if you can describe it in two sentences, go inline. Four or more separate steps belong in a PRD. When 40% of tasks can run independently, add `--parallel`.

## Quick Start

**One-off task (no PRD):**
```bash
tmux -S ~/.tmux/sock new -d -s my-fix \
  "cd /path/to/repo && \
   ralphy --codex --verbose -- -c model_reasoning_effort=\"high\" 'Fix the broken login redirect'; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; sleep 999999"
```

**PRD-based build:**
```bash
cd /path/to/repo
ralphy --init
# Edit .ralphy/config.yaml with your project details

tmux -S ~/.tmux/sock new -d -s my-build \
  "cd /path/to/repo && [ -f PRD.md ] || { echo '[ERROR] PRD.md not found'; exit 1; } && \
   export RALPH_TELEGRAM_CHAT_ID=\"\${RALPH_TELEGRAM_CHAT_ID:-}\"; \
   ralphy --codex --verbose --prd PRD.md -- -c model_reasoning_effort=\"high\"; \
   EXIT_CODE=\$?; echo EXITED: \$EXIT_CODE; \
   openclaw system event --text 'Session my-build finished (exit '\$EXIT_CODE').' --mode now; \
   sleep 999999"
```

**Verify it launched:**
```bash
tmux -S ~/.tmux/sock has-session -t my-build && echo "running" || echo "dead"
```

## Engines

Codex and Claude Code both work as the underlying coding agent. Pick the one that fits your task, then forget about it.

**Codex** (`--codex`): Stronger at backend logic, API design, data modeling. Set reasoning effort globally in `~/.codex/config.toml` or per-run with `-- -c model_reasoning_effort="high"`.

**Claude Code** (`--claude`): Better for frontend work, component design, visual polish. Requires `-- --effort high` on every invocation since there is no global config for it.

**Sonnet** (`--sonnet`): Cheaper but less capable. Suitable for boilerplate, formatting tasks, and anything where quality is not critical.

Shell aliases `ralphy-codex` and `ralphy-claude` in `~/.zshrc` bundle the effort flags so you do not have to remember them.

Ralphy flags like `--prd` and `--yaml` must always appear before the `--` separator. Anything after `--` gets forwarded to the engine. Putting ralphy flags on the wrong side is a silent failure.

## The Loop Pattern

Long agent sessions degrade over time. After several iterations of accumulated context, the model slows down and its output quality drops. Stale failure traces from earlier attempts pollute the context window.

Ralph loops solve this by keeping each cycle stateless. The agent starts with zero conversation history and rebuilds context from durable sources:

- **`.ralphy/progress.txt`**: Append-only log where each cycle records what it learned and what tripped it up.
- **`.ralphy/config.yaml`**: Project-level settings, verification commands, and file boundaries.
- **`CLAUDE.md` / `AGENTS.md`**: Conventions that Claude Code and Codex auto-load on startup.
- **Git history**: The commit log shows exactly what previous cycles accomplished.
- **PRD checklist state**: Checked boxes tell the agent what is already done.

Set up memory on first use:
```bash
ralphy --add-rule "Read .ralphy/progress.txt FIRST for context from previous iterations"
ralphy --add-rule "After completing your task, APPEND learnings to .ralphy/progress.txt"
ralphy --add-rule "Update CLAUDE.md or AGENTS.md if you discover new project patterns"
ralphy --add-rule "Run ALL verification commands before marking a task complete"
ralphy --add-rule "Make a git commit with a descriptive message after each completed task"
ralphy --add-rule "Before starting any server, kill existing processes on the target port: lsof -ti:PORT | xargs kill -9 2>/dev/null || true"
```

## Writing a Good PRD

The PRD is a markdown file with checkboxes. Ralphy treats every `- [ ]` in the file as a task, regardless of indentation or nesting. There is no hierarchy. One checkbox equals one unit of work.

**Checkbox rules:**
- Use `- [ ]` only for top-level tasks. Acceptance criteria, sub-steps, and notes go in plain bullets or numbered lists.
- Keep each task on a single line, under 200 characters.
- Nested `- [ ]` will inflate your task count silently. If ralphy reports 40 tasks and you wrote 12, check for nesting.

**Good task sizing:** Each task should take an agent 3-5 minutes. If one takes longer than 7 minutes, it is too broad and should be split.

**Always include verification commands:**
```markdown
## Verification Commands
- Typecheck: `npx tsc --noEmit`
- Tests: `npm test`
- Lint: `npx eslint .`
```

**For server projects**, make port cleanup the first task:
```markdown
- [ ] Kill any existing process on port 8080: `lsof -ti:8080 | xargs kill -9 2>/dev/null || true`
```

**Validate before launching** to catch malformed checkboxes:
```bash
rg -n '^- \[ \] ' PRD.md >/dev/null || { echo '[ERROR] no valid top-level tasks'; exit 1; }
rg -n '^- \[\]' PRD.md >/dev/null && { echo '[ERROR] malformed checkbox "- []"'; exit 1; }
rg -n '^[[:space:]]+- \[ \] ' PRD.md >/dev/null && { echo '[ERROR] nested checkboxes found'; exit 1; }
```

**YAML alternative** (`--yaml tasks.yaml`): Better for longer task descriptions and explicit parallel grouping. Put everything in the `title` field since `description` is unreliable in YAML format.

## Running in Parallel

When your PRD has tasks that do not depend on each other, parallelism cuts build time significantly.

**Built-in parallel mode:**
```bash
ralphy --codex --parallel --max-parallel 3 --verbose --prd PRD.md -- -c model_reasoning_effort="high"
```
Ralphy creates git worktrees for each concurrent task and auto-merges results.

**YAML with parallel groups** gives you explicit control over ordering:
```yaml
tasks:
  - title: Set up project structure
    parallel_group: 1
  - title: Create User model
    parallel_group: 2
  - title: Create Post model
    parallel_group: 2
  - title: Build auth endpoints
    parallel_group: 3
```
Tasks in the same group run concurrently. Higher-numbered groups wait for lower ones to finish.

**Folder mode** for splitting by concern:
```bash
ralphy --codex --parallel --verbose --prd ./prd/ -- -c model_reasoning_effort="high"
```

**Sandbox mode** for large repos with heavy dependency trees:
```bash
ralphy --codex --parallel --sandbox --max-parallel 4 --verbose --prd PRD.md -- -c model_reasoning_effort="high"
```

**Manual parallel** when you want different engines on different parts: launch two tmux sessions, one with `--claude --prd PRD-ui.md` and one with `--codex --prd PRD-api.md`. Stagger by 2 minutes to avoid API rate bursts.

Parallelize when tasks touch different files or services. Avoid it when tasks have sequential dependencies or modify the same files.

## Monitoring

`ralph-monitor.sh` runs on a 10-minute timer (launchd on macOS, systemd on Linux) and watches all Ralph tmux sessions without consuming any API tokens.

It detects three conditions:
1. **Completion**: The session output contains `EXITED:` followed by an exit code. Fires a notification.
2. **Stall**: Output has not changed in 30+ minutes. Fires a warning.
3. **Cleanup**: Completed sessions older than 30 minutes get killed automatically.

Install with `./install.sh`, which places the script at `~/.openclaw/bin/ralph-monitor.sh` and schedules the timer.

The completion hook in the tmux template (`echo EXITED: $EXIT_CODE` + `openclaw system event`) is what triggers detection. Without that line, the monitor cannot see that a session finished.

## Common Problems

**"No tasks remaining" on first run**: Your PRD probably has malformed checkboxes (`- []` instead of `- [ ]`) or only nested ones. Run the preflight validation.

**Agent exits immediately**: Check `~/.codex/log/codex-tui.log`. Usually means auth has expired (`codex auth login`).

**Wrong task count**: Count the `- [ ]` lines yourself. If your count differs from what ralphy reports, there are stray checkboxes in non-task sections.

**Port already in use (EADDRINUSE)**: Previous cycle left a server running. Add port cleanup as the first PRD task or as a rule in `.ralphy/config.yaml`.

**Merge conflicts in parallel mode**: Two tasks touched the same file. Use `--no-merge` and resolve manually, or restructure with YAML parallel groups that keep conflicting tasks sequential.

**`--prd` flag silently ignored**: It was placed after `--`. Ralphy flags go before the separator, engine flags go after.

**`--dry-run` hangs indefinitely**: Known issue in ralphy v4.7.2 with long task titles. If preflight passes, skip the dry run and launch directly.

**Monitor not firing**: Confirm the timer is scheduled (`launchctl list | grep ralph-monitor`) and that `echo "EXITED: $EXIT_CODE"` is present in your tmux command.

## Key Rules

1. Keep tasks small: 3-5 minutes each, 7 minutes maximum.
2. Run inside tmux with the `~/.tmux/sock` socket. Background processes (`&`) are not recoverable.
3. Use `--verbose` and high effort on every run.
4. Guard PRD-based launches with `[ -f PRD.md ]` in the tmux command.
5. Validate your PRD with the preflight checks before launching.
6. Include the completion hook (`EXITED` echo + `openclaw system event` + `sleep`) in every tmux session.
7. Checkboxes (`- [ ]`) are only for top-level tasks. Everything else uses plain bullets.
8. Review finished builds with the opposite engine: Claude Code reviews Codex output and vice versa.
9. Log each launch in your daily notes before starting.
10. Confirm the session is alive after launching. Do not report success without verification.
