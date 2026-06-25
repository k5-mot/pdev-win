# contribution-guidelines Specification

## Purpose
Define repository contribution conventions for text files, PowerShell, shell, Markdown, portable state, and Japanese gitmoji Conventional Commit messages.
## Requirements
### Requirement: Text file conventions

Repository text files SHALL be UTF-8 without BOM and preserve existing newline style; new files SHOULD use LF unless the surrounding file pattern requires otherwise.

#### Scenario: Contributor edits text

- **WHEN** a contributor edits PowerShell, shell, or Markdown files
- **THEN** encoding and newline conventions remain consistent with the repository

### Requirement: Path resolution conventions

Repository scripts SHALL avoid fixed user profile paths and prefer OS-known folder APIs for known locations.

#### Scenario: Script needs Desktop

- **WHEN** a script resolves Desktop
- **THEN** it uses `[Environment]::GetFolderPath()` instead of a hard-coded user profile path

### Requirement: PowerShell conventions

PowerShell code SHALL use strict error behavior and comment-based help for functions.

#### Scenario: Contributor adds a PowerShell function

- **WHEN** a new function is added
- **THEN** it includes comment-based help with at least `.SYNOPSIS`
- **AND** parameter documentation is added when useful
- **AND** complex logic has concise Japanese comments
- **AND** external command exit codes are checked

### Requirement: Portable state convention

Scripts SHALL keep temporary files, logs, and caches under the portable root when they relate to the portable environment.

#### Scenario: Script introduces mutable state

- **WHEN** a script needs temp, log, or cache storage
- **THEN** it does not depend on AppData or system-wide settings for normal portable behavior

### Requirement: Shell conventions

Shell scripts SHALL use strict mode and safe file handling.

#### Scenario: Contributor adds shell script behavior

- **WHEN** a shell script is added or changed
- **THEN** it uses `set -euo pipefail`, writes failure messages to stderr, checks input/output paths, and guards destructive operations with explicit conditions

### Requirement: Markdown conventions

Markdown SHALL keep README concise and place content according to audience.

#### Scenario: Contributor adds Markdown content

- **WHEN** content is user-facing
- **THEN** it can live in README, `docs/`, or script manuals
- **AND** when content is a development requirement, implementation contract, contribution rule, or maintainer workflow, it lives in OpenSpec
- **AND** multi-line command examples include comments explaining each command

### Requirement: Commit message conventions

Commit messages SHALL be Japanese gitmoji Conventional Commits.

#### Scenario: Contributor commits changes

- **WHEN** a commit is created
- **THEN** its message follows `<gitmoji> <type>: <summary>`
- **AND** common types include `feat`, `fix`, `docs`, `refactor`, `test`, and `chore`
- **AND** each commit contains one meaningful unit of work
- **AND** mixed documentation, implementation, and rename work is split where appropriate
