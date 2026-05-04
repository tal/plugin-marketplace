# plan-refiner

Turn rough ideas, vague specs, and napkin-sketch plans into implementable documents through structured strategic interviewing. The plugin runs an in-depth Q&A loop using `AskUserQuestion`, asks only non-obvious questions about technical implementation, UI/UX, tradeoffs, concerns, and edge cases, and synthesizes the answers into a versioned, comprehensive plan or spec. It is built for the moment between "I have an idea" and "I'm ready to write code" — when the missing pieces are decisions, not keystrokes.

## Install

Claude Code (from inside the session):

```
/plugin install plan-refiner@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin install plan-refiner@tal-marketplace
```

Codex:

```
codex plugin install plan-refiner@tal-marketplace
```

## Commands

| Command | What it does | When to use |
|---|---|---|
| `/plan-refiner:create` | Builds a brand new implementation plan from a file, a rough description, or no input at all. Spawns an Explore subagent to read the relevant codebase first, then conducts a deep multi-round interview, then synthesizes a `plans/...md` file with overview, goals, technical approach, data model, edge cases, tradeoffs, and testing strategy. Optionally runs a follow-up gap analysis. | You're starting fresh and need a plan written from scratch. Pass `@SPEC.md`, a free-text description, or no argument. |
| `/plan-refiner:refine` | Reads an existing spec/plan, identifies clear vs. ambiguous areas, conducts a strategic interview, and writes a versioned refined spec (`SPEC.md` -> `SPEC.v1.md` -> `SPEC.v2.md`). Asks whether to include a "Refinement Summary" section at the top. | You already have a spec and want it sharpened. Iterate by re-running on the latest version. |
| `/plan-refiner:phase` | Breaks a spec into high-level, independently testable phases. Output is bullet-point only — goal, deliverables, "testable by", depends-on, unblocks — plus a required ASCII dependency diagram. No implementation details. Writes to `SPEC.phased.md`. | After refining, when you need a roadmap and ordering before fleshing out work. |
| `/plan-refiner:next-phase` | Finds the next unfilled phase in a `*.phased.md` file, spawns an Explore subagent to read the original spec and inspect what previous phases actually built (including recent git history for deviations), conducts a phase-specific implementation interview, then fills in `### Implementation Details` with file paths, type definitions, and a testing checklist. Marks the phase `**Status:** detailed`. | One phase at a time, right before you implement it. Re-run for each subsequent phase. |
| `/plan-refiner:act-on` | Reads a plan in `plans/`, presents actionable items grouped by priority, lets you multi-select, executes selected items in parallel via background subagents, appends a "Completed Items" section, and renames the file to `.partial.md` or `.completed.md` based on coverage. | When a plan is detailed enough to execute and you want the plugin to drive the work. |

All commands hand off to the `plan-refinement` skill for question patterns, completeness checks, and tradeoff frameworks.

## Skills

| Skill | Triggers on | What it does |
|---|---|---|
| `plan-refinement` | "refine this spec", "improve my plan", "ask me questions about this", "clarify requirements" — or any time a strategic interview is appropriate. | Provides the question-asking playbook the commands and the agent rely on: how to distinguish obvious from non-obvious questions, how to batch 1-4 related questions per round using `AskUserQuestion`, dimension coverage (technical, UI/UX, tradeoffs, concerns, edge cases), interview pacing, version-management conventions for `*.vN.md` files, and synthesis structure for the output spec. Ships with reference docs (`question-patterns.md`, `refinement-checklist.md`, `tradeoff-frameworks.md`) and a worked before/after example. |

## Agents

| Agent | Triggers on | What it does |
|---|---|---|
| `plan-refiner` | User asks to refine, improve, or clarify a plan/spec/requirements doc through questioning; `/plan-refiner:refine` invokes it explicitly. | Plan Refinement Specialist that runs the full refinement loop end-to-end: loads the `plan-refinement` skill, analyzes input, decides whether the spec is already complete enough to skip the interview, conducts iterative `AskUserQuestion` rounds (capped around 15-20 total questions), manages versioned filenames, optionally adds a Refinement Summary, and writes the synthesized spec. Tools: Read, Write, Glob, AskUserQuestion, Skill. Color: blue. |

## How it fits together

A typical flow walks through the commands in order, but each step is independently useful:

1. **Start with `/plan-refiner:create`** when the input is a rough idea, a sentence, or nothing yet. The command explores the codebase first so the questions are codebase-aware, then interviews until the plan is implementable, and writes to `plans/...md`. If you already have a draft spec, skip ahead.
2. **Use `/plan-refiner:refine`** to sharpen an existing spec. Each invocation produces the next `.vN.md` so version history is preserved. Re-run as many times as the spec needs.
3. **Use `/plan-refiner:phase`** once the spec is solid. The output is a high-level map — bullet points and an ASCII dependency diagram — that decides ordering and what's parallel vs. sequential. Every spec item lands in a phase or is explicitly deferred.
4. **Use `/plan-refiner:next-phase`** right before you implement each phase. It re-reads the spec, inspects what was actually built in earlier phases (commits and source), interviews about implementation specifics, and fills in concrete file paths, type definitions, and test cases for that one phase. Run it again for the next phase.
5. **Use `/plan-refiner:act-on`** to execute a finished plan. It runs items in parallel where it can and updates the file with a Completed Items section, renaming to `.partial.md` or `.completed.md` so you can see what's left.

You can also enter the flow at any point — refine a hand-written spec, or skip phasing on a small change and go straight from `/refine` to implementation.

## Files of interest

- `agents/plan-refiner.md` — agent system prompt and behavior contract.
- `skills/plan-refinement/SKILL.md` — main skill instructions.
- `skills/plan-refinement/references/question-patterns.md` — examples of effective questions by category.
- `skills/plan-refinement/references/refinement-checklist.md` — completeness checklist for specs.
- `skills/plan-refinement/references/tradeoff-frameworks.md` — frameworks for analyzing technical tradeoffs.
- `skills/plan-refinement/examples/before-after-feature.md` — worked refinement example.
- `commands/create.md`, `commands/refine.md`, `commands/phase.md`, `commands/next-phase.md`, `commands/act-on.md` — slash command definitions.
- `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` — manifests for both clients.
