# launchers-terminal Specification

## Purpose
Define root-level launcher behavior and optional Windows Terminal profile requirements for the portable environment.
## Requirements
### Requirement: Standard launchers

The standard bootstrap SHALL create `$Root\VSCode.cmd` and `$Root\PowerShell.cmd`; optional Cygwin setup SHALL create `$Root\Cygwin.cmd`.

#### Scenario: Launchers are generated

- **WHEN** setup completes
- **THEN** the expected root-level launcher files exist

### Requirement: VS Code launcher environment

`VSCode.cmd` SHALL configure portable PATH and cache/config environment before starting VS Code.

#### Scenario: VS Code launcher runs

- **WHEN** `VSCode.cmd` executes
- **THEN** it adds `.local\bin` and required `.local\opt` directories to PATH
- **AND** sets `PIP_CONFIG_FILE`, `PIP_CACHE_DIR`, `UV_CACHE_DIR`, `npm_config_cache`, `CODEX_HOME`, and `CODEX_SQLITE_HOME`
- **AND** starts `Code.exe` with `--user-data-dir`, `--extensions-dir`, `--disable-gpu`, and `--no-sandbox`
- **AND** exits with code 0 after launch

### Requirement: PowerShell launcher environment

`PowerShell.cmd` SHALL start Windows PowerShell with the portable PATH and cache environment.

#### Scenario: PowerShell launcher runs

- **WHEN** `PowerShell.cmd` executes
- **THEN** it adds `.local\bin` and required `.local\opt` directories to PATH
- **AND** configures cache-related environment variables for the portable root
- **AND** starts Windows PowerShell

### Requirement: No automatic VS Code launch

The standard bootstrap SHALL NOT auto-launch VS Code after installation.

#### Scenario: Setup completes

- **WHEN** installation succeeds
- **THEN** setup logs the launcher paths
- **AND** leaves launch choice to the user

### Requirement: Windows Terminal profiles

Windows Terminal integration SHALL be documented as an optional user configuration that preserves existing profiles.

#### Scenario: User configures Windows Terminal

- **WHEN** a user adds `PowerShell-Portable` or `Cygwin` profiles
- **THEN** `PowerShell-Portable` runs `$Root\PowerShell.cmd`
- **AND** `Cygwin` runs `$Root\Cygwin.cmd`
- **AND** `startingDirectory` matches the actual root
