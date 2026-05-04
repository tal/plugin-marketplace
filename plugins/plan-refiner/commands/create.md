---
name: create
description: Create an implementation plan through deep, in-depth interviewing
argument-hint: [file-path-or-description]
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - Task
  - TodoWrite
  - TodoRead
---

# Plan Command

Create a comprehensive implementation plan by deeply exploring the codebase, then conducting an exhaustive interview using AskUserQuestion. Cover literally everything: technical implementation, UI & UX, concerns, tradeoffs, edge cases, architecture, data models, error handling, and more. Questions must be non-obvious.

## Usage

```bash
/plan @SPEC.md              # Interview based on an existing file
/plan @rough-idea.md        # Interview based on a rough idea doc
/plan add dark mode support  # Interview based on a verbal description
/plan                        # Ask what to plan, then dive in
```

## Instructions for Claude

### Step 1: Load Knowledge

Load the plan-refinement skill for question patterns and frameworks:

```
Use Skill tool to load: plan-refinement
```

### Step 2: Gather Initial Context

**If a file path is provided** (starts with `@` or ends in `.md`/`.txt`):

- Read the file to understand the starting point

**If a text description is provided:**

- Use the description as the seed
- Ask 1-2 brief scoping questions if the description is very vague, then move on quickly

**If no argument is provided:**

- Ask the user what they want to plan — don't over-scaffold, just get the topic and go

### Step 3: Explore the Codebase

**This step is critical.** Before interviewing, use the Task tool to spawn an Explore subagent to deeply research the existing codebase related to the plan topic. Understanding the existing code makes interview questions dramatically better.

```
Task tool with subagent_type: "Explore"
Prompt: Research [topic] in this codebase. Find and read:
- Existing implementations related to [topic]
- Relevant types, interfaces, and data structures
- How the current system works end-to-end
- Any existing patterns or conventions that apply
Return full contents of key files and a summary.
```

Wait for the exploration results before starting the interview. Use what you learn to ask informed, codebase-aware questions instead of generic ones.

**Skip this step** only if the plan is for a brand new project with no existing codebase.

### Step 4: Conduct Deep Interview

This is the core of the command. Interview the user using AskUserQuestion about **literally anything** related to the plan. Be very in-depth.

**Critical rules:**

- Questions must be **non-obvious** — never ask something that's clearly stated or easily inferred
- Continue interviewing **continually** until the plan is truly complete
- Each round should have 1-4 related questions
- Let each round's answers inform the next round's questions
- Cover ALL dimensions, not just the ones the user mentioned
- **Honor custom answers** — users frequently choose "Other" and type nuanced answers that are richer than the provided options. Use those answers fully and let them shape subsequent questions.
- **Verify surprising answers** — if an answer seems to contradict an earlier one or doesn't match what you expected, ask a brief follow-up to confirm understanding before moving on

**Dimensions to explore (adapt to what's relevant):**

1. **Technical implementation** — Architecture, patterns, data structures, algorithms, APIs
2. **UI & UX** — User flows, interaction patterns, feedback, states, accessibility
3. **Concerns** — Security, performance, scalability, maintainability, cost
4. **Tradeoffs** — Where are the tensions? What are we optimizing for vs. sacrificing?
5. **Edge cases** — What happens when things go wrong? Boundary conditions?
6. **Data model** — What entities exist? How do they relate? What's mutable?
7. **Integration points** — What does this touch? What APIs, services, or systems are involved?
8. **Error handling** — How do we handle failures? Retry? Degrade? Notify?
9. **Migration/rollout** — How do we get from here to there? Feature flags? Phased rollout?
10. **Testing strategy** — What needs testing? How do we verify correctness?

**Interview pacing:**

- Start broad (what are we building, why, for whom)
- Go deep on each dimension that's relevant
- Circle back when earlier answers reveal new questions
- Don't stop after 3-4 rounds just because it feels like enough — keep going until you genuinely have no more non-obvious questions
- If the user gives a terse answer, probe deeper on that topic
- Typical thorough interview: 5-10+ rounds

**When to stop:**

- You have no more non-obvious questions AND the plan feels implementable
- The user says "stop", "done", "that's enough", or similar
- The user's answers indicate they want to wrap up (getting terse, saying "whatever you think")

### Step 5: Determine Output File

**If the input was a file:**

- Default output: same filename in a `plans/` directory (create if needed)
- Example: input `@SPEC.md` -> output `plans/SPEC.md`
- If `plans/SPEC.md` already exists, ask the user what to do

**If the input was a description:**

- Generate a descriptive filename based on the topic
- Format: `plans/YYYY-MM-DD_descriptive-name.md`
- Example: `plans/2026-02-20_dark-mode-support.md`

**Ask the user to confirm the output path** before writing:

```
Question: "Where should I write the plan?"
Header: "Output"
Options:
  - "{default path}" - Suggested based on input
  - "Custom path" - Let me specify
```

### Step 6: Write the Plan

Synthesize everything from the interview into a comprehensive implementation plan.

**Plan structure:**

```markdown
# [Plan Title]

## Overview

[1-2 paragraph summary of what we're building and why]

## Goals

- [Primary goal]
- [Secondary goals]

## Non-Goals

- [What this plan explicitly does NOT cover]

## Technical Approach

[Architecture, patterns, key technical decisions with rationale]

[Include diagrams as ASCII art where they clarify flow or architecture]

## Implementation Details

[Detailed breakdown of what needs to be built]

### [Component/Phase 1]

[Details, including specific files, APIs, data structures]

[Include TypeScript/code examples for key types, interfaces, and function signatures]

### [Component/Phase 2]

[Details...]

## Data Model

[If applicable - entities, relationships, schemas]

[Include type definitions as code blocks]

## Edge Cases & Error Handling

[How we handle failures, boundaries, unexpected states]

## Tradeoffs & Decisions

[Key decisions made during planning with rationale]

- **[Decision]**: [What we chose] because [why]

## Testing Strategy

[What needs testing, how we verify correctness]

## Open Questions

[Anything still unresolved - keep this section even if empty]
```

Adapt this structure to the plan — skip sections that don't apply, add sections that do. The structure serves the content, not the other way around.

**Writing style:**

- Specific and concrete — no vague terms
- Include rationale for every significant decision
- Actionable — a developer should be able to implement from this
- Organized logically by component/phase, not by interview order
- **Include code examples** — type definitions, function signatures, key logic snippets. These are essential for implementation clarity.
- **Include ASCII diagrams** for request flows, architecture, or data pipelines where they help

### Step 7: Gap Analysis (Optional)

After writing the plan, offer to run a gap analysis:

```
Question: "Want me to review the plan for gaps and ambiguities?"
Header: "Gap analysis"
Options:
  - "Yes" - Spawn a subagent to read the plan and ask about anything unclear or missing
  - "No" - Plan is done
```

If yes, spawn a general-purpose subagent via Task tool to:

1. Read the written plan thoroughly
2. Cross-reference against the codebase (existing types, APIs, conventions)
3. Identify non-obvious gaps, ambiguities, and unanswered questions
4. Use AskUserQuestion to ask about each gap found
5. Return a summary of all gaps and the user's answers

After the gap analysis, update the plan with the new information.

### Step 8: Confirm Completion

After writing (and optionally updating from gap analysis), tell the user:

```
Plan written to {path}.

Key decisions:
- [2-3 most important decisions from the interview]

Next steps: Use `/refine` to iterate on this plan, or `/act-on-plan` to execute it.
```

## Important Notes

- **Explore first, then interview** — Understanding the codebase before asking questions makes the difference between generic and insightful questions.
- **Depth over speed** — This command's value is in the thoroughness of the interview. Don't rush.
- **Non-obvious questions only** — If the answer is clearly stated or trivially inferred, don't ask.
- **Continue until complete** — Don't stop early. Keep interviewing until the plan is genuinely implementable.
- **Adapt to the domain** — A backend API plan needs different questions than a UI feature plan.
- **Synthesize, don't transcribe** — The output should be a coherent plan, not a Q&A transcript.
- **Code examples are essential** — Plans without concrete type definitions and function signatures are too vague to implement from.
- **Create plans/ directory** if it doesn't exist (use Write tool, it handles directory creation).
