# Agent Instructions

## Project Context

- Read `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, and `.planning/REQUIREMENTS.md` before planning substantial work.
- Current focus is Phase 1: Playback Critical Path and Responsiveness.
- Core value: make music start quickly and keep playback stable. Playback startup takes priority over lyrics, recommendations, MV, artwork, cache work, and UI polish.

## CodeGraph

In this repository, `.codegraph/` is present. Use CodeGraph before grep/find or raw file reads when locating or understanding source code:

- `codegraph_explore` for architecture, flows, bugs, and named areas.
- `codegraph_node` for a specific file or symbol.
- `codegraph_callers` before changing shared functions or callbacks.

If CodeGraph reports stale files after edits, read those specific files directly.

## GSD Workflow

- Planning docs live in `.planning/`.
- Phase work should start with `$gsd-discuss-phase 1` or `$gsd-plan-phase 1`.
- Preserve requirements traceability when roadmap or scope changes.
- Keep v1 focused on stabilization: playback first sound, search responsiveness, recommendation stability, image memory, player gestures, and regression coverage.
- Do not pull v2 API/auth/cache rewrites into Phase 1 unless a narrow change is required for v1 stability.

## Git Safety

- Do not revert uncommitted user or prior-agent source changes unless explicitly asked.
- Stage only files relevant to the current task.
- Keep planning-doc commits separate from source-code commits when possible.
