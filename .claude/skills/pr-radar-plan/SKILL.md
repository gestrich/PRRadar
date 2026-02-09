---
name: pr-radar-plan
description: Create a phased planning document for a PRRadar feature or change
---

Create a planning document in `docs/proposed/<doc-name>.md` where the doc name reflects the plan appropriately (e.g., `add-user-authentication.md`, `refactor-api-layer.md`).

## Step 1: Read Architecture Guides

Before writing the plan, fetch and read both architecture skills from `https://github.com/gestrich/swift-app-architecture` (under `plugin/skills/`):

1. **`swift-architecture`** — The 4-layer architecture guide (SDKs → Services → Features → Apps), layer responsibilities, dependency rules, and code placement guidance.
2. **`swift-swiftui`** — The SwiftUI Model-View architecture patterns, enum-based state, observable model conventions, and view composition rules.

Both guides are frequently relevant. Use the principles from these docs to inform every phase of the plan — reference specific architecture or SwiftUI conventions when a phase involves decisions about where code should live, how layers interact, how views should be structured, or how state should be managed.

## Step 2: Write the Planning Document

### Planning Document Format

The planning document should follow this structure:

```markdown
## Background

[Explain why we are making these changes. Include any general information that applies across all phases. Reference user requirements and context from the conversation.]

## Phases

## - [ ] Phase 1: [Short descriptive name]

[Detailed description of Phase 1, including:
- Specific tasks to complete
- Files to modify
- Important details from user's instructions
- Any technical considerations
- Expected outcomes
- Reference relevant architecture or SwiftUI principles that apply to this phase]

## - [ ] Phase 2: [Short descriptive name]

[Detailed description of Phase 2...]

## - [ ] Phase N-1: Architecture Validation

[This phase is ALWAYS included as the second-to-last phase, immediately before the Validation/testing phase.]

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**For Python changes** (`prradar/`, `tests/`):
- Fetch and read each skill from `https://github.com/gestrich/python-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Determine which languages were touched (Python, Swift, or both)
4. For each relevant language, fetch and read ALL skills from the corresponding GitHub repo
5. Evaluate the changes against each skill's conventions
6. Fix any violations found

## - [ ] Phase N: Validation

[Describe validation approach:
- Which tests to run (unit, integration, e2e)
- Manual checks if needed
- Success criteria
- Prefer automated testing over manual user verification]
```

The `## - [ ]` format makes each phase a markdown section header, improving readability and navigation in markdown viewers while preserving the checkbox for status tracking.

## Important Guidelines

1. **Limit phases to 10 or less** - For simple plans, use 5 or fewer phases
2. **Include user details** - Capture specific requirements and preferences from the conversation
3. **Always include Architecture Validation phase** - As the second-to-last phase, before testing
4. **Always end with Validation phase** - Choose appropriate test level based on complexity
5. **No implementation** - Only write the planning document, don't start coding
6. **Descriptive naming** - Doc filename should clearly indicate what's being planned
7. **Be specific** - Each phase should have enough detail to execute independently

## Workflow

1. **Read architecture guides** — Fetch and read both `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
2. Gather requirements (ask clarifying questions if needed)
3. Determine appropriate doc name based on the task
4. Create the planning document in `docs/proposed/<doc-name>.md`, referencing architecture and SwiftUI principles in each phase as relevant
5. Present the plan to the user for review
6. Wait for approval before any implementation
