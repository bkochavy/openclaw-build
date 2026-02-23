#!/bin/bash
# Cross-model review pass — run after a Ralph loop completes
# One model builds, a different model reviews
# Usage: ./review-pass.sh /path/to/repo [num_commits]

set -e

REPO="$1"
NUM_COMMITS="${2:-10}"

if [ -z "$REPO" ]; then
  echo "Usage: $0 /path/to/repo [num_commits_to_review]"
  exit 1
fi

cd "$REPO"

echo "=== Cross-Model Review Pass ==="
echo "Repo: $REPO"
echo "Reviewing last $NUM_COMMITS commits"
echo ""

REVIEW_PROMPT="Review the last $NUM_COMMITS commits in this repository. 

Check for:
1. Bugs or logic errors
2. Missing error handling
3. Inconsistent patterns across files
4. Security issues (hardcoded secrets, injection, unsafe input)
5. Missing or broken tests
6. Dead code or unused imports
7. Performance issues (N+1 queries, unnecessary re-renders)

For each issue found:
- Describe the problem with file path and line
- Fix it directly if it's a clear bug
- Add a TODO comment if it needs human judgment

Write a summary to REVIEW.md with:
- Issues found and fixed
- Issues flagged for human review
- Overall code quality assessment

Then run all verification commands from the PRD (if present)."

echo "Launching Codex review (high effort)..."
ralphy --codex --verbose -- -c model_reasoning_effort="high" "$REVIEW_PROMPT"

echo ""
echo "Review complete. Check REVIEW.md for findings."
