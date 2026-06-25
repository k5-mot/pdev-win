## ADDED Requirements

### Requirement: Portable root layout

The portable environment SHALL use a predictable root layout with `.local`, `.config`, and root-level launchers.

#### Scenario: Standard layout is created

- **WHEN** setup creates a portable root
- **THEN** `.local/bin`, `.local/opt`, `.local/pkg`, `.local/logs`, `.local/tmp`, `.config/pip`, and `.config/codex` are used for installed state
- **AND** `VSCode.cmd` and `PowerShell.cmd` are placed at the root

### Requirement: Root-level launcher boundary

The portable root SHALL keep tool bodies, settings, caches, logs, and temporary files in subdirectories instead of scattering them at the root.

#### Scenario: Root is inspected

- **WHEN** a maintainer inspects the root directory after standard setup
- **THEN** root-level command files are launchers
- **AND** installed tools and mutable state live under `.local` or `.config`

### Requirement: Bin shim directory

`.local/bin` SHALL contain cmd shims that delegate to tool executables under `.local/opt`.

#### Scenario: Fixed CLI shim is generated

- **WHEN** setup installs a fixed standalone CLI
- **THEN** the generated shim is placed in `.local/bin`
- **AND** it delegates to the executable under `.local/opt`

### Requirement: Tool body directory

`.local/opt` SHALL contain extracted or placed tool bodies.

#### Scenario: Tool is installed

- **WHEN** setup installs a tool
- **THEN** the tool body is placed under `.local/opt/<tool>`

### Requirement: Package and cache directory

`.local/pkg` SHALL contain downloaded archives, executables, wheels, and package caches.

#### Scenario: Setup downloads or caches package data

- **WHEN** setup downloads reusable artifacts or configures pip, uv, or npm cache
- **THEN** those files are placed under `.local/pkg` or its cache subdirectories

### Requirement: Logs and temporary files

`.local/logs` SHALL contain install logs and `.local/tmp` SHALL contain temporary extraction files.

#### Scenario: Setup performs noisy or temporary work

- **WHEN** setup runs external tools or extracts archives
- **THEN** logs are written under `.local/logs`
- **AND** temporary files are created under `.local/tmp`

### Requirement: Portable Codex config

`.config/codex` SHALL hold portable Codex user-level configuration copied from `config/.codex` when that template exists next to `setup.ps1`.

#### Scenario: Codex template exists

- **WHEN** setup sees `config/.codex`
- **THEN** it copies that content to `$Root\.config\codex`
- **AND** model provider credentials are handled by that config rather than by launcher scripts

### Requirement: Optional portable tools manifest

If `config/portable-tools.json` exists, setup SHALL prefer it as the GitHub Releases portable tools manifest.

#### Scenario: Manifest is present

- **WHEN** `setup.ps1` runs and finds `config/portable-tools.json`
- **THEN** each entry can define `name`, `repo`, `assetPattern`, `exeName`, `shimName`, and `versionArgs`
- **AND** setup falls back to its built-in manifest when the file does not exist
