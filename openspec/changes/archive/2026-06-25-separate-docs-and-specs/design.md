## Context

The user's boundary is clear: OpenSpec should contain development requirements, while `docs/` should contain manuals and operational information needed to use the project. The current tree violates this because `docs/SPEC.md`, `docs/CODING_RULES.md`, and `docs/REPOSITORY_GUIDE.md` contain development specifications or maintainer guidance, and OpenSpec has only one broad spec.

## Goals / Non-Goals

**Goals:**

- Reflect every substantive requirement from `docs/SPEC.md` in OpenSpec.
- Split OpenSpec into capability-sized specs instead of one catch-all document.
- Move development-only documentation out of `docs/`.
- Keep user-facing setup and troubleshooting information discoverable from README.
- Preserve commit conventions in OpenSpec and follow them for this change.

**Non-Goals:**

- Change PowerShell implementation behavior.
- Rewrite the user-facing setup instructions in README.
- Remove operational troubleshooting docs that users need when running the scripts.

## Decisions

### Decision 1: OpenSpec is the development source of truth

Development requirements, coding rules, repository maintenance rules, and implementation contracts live in `openspec/specs/`. `docs/` remains for user manuals, troubleshooting, and script usage documentation.

Alternative considered: keep `docs/SPEC.md` as a rendered copy of OpenSpec. Rejected because the user explicitly wants to avoid duplicate OpenSpec content in docs.

### Decision 2: Split specs by stable capabilities

The `docs/SPEC.md` sections map naturally to separate capabilities: environment boundary, layout, bootstrap toolchain, package management, VS Code, Cygwin, launchers, logging/validation, and automation. This keeps future changes targeted and reviewable.

Alternative considered: create one large `portable-dev-environment` spec. Rejected because it would recreate the current "one document only" problem.

### Decision 3: Remove broad repository guide

The repository guide mixed source map, maintainer workflow, coding rules, and setup requirements. Those become OpenSpec requirements instead of a maintainer doc under `docs/`.

## Risks / Trade-offs

- Users may look for `docs/SPEC.md` from habit -> README will point to `openspec/specs/` for development specs.
- OpenSpec specs become more numerous -> capability names are narrow and stable to keep navigation predictable.
- Deleted docs may be referenced elsewhere -> verify local Markdown links and grep old paths before commit.

## Migration Plan

1. Add split delta specs under the new OpenSpec change.
2. Delete development-only docs from `docs/`.
3. Update README links and OpenSpec project context.
4. Archive the change to sync main specs.
5. Remove the obsolete `repository-documentation` main spec if archive leaves an empty shell.
