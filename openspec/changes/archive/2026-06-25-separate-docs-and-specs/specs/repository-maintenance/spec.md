## ADDED Requirements

### Requirement: Repository entry points

The repository SHALL keep clear entry points for users, maintainers, automation, and OpenSpec planning.

#### Scenario: Maintainer or user enters the repository

- **WHEN** they inspect the repository
- **THEN** README is the user entry point, setup scripts are bootstrap entry points, `scripts/README.md` is the support-script entry point, GitHub Actions contains automation, and OpenSpec contains development requirements

### Requirement: Support script responsibilities

Support scripts SHALL be documented as helpers separate from the core bootstrap.

#### Scenario: Maintainer inspects `scripts/`

- **WHEN** they review support scripts
- **THEN** Docker/OCI image download, disk inspection, tree display, and Docling remote chunk validation are identifiable as helper responsibilities

### Requirement: Agent skill responsibilities

Agent skills under `.agents/skills/` SHALL be treated as task-specific automation packages, not product bootstrap runtime.

#### Scenario: Maintainer changes an agent skill

- **WHEN** a skill package changes
- **THEN** its `SKILL.md`, scripts, glossary, and agent config remain internally consistent
- **AND** product bootstrap behavior is not assumed to call the skill directly

### Requirement: Archives are historical

Files under `archives/` SHALL be treated as historical setup versions.

#### Scenario: Current setup behavior changes

- **WHEN** a maintainer updates current setup behavior
- **THEN** they update root setup scripts and OpenSpec
- **AND** they do not modify old archive versions unless explicitly preserving or correcting history

### Requirement: Generated areas are ignored

Generated portable environments, caches, and script outputs SHALL remain outside the source contract.

#### Scenario: Generated files are produced

- **WHEN** setup or support scripts produce `pdev/`, `inputs/`, `.local/`, `.config/`, `.cache/`, `.tmp/`, `.home/`, Docker layout outputs, logs, or common Python/Node/editor artifacts
- **THEN** those files are ignored by repository source control rules
