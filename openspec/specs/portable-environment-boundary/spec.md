# portable-environment-boundary Specification

## Purpose
Define the portable environment's purpose, Desktop-only boundary, root-contained state, optional Cygwin separation, and required external network access.
## Requirements
### Requirement: Portable environment purpose

The standard bootstrap SHALL install a portable development environment under Desktop without administrator privileges.

#### Scenario: Standard bootstrap completes

- **WHEN** `setup.ps1` completes successfully
- **THEN** Python, pip, Node.js, uv, jq, pandoc, bat, bottom, crane, delta, dust, eza, fd, hyperfine, procs, ripgrep, and Visual Studio Code are available from the portable environment
- **AND** PATH is configured so the installed tools can be used
- **AND** VS Code and Windows PowerShell can be launched from root-level launchers

### Requirement: Optional Cygwin separation

Cygwin SHALL be installed only by `setup_cygwin.ps1`, not by the standard `setup.ps1` bootstrap.

#### Scenario: User wants Cygwin

- **WHEN** the user runs `setup_cygwin.ps1` against an existing portable root
- **THEN** Cygwin is added under that root
- **AND** the standard bootstrap remains usable without Cygwin

### Requirement: Desktop-only root

The bootstrap SHALL accept only roots that resolve under the OS-known Desktop folder.

#### Scenario: Root is outside Desktop

- **WHEN** a user supplies a `Root` outside the Desktop folder resolved by `[Environment]::GetFolderPath('Desktop')`
- **THEN** the script stops before installing tools

### Requirement: No fixed user profile path

The bootstrap SHALL NOT hard-code a physical user profile path when resolving Desktop or user-scoped locations.

#### Scenario: Desktop is redirected

- **WHEN** the user's Desktop is redirected or network-backed
- **THEN** the bootstrap uses the OS-known folder path
- **AND** warns when a network path may affect access

### Requirement: Root-contained state

The bootstrap SHALL keep binaries, user data, settings, caches, logs, and temporary files under the portable root wherever the tools allow it.

#### Scenario: Setup writes configuration or cache files

- **WHEN** setup configures tool state
- **THEN** AppData and global system locations are not required for normal operation
- **AND** the state is directed under the portable root

### Requirement: External network access

The standard bootstrap SHALL document and rely on access to GitHub, Python.org, Node.js, PyPI, and the VS Code update endpoint; optional Cygwin setup SHALL document and rely on access to Cygwin mirrors.

#### Scenario: Network access is restricted

- **WHEN** the environment blocks one of the required endpoints
- **THEN** setup can fail with a clear network-related cause
