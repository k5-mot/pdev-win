# logging-validation-automation Specification

## Purpose
Define setup logging, runtime validation, and GitHub Actions validation requirements for the portable bootstrap.
## Requirements
### Requirement: Setup logging

Setup scripts SHALL emit structured log messages and store install logs under the portable root.

#### Scenario: Setup logs a message

- **WHEN** setup emits a log line
- **THEN** the log includes time, level, message, and console color behavior
- **AND** supported levels include `INFO`, `OK`, `WARN`, `ERROR`, and `STEP`

### Requirement: Runtime command validation

Setup SHALL validate installed tools by checking portable paths and version commands.

#### Scenario: Tool verification runs

- **WHEN** setup verifies installed tools
- **THEN** it checks expected executable or shim paths
- **AND** runs version commands for installed tools

### Requirement: GitHub Actions bootstrap validation

The repository SHALL validate the portable bootstrap on Windows PowerShell in CI.

#### Scenario: Validation workflow runs

- **WHEN** `.github/workflows/validate-portable-dev.yml` runs
- **THEN** it prepares a Desktop workspace, parses `setup.ps1`, `setup_mise.ps1`, and `setup_cygwin.ps1`, runs standard setup and optional Cygwin setup with `Force`, verifies expected layout paths, and uploads setup logs when available

### Requirement: Workflow trigger scope

The validation workflow SHALL run when bootstrap scripts, configuration templates, or the workflow itself change.

#### Scenario: Bootstrap-related file changes

- **WHEN** a push or pull request changes `setup.ps1`, `setup_mise.ps1`, `setup_cygwin.ps1`, `config/**`, or `.github/workflows/validate-portable-dev.yml`
- **THEN** the validation workflow is eligible to run

### Requirement: Pinned GitHub release version validation

The repository SHALL validate that script-pinned GitHub Releases versions match the latest upstream releases.

#### Scenario: Pinned version workflow runs

- **WHEN** `.github/workflows/check-pinned-versions.yml` runs
- **THEN** it executes `scripts/Test-PinnedGitHubReleaseVersions.ps1`
- **AND** compares GitHub Releases tags pinned by `setup.ps1` and `setup_mise.ps1` with each repository's latest release tag
- **AND** fails when a pinned release is outdated

#### Scenario: Pinned version related file changes

- **WHEN** a push or pull request changes `setup.ps1`, `setup_mise.ps1`, `scripts/Test-PinnedGitHubReleaseVersions.ps1`, or `.github/workflows/check-pinned-versions.yml`
- **THEN** the pinned version workflow is eligible to run
