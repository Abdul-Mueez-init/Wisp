# Wisp — Development Rules

These rules apply to every Claude session working on this project, regardless of which Claude account/chat is being used. Read this file, PRD.md, ERD.md, and architecture.md at the start of every session before writing any code.

## Rule 1 — Strict adherence to the doc set, no invention
Follow PRD.md, ERD.md, architecture.md, and (once available) design.md exactly as written. Do not invent:
- New database tables/columns not in ERD.md
- New folder structures or state management patterns not in architecture.md
- New design choices (colors, spacing, components) not in design.md
- New features or scope not in PRD.md

If something is genuinely missing or ambiguous, stop and say so explicitly — propose the addition to the relevant doc first, get it confirmed, then update that doc before writing code against it. Never silently improvise and continue.

## Rule 2 — Zero tolerance for negligence and inconsistency
- Do not write code that contradicts an existing file's pattern because it's "close enough" or faster to write.
- Do not skip error handling, loading states, or null-safety checks to save time.
- Do not leave TODOs in place of working logic unless explicitly agreed as a deferred item in plan.md.
- If asked to build something and the existing code doesn't support it cleanly, say so — don't force a hacky workaround silently.
- Every piece of code produced should be something you'd stand behind as production-quality, not a rough draft.

## Rule 3 — Session batching
Work in batches of roughly 5-6 code files per message/response. This keeps each chunk reviewable and keeps handoffs between different Claude sessions (when session limits are hit) clean and closeable — a batch should represent a complete, working unit, not a half-finished feature.

## Rule 4 — Context handoff between sessions
At the start of any new Claude session (new chat or different Claude account), the following must be provided before continuing work:
1. PRD.md, ERD.md, architecture.md, rules.md, plan.md (this doc set)
2. context.md (current progress — see Rule 5)
3. The actual current content of any files being continued/edited (not a description of them)

## Rule 5 — context.md must be updated every session
Before ending a session (or when session limits are close), update `context.md` with:
- What was built this session
- Current phase / next phase from plan.md
- Any deviations from the doc set that were agreed upon (and reflected back into the relevant doc)
- Any open issues/bugs not yet resolved

A new Claude session should never have to guess "what's already done" — context.md is the single source of truth for progress.

## Rule 6 — One feature closed out per session block where possible
Avoid leaving a feature half-implemented across a session boundary. Finish the current unit of work (e.g. "typing indicator" fully working) before switching sessions, rather than stopping mid-implementation. If a session limit is hit mid-feature, context.md must clearly document exactly what's done and what's left for that specific feature.

## Rule 7 — Schema and architecture changes require doc updates first
If a database change or architectural change becomes necessary mid-build, update ERD.md/architecture.md first, in their own step, then implement. Never let the codebase and the docs drift out of sync — the docs are the source of truth, not the code.

## Rule 8 — AI feature calls go through the shared config only
Per architecture.md, all Gemini/Groq calls route through `config/ai_config.dart`. No feature code should instantiate its own AI client directly.
