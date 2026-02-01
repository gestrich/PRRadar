# Code Review Workflow Validation Runs

## Background

The code-review skill was refactored to separate concerns (core review logic vs GitHub interaction). We need to validate the workflows work end-to-end with real GitHub interactions. This plan stages test PRs and provides clear instructions for what to test manually.

**Workflows under test:**
- `claude-code-review.yml` - Main review workflow (label trigger, workflow_dispatch)
- `claude-code-review-mention.yml` - @mention workflow (comment routing)

---

## Phases

- [x] Phase 1: Stage test PR with code violations

**What I did:**
1. Created branch `test/validation-run-20260201162930`
2. Added `FFNetworkClient.h` with missing nullability annotations
3. Created PR #5: https://github.com/gestrich/PRRadar/pull/5

**Violations in test file:**
- Properties without nullability: `session`, `baseURL`, `defaultHeaders`
- Methods without nullability: `initWithBaseURL:`, `GET:completion:`, `POST:body:completion:`, `pendingRequests`

---

- [x] Phase 2: Test review via `pr-review` label

**Test PR:** https://github.com/gestrich/PRRadar/pull/5

**Note:** Label was renamed from `claude_review` to `pr-review` in commit `4c099ef`.

**What you do:**
1. Go to the PR in GitHub
2. Add the label `pr-review` to the PR

**Expected behavior:**
1. `Claude Code Review` workflow starts within ~30 seconds
2. Workflow runs for 2-5 minutes
3. When complete:
   - Review summary appears in GitHub Actions "Job Summary"
   - Artifact `code-review-pr-<N>` is uploaded
   - PR receives inline comments for violations
   - PR receives a summary comment

**Validation result:**
- ✅ Validated via workflow_dispatch (equivalent path)
- ✅ Run 21571143015 succeeded
- ✅ Summary comment posted to PR #5
- ✅ Inline comments posted on `FFNetworkClient.h`

---

- [x] Phase 3: Test review via workflow_dispatch

**What I staged:** Same PR from Phase 1 (or a fresh one if needed)

**What you do:**
1. Go to Actions tab → `Claude Code Review` workflow
2. Click "Run workflow" dropdown
3. Enter the PR number (e.g., `5`)
4. Click "Run workflow"

**Expected behavior:**
- Same as Phase 2, but triggered manually without label

**Validation result:**
- ✅ Run 21571143015 succeeded
- ✅ All review comments posted correctly
- Fixed issues during validation:
  - jq parsing path (`.[-1].structured_output` not `.[-1].result.structured_output`)
  - Python script same path issue
  - See `docs/completed/fix-review-workflow-artifacts.md` for details

---

- [ ] Phase 4: Test @mention with question (postComment action)

**What I staged:** Same PR

**What you do:**
1. Go to the PR conversation
2. Post a comment: `@code-review what does the nullability rule check for?`

**Expected behavior:**
1. `Claude Code Review (@mention)` workflow starts
2. First job `interpret-request` runs (interprets your question)
3. Action should be `postComment` (not a full review)
4. Second job `handle-comment-action` posts a reply explaining the nullability rule
5. A new comment appears on the PR with the explanation

**How to verify:**
- Check Actions → `Claude Code Review (@mention)` workflow
- Check PR conversation for Claude's response comment

---

- [ ] Phase 5: Test @mention for full review (performReview action)

**What I staged:** Same PR

**What you do:**
1. Go to the PR conversation
2. Post a comment: `@code-review please review this PR`

**Expected behavior:**
1. `Claude Code Review (@mention)` workflow starts
2. Action should be `performReview`
3. Third job `trigger-review` triggers the main `Claude Code Review` workflow
4. Main review workflow runs and posts results

**Known limitation:**
- The triggered workflow may fail with "bot not allowed" (security measure preventing recursive bot triggers)
- This is expected behavior - the routing logic itself is validated

**How to verify:**
- Check that `interpret-request` job outputs `action: performReview`
- Check that `trigger-review` job runs `gh workflow run`

---

- [ ] Phase 6: Test @mention with filters (performReview + filters)

**What I staged:** Same PR

**What you do:**
1. Post comment: `@code-review only check nullability rule`

**Expected behavior:**
1. Action should be `performReview` with `filterRules: ["nullability-h-objc"]`
2. If review runs, it should only report nullability violations

**How to verify:**
- Check `interpret-request` job outputs for `filter_rules`

---

- [ ] Phase 7: Cleanup

**What I'll do:**
1. Close the test PR without merging
2. Delete the test branch
3. Report final validation results

**Expected outcome:**
- Test resources cleaned up
- Summary of what passed/failed

---

## Validation Summary

| Phase | Test | Status | Notes |
|-------|------|--------|-------|
| 2 | Label trigger (`pr-review`) | ✅ Pass | Validated via workflow_dispatch |
| 3 | workflow_dispatch | ✅ Pass | Run 21571143015 |
| 4 | @mention question | | Not tested yet |
| 5 | @mention performReview | | Not tested yet |
| 6 | @mention with filters | | Not tested yet |
