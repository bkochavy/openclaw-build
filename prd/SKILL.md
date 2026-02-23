---
name: prd-writer
description: "Turn a rough idea into a detailed PRD through structured conversation. Use when: user has a product/feature idea and needs a spec, someone says 'spec this', 'write a PRD', 'plan this feature', 'build me X' (where X needs scoping first), 'prd', 'spec', '/spec'. Produces a PRD compatible with openclaw-coding-loops and ready for handoff."
metadata: {"openclaw":{"emoji":"📋"}}
---

# PRD Writer

Turn a rough idea into a build-ready PRD through a structured conversation.

**You are a facilitator, not a generator.** Ask questions, extract answers, THEN generate. Never produce content and ask "is this right?" — instead, gather what you need and get it right the first time.

## The Pipeline

```
IDEA → Understand → Plan → [Approve] → Spec → [Approve] → Handoff
```

Five phases, two approval gates. Each phase has a clear deliverable.

## Phase 1: UNDERSTAND

**Goal:** Know exactly what the user wants to build and why.

1. **Restate** the idea in your own words (1-2 sentences)
2. **Identify unknowns** — what's ambiguous or missing?
3. **Ask 3-7 clarifying questions** using **polls or inline buttons (channel-dependent)**. Polls display full option text and can work cleanly cross-thread; inline buttons are better for simple yes/no confirmations like approval gates.

### Question Design

Each question should have 3-4 concrete options + "Other." Use polls or inline buttons (channel-dependent) so the user can tap, not type.

**Good questions** resolve genuine ambiguity:
- "Who's the user?" → `[Our team only] [Public users] [Both]`
- "What's the MVP scope?" → `[Bare minimum] [Polished v1] [Full vision]`
- "Greenfield or existing codebase?" → `[New project] [Add to X] [Replace Y]`

**Bad questions** ask what's already obvious from context. If the user said "build me a Chrome extension for tab management" — don't ask "What platform?" Don't ask questions where the answer is implied.

Ask as many questions as genuinely needed (3-7 typical). Never pad with filler questions, never skip a question that would prevent a bad PRD.

**After the user answers:** If anything is still ambiguous, ask 1-2 follow-ups. Otherwise, move to Phase 2.

## Phase 2: PLAN

**Goal:** Lightweight architecture + task breakdown that the user approves before detailed spec work.

Generate a **Master Plan** (not a PRD yet):

### Master Plan Format

```markdown
# Master Plan: [Project Name]

## Overview
[1 paragraph: what we're building and why]

## Architecture
[High-level approach — stack, key components, data flow]
[If applicable: schema sketch, API shape, key integrations]

## Task Groups
[Break the work into 2-6 logical groups with dependencies]

| Group | Description | Depends On | ~Tasks |
|-------|-------------|------------|--------|
| 1. Setup | Project scaffold, config, CI | — | 3 |
| 2. Core | Main feature logic | 1 | 5 |
| ...  | ... | ... | ... |

## Goal-Backward Criteria
[For each group: "What must be TRUE when this group is complete?"]
- Group 1: Project runs locally, tests pass, CI green
- Group 2: User can [core action] and see [expected result]
- ...

## Out of Scope
[Explicit list of what this does NOT include]

## Open Questions
[Anything still unresolved — ideally empty]
```

**Keep it lightweight.** No code snippets, no file paths, no implementation detail. That's the PRD's job.

Present the Master Plan, then:

```
[Approve Plan ✅] [Change Something ✏️] [Start Over 🔄]
```

**This is Gate 1.** Do NOT proceed to Phase 3 without explicit approval.

If you want changes, discuss and revise. Loop until approved.

## Phase 3: SPEC

**Goal:** Detailed PRD so specific that a coding agent needs zero decisions.

Read `references/prd-template.md` for the full template. Key principles:

### Task Granularity
- Each task completable without decisions. If it requires a decision, split it.
- Acceptance criteria must be **verifiable** — "works correctly" is banned. "Button shows confirmation dialog before deleting" is good.
- Use **goal-backward criteria**: "What must be TRUE?" not "What do we build?"

### Pre-Code Artifacts
Include these sections ONLY when applicable (don't force them):
- **Schema** — if there's a database, specify tables/columns/types
- **System Prompts** — if the product uses LLM calls, write the prompts
- **Business Logic** — pricing rules, access control, notification triggers in plain English
- **Constraints** — hard technical/business boundaries ("Must use X", "No Y")

### Output Format

Write the PRD to: `projects/[project-name]/PRD.md`

The PRD must be compatible with openclaw-coding-loops task format. Each user story maps to a coding-loop task with acceptance criteria as the verification checklist.

Present the PRD file path, then:

```
[Approve PRD ✅] [Edit Something ✏️] [Back to Plan 🔙]
```

**This is Gate 2.** Do NOT proceed to handoff without explicit approval.

## Phase 4: HANDOFF

**Goal:** Set up everything for an openclaw-coding-loops launch.

After PRD approval:

1. Confirm project directory exists at `projects/[project-name]/`
2. Present the launch command:
   ```
   Ready to build! Next step:
   SKILL REQUIRED: Read skills/openclaw-coding-loops/SKILL.md
   Then: ralphy --init in projects/[project-name]/
   Then: launch openclaw-coding-loops with the PRD
   ```
3. Offer button:
   ```
   [Launch Build 🚀] [I'll do it manually ⏸️]
   ```

If "Launch Build 🚀" — follow the openclaw-coding-loops skill to set up and launch the build. Run `ralphy --init`, inject standard rules, and start the tmux session with completion hooks.

## Cross-Thread Execution

When running a PRD interview in a different thread/topic than where it was triggered:
- **Drive everything from the calling session.** Use `message` tool to send questions to the target thread.
- **Button callbacks route to the target thread's session** — so either run the interview IN that session, or collect answers via regular messages, not buttons.
- **If using buttons cross-thread:** Include the full question + answer text in `callback_data` so the receiving session has context (e.g. `"q1: Files + previews + editor"`).
- **Simplest pattern:** Ask all questions in a single message, have the user reply with "1C, 2B, 3A" style answers.

## Rules

- **NEVER skip Phase 1.** Even if the idea seems clear, ask at least 2-3 questions.
- **NEVER generate the PRD without Gate 1 approval** of the Master Plan.
- **NEVER hand off without Gate 2 approval** of the PRD.
- **NEVER pad questions.** Every question must resolve genuine ambiguity.
- **ALWAYS use polls or inline buttons (channel-dependent)** for questions and approvals.
- **ALWAYS write PRD to disk** — don't just paste it in chat. The user needs a file.
- **Keep the conversation moving.** Don't over-explain phases or meta-process. Just DO each phase.
- **Adapt question count to complexity.** Simple feature = 3 questions. New product = 7+.
- **If the user provides a detailed brief upfront**, skip questions that are already answered. Acknowledge what you know, ask only what's missing.
