# PRD: Rate Limiting for `POST /v1/messages`
**Created:** 2026-02-22T14:00:00Z
**Status:** APPROVED
**Master Plan:** `projects/messaging-api/master-plan.md`
## 1. Overview: Add per-API-key and per-IP limits to prevent abuse and protect latency.
## 2. Goals: Keep p95 latency < 250ms under burst traffic; return clear throttling feedback.
## 3. User Stories
### US-001: Protect Message Endpoint
**Description:** As an API operator, I want request throttling so bad actors cannot overload `POST /v1/messages`.
**Acceptance Criteria:** - [ ] 61st request in 60s returns 429 for keyed clients - [ ] `retry_after` is included and accurate - [ ] existing success path unchanged.
**Priority:** P0
## 4. Functional Requirements: FR-1 enforce 60 req/min per API key; FR-2 enforce 10 req/min per IP unauthenticated; FR-3 emit metric `rate_limit.blocked`.
## 5. Schema (if applicable): `api_rate_limits(key_hash TEXT PRIMARY KEY, window_start TIMESTAMPTZ, request_count INT NOT NULL)`.
## 6. API Shape (if applicable): `POST /v1/messages` may return `429 {"error":"rate_limited","retry_after":12}`.
## 7. System Prompts (if applicable): N/A.
## 8. Business Logic (if applicable): Authenticated key limits take precedence; fallback to IP limit when no key is present.
## 9. Constraints: Must use existing Redis cluster; no new managed services.
## 10. Non-Goals: No tier-specific limits, no admin bypass, no UI for limit tuning.
## 11. Technical Considerations: Use atomic Redis Lua script for increment + TTL to avoid race conditions.
## 12. Success Metrics: <1% false-positive throttles in staging load test; zero 5xx from limiter path.
## 13. Verification Commands: `npm test && npm run typecheck && npm run loadtest:ratelimit`.
## 14. Open Questions: Should trusted internal service accounts get a separate quota in v2?
