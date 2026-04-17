---
name: Plan Refinement
description: This skill should be used when the user asks to "refine this spec", "improve my plan", "ask me questions about this", "clarify requirements", or when conducting strategic interviews to improve plans, specs, or requirements documents through in-depth questioning about technical implementation, UI/UX decisions, tradeoffs, concerns, and edge cases.
version: 0.1.0
---

# Plan Refinement Skill

## Overview

This skill provides guidance for refining plans, specifications, and requirements through strategic interviewing. The goal is to transform rough ideas into comprehensive, well-thought-out specifications by asking non-obvious questions that uncover hidden complexity, clarify ambiguities, and identify critical decisions that need to be made.

## Core Principles

### 1. Distinguish Obvious from Non-Obvious Questions

**Avoid asking obvious questions** that can be inferred from context or are clearly stated in the spec.

**Obvious questions (avoid):**
- "What programming language should we use?" (when spec mentions "Python API")
- "Should we add a submit button?" (when spec describes a form)
- "Will this need a database?" (when spec discusses "user profiles")

**Non-obvious questions (ask):**
- "What should happen if the API rate limit is exceeded during bulk operations?"
- "Should form validation happen on blur, on submit, or both? What's the UX for showing errors?"
- "For user profiles, what's the strategy for handling profile picture storage—local filesystem, S3, CDN?"

### 2. Question Categories

Structure questions around these areas, but present them naturally without explicit categorization:

**Technical Implementation:**
- Architecture and design patterns
- Data structures and storage
- Performance and scalability considerations
- Error handling and edge cases
- Security and authentication
- API design and integration points

**UI/UX Decisions:**
- User flow and interaction patterns
- Error states and feedback
- Loading states and optimistic updates
- Accessibility considerations
- Responsive design breakpoints
- Animation and transitions

**Tradeoffs:**
- Performance vs. complexity
- Flexibility vs. simplicity
- Time-to-market vs. technical debt
- Cost vs. scalability
- User experience vs. implementation effort

**Concerns and Constraints:**
- Budget and timeline constraints
- Technical limitations
- Team expertise and resources
- Maintenance and operations
- Backwards compatibility
- Migration strategies

**Edge Cases:**
- Boundary conditions
- Error scenarios
- Race conditions
- Network failures
- Invalid input handling
- State synchronization

### 3. Iterative Refinement Process

**Pre-Interview Assessment:**
1. Read the current spec thoroughly
2. Identify what's clearly defined vs. ambiguous
3. Determine whether the spec is already sufficiently clear
4. If the spec is clear, ask the user whether to proceed before starting the interview

**Interview Flow:**
1. Ask questions iteratively, not all at once
2. Each round of answers informs the next round of questions
3. Use the AskUserQuestion tool with 1-4 related questions per round
4. Continue until no more non-obvious questions remain or the user says "stop"
5. Build understanding progressively through conversation

**Question Crafting:**
- Keep questions focused and specific
- Provide context in question text
- Offer concrete options when appropriate
- Ask about decisions, not just facts
- Frame questions to reveal tradeoffs

**Post-Interview:**
1. Synthesize all answers into a coherent refined spec
2. Organize information logically
3. Include decisions made and rationale
4. Ask the user about including a change summary
5. Ask whether to remember the summary preference for future sessions

## Using the AskUserQuestion Tool

### Question Structure

```typescript
{
  question: "Clear, specific question ending with question mark?",
  header: "Short label (max 12 chars)",
  options: [
    {
      label: "Concise choice (1-5 words)",
      description: "What this means and implications"
    },
    // 2-4 options total
  ],
  multiSelect: false  // true only if choices aren't mutually exclusive
}
```

### Batching Related Questions

Ask 1-4 related questions per round using single AskUserQuestion call:

**Good batching (related questions):**
- Error handling strategy, retry logic, fallback behavior
- Authentication method, session management, token refresh
- Data validation approach, error messaging, user feedback

**Poor batching (unrelated questions):**
- Database choice, button color, deployment strategy
- (These should be separate rounds)

### Follow-Up Questions

After receiving answers:
1. Analyze responses
2. Identify new questions raised by answers
3. Ask next round of questions
4. Repeat until comprehensive

## Version Management

### File Naming Convention

**First refinement:**
- Input: `SPEC.md`
- Output: `SPEC.v1.md`

**Subsequent refinements:**
- Input: `SPEC.v1.md`
- Output: `SPEC.v2.md`

**Version detection pattern:**
- Check for existing `.v{N}.md` files
- Find highest version number
- Increment to next version

**Collision handling:**
- If output version exists, ask user:
  - Overwrite existing version
  - Skip to next version number
  - Cancel operation

### Implementation Steps

1. Parse input filename
2. Extract base name (strip `.v{N}.md` if present)
3. Search directory for `{basename}.v*.md` files
4. Find max version number (0 if none exist)
5. Output to `{basename}.v{next}.md`
6. Handle collisions by prompting user

## Workflow for Refining Specs

### Step 1: Read and Analyze

Read the input spec file completely. During analysis:

**Identify clear elements:**
- Explicit requirements
- Concrete technical decisions
- Defined workflows
- Specified constraints

**Identify ambiguous elements:**
- Vague descriptions ("user-friendly", "fast", "scalable")
- Missing technical details
- Undefined edge cases
- Unstated assumptions
- Unresolved tradeoffs

**Assess completeness:**
- Is the spec sufficiently clear to implement?
- Are there obvious gaps or questions?
- Would different developers interpret this differently?

### Step 2: Pre-Interview Check

If the spec is already quite clear and comprehensive:
1. Acknowledge that the spec is well-defined
2. Ask the user whether to proceed with refinement anyway
3. If the user declines, exit gracefully
4. If the user confirms, continue with the interview

If the spec has clear gaps or ambiguities:
1. Proceed directly to interview
2. No need to ask for confirmation

### Step 3: Conduct Interview

**Round 1 - High-level architecture:**
- Major technical decisions
- Overall approach and patterns
- Core data structures
- Primary user flows

**Round 2 - Implementation details:**
- Specific APIs and integrations
- Data validation and processing
- Error handling strategy
- State management

**Round 3 - Edge cases and concerns:**
- Failure scenarios
- Performance considerations
- Security implications
- Operational concerns

**Round 4+ - Deep dive:**
- Follow-up on previous answers
- Uncover hidden complexity
- Clarify remaining ambiguities
- Validate understanding

Continue until:
- No more non-obvious questions remain
- The user indicates "stop" or "done"
- The spec is comprehensive enough to implement

### Step 4: Synthesize and Write

**Organize the refined spec:**

1. **Overview** - Clear problem statement and goals
2. **Requirements** - Functional and non-functional requirements
3. **Technical Approach** - Architecture, patterns, technologies
4. **Implementation Details** - APIs, data structures, algorithms
5. **UI/UX Specifications** - User flows, interactions, states
6. **Edge Cases** - Error handling, boundary conditions
7. **Tradeoffs and Decisions** - Why certain choices were made
8. **Open Questions** - Anything still unresolved

**Writing style:**
- Clear and specific
- Includes rationale for decisions
- Documents tradeoffs considered
- Provides enough detail for implementation
- Organized logically

### Step 5: Finalize Output

**Ask the user about the change summary:**

Use AskUserQuestion to ask:
1. "Would you like to include a summary of changes and clarifications at the top of the refined spec?"
   - Options: Yes / No
2. "Should this preference be remembered for future refinement sessions?"
   - Options: Yes (save to memory) / No (just this time)

If the user wants a summary, include the section at the top:
```markdown
## Refinement Summary

**Changes from v{N-1}:**
- Clarified [aspect]
- Added details about [topic]
- Resolved ambiguity in [area]
- Specified approach for [concern]

**Key Decisions:**
- [Decision 1]: [Rationale]
- [Decision 2]: [Rationale]
```

**Write the refined spec:**
1. Write to versioned output file
2. Preserve all original content
3. Enhance with clarifications
4. Add new sections as needed
5. Include summary if requested

## Tips and Best Practices

### Effective Questioning

**Ask "what if" questions:**
- "What if the external API is down?"
- "What if two users edit simultaneously?"
- "What if the dataset is 100x larger?"

**Probe tradeoffs:**
- "Would you prefer simpler code or better performance here?"
- "Is it more important to ship quickly or have zero bugs?"
- "Should we optimize for developer experience or runtime efficiency?"

**Clarify intentions:**
- "When you say 'fast', what's the target latency?"
- "What does 'user-friendly' mean in this context?"
- "Can you define what 'scalable' means for this feature?"

### Interview Pacing

**Start broad, then narrow:**
- Begin with high-level architecture
- Progress to implementation details
- Finish with edge cases and polish

**Build on previous answers:**
- Use earlier responses to inform later questions
- Create logical flow through conversation
- Avoid asking redundant questions

**Know when to stop:**
- Watch for diminishing returns
- Respect the user's time
- Aim for "good enough" rather than perfect

### Quality Indicators

**A well-refined spec should:**
- Be implementable by someone unfamiliar with the project
- Have clear acceptance criteria
- Document key decisions and rationale
- Cover major edge cases
- Define error handling strategy
- Specify non-functional requirements

**Warning signs of incomplete refinement:**
- Vague requirements ("should be intuitive")
- Missing error handling
- Undefined edge cases
- Unresolved technical decisions
- Ambiguous acceptance criteria

## Additional Resources

### Reference Files

For detailed patterns and techniques:
- **`references/question-patterns.md`** - Examples of effective questions by category
- **`references/refinement-checklist.md`** - Comprehensive checklist for spec completeness
- **`references/tradeoff-frameworks.md`** - Frameworks for analyzing technical tradeoffs

### Example Files

Working examples of refined specs:
- **`examples/before-after-feature.md`** - Feature spec refinement
- **`examples/before-after-api.md`** - API spec refinement
- **`examples/before-after-architecture.md`** - Architecture spec refinement

## Common Pitfalls to Avoid

**Don't ask obvious questions:**
- Questions answered in the original spec
- Questions with only one reasonable answer
- Questions that are just confirming the obvious

**Don't overwhelm with too many questions:**
- Batch related questions (1-4 per round)
- Let answers inform next questions
- Take breaks in long interviews

**Don't ignore user signals:**
- If the user says "stop", stop
- If answers are getting terse, wrap up
- If the user seems confused, clarify the question

**Don't forget the goal:**
- The goal is an implementable spec, not a perfect spec
- Practical over theoretical
- Decisions over options
- Clarity over comprehensiveness

## Success Metrics

A successful refinement results in:
- The user feels heard and understood
- The spec is significantly clearer than the original
- Major ambiguities resolved
- Key decisions documented
- Implementation path clear
- Edge cases considered
- Tradeoffs acknowledged

The refined spec should answer: "If handed to a developer, could they implement it without constantly coming back with questions?"
