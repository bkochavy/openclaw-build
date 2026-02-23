# PRD Template

Use this structure. Include sections only when they add value — don't force empty sections.

```markdown
# PRD: [Project Name]

**Created:** [UTC timestamp]
**Status:** DRAFT | APPROVED
**Master Plan:** [link to master plan if separate]

## 1. Overview
[1-2 paragraphs: what we're building, the problem it solves, who it's for]

## 2. Goals
- [Specific, measurable objective]
- [Another objective]
- [Keep to 3-5 goals max]

## 3. User Stories

### US-001: [Short Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] [Specific, verifiable criterion]
- [ ] [Another criterion]
- [ ] [Tests pass / typecheck passes]
- [ ] [If UI: visual verification step]

**Priority:** P0 | P1 | P2

---

### US-002: [Short Title]
...

## 4. Functional Requirements
- FR-1: [Explicit, unambiguous requirement]
- FR-2: [Another requirement]
- FR-3: [Number them for easy reference]

## 5. Schema (if applicable)
[Tables, columns, types, relationships. Be exact.]

```sql
CREATE TABLE items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 6. API Shape (if applicable)
[Endpoints, methods, request/response shapes]

```
POST /api/items
  body: { name: string }
  response: { id: string, name: string, status: string }
```

## 7. System Prompts (if applicable)
[If the product uses LLM/AI calls, write the exact prompts here]

## 8. Business Logic (if applicable)
[Plain English rules the agent must implement literally]
- When X happens, do Y
- If condition A and B, then C
- Pricing: [formula]

## 9. Constraints
- [Hard technical boundary: "Must use TypeScript"]
- [Hard business boundary: "No external API calls"]
- [Platform constraint: "Must run on Cloudflare Workers"]

## 10. Non-Goals
- [Explicit: what this does NOT include]
- [Prevents scope creep during implementation]

## 11. Technical Considerations
- [Known dependencies or integration points]
- [Performance requirements]
- [Existing patterns to follow]

## 12. Success Metrics
- [How do we know this worked?]
- [Measurable outcome, not "it works"]

## 13. Verification Commands
[Commands the agent runs to verify the build works]
```bash
npm test
npm run typecheck
npm run build
# Manual verification: open http://localhost:3000 and [do X]
```

## 14. Open Questions
- [Anything unresolved — ideally empty by approval time]
```

## Task Sizing Guide

Each user story = one Ralph task. Size them so:
- Completable in one focused session (< 30 min of agent work)
- Zero decisions required — if the agent has to choose between approaches, the story is underspecified
- Acceptance criteria are checkboxes the agent can literally verify

**Too big:** "Build the authentication system"
**Right size:** "Add JWT token generation endpoint that returns {access_token, refresh_token} with 15min/7day expiry"

## Writing for AI Agents

The PRD reader is a coding agent (Codex or Claude Code). Write accordingly:
- Be explicit and unambiguous — agents take instructions literally
- Include exact file paths when known
- Show code for small changes (< 20 lines), function signatures for larger ones
- State constraints explicitly — agents respect stated boundaries
- Number everything (US-001, FR-1) for easy reference
- Acceptance criteria = the agent's definition of done
