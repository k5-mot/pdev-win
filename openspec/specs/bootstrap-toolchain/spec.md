# bootstrap-toolchain Specification

## Purpose
Define the standard `setup.ps1` bootstrap contract: accepted arguments, default versions, download/cache behavior, portable CLI installation, shims, and portable-path verification.
## Requirements
### Requirement: Standard setup arguments

`setup.ps1` SHALL expose `Root`, tool version arguments, and `Force`, and SHALL NOT expose `PipVersion` or `SkipVSCodeLaunch`.

#### Scenario: User customizes setup

- **WHEN** a user runs `setup.ps1`
- **THEN** they can set `Root`, `PythonVersion`, `NodeVersion`, `UvVersion`, `JqVersion`, `PandocVersion`, `VSCodeVersion`, and `Force`
- **AND** `Root` still resolves under Desktop

### Requirement: Version defaults

The standard bootstrap SHALL maintain explicit defaults for versioned tools.

#### Scenario: User omits version arguments

- **WHEN** `setup.ps1` runs with defaults
- **THEN** Python defaults to `3.12.10`
- **AND** Node.js defaults to `24.16.0`
- **AND** uv defaults to `0.11.18`
- **AND** jq defaults to `1.8.0`
- **AND** pandoc defaults to `3.9.0.2`
- **AND** VS Code defaults to `stable`

### Requirement: Version tag normalization

The bootstrap SHALL accept common version prefix variants for Node.js, uv, and jq.

#### Scenario: User supplies prefixed versions

- **WHEN** a user supplies `v` prefixes for Node.js or uv or a `jq-` prefix for jq
- **THEN** setup normalizes the value before resolving downloads

### Requirement: Bootstrap sequence

The standard bootstrap SHALL perform the required setup sequence before reporting success.

#### Scenario: Standard setup runs

- **WHEN** `setup.ps1` executes
- **THEN** it enables TLS 1.2 when supported, validates root directories, creates required directories, downloads requested tool versions, reuses cache unless `Force` is set, installs tools under `.local/opt`, configures PATH and cache environment variables, writes VS Code configuration, copies Codex config templates when present, installs VS Code extensions, writes launchers, installs additional pip and npm packages, and verifies command availability

### Requirement: Cached download behavior

The bootstrap SHALL reuse cached downloads unless `Force` is set.

#### Scenario: Cached artifact exists

- **WHEN** a download target already exists under `.local/pkg`
- **AND** `Force` is not set
- **THEN** setup reuses the cached file

### Requirement: GitHub portable CLI tools

The bootstrap SHALL install GitHub Releases based portable CLI tools into `.local/opt` and create shims where configured.

#### Scenario: GitHub tool asset is resolved

- **WHEN** a portable CLI tool manifest entry resolves to a Windows x64 asset
- **THEN** setup downloads and expands or places the asset under `.local/opt`
- **AND** creates a shim under `.local/bin` when configured

### Requirement: Missing portable tools fail together

The bootstrap SHALL aggregate unresolved portable CLI tools and fail after reporting them.

#### Scenario: One or more tools cannot be fetched

- **WHEN** setup cannot resolve or install configured portable CLI tools
- **THEN** it reports the failed tools together
- **AND** the setup fails instead of silently continuing

### Requirement: Verification prefers portable paths

The bootstrap SHALL verify tool commands from portable shims or portable executable paths instead of relying on user or system PATH.

#### Scenario: Same command exists on system PATH

- **WHEN** a tool also exists outside the portable root
- **THEN** setup verification uses the path built from the portable root
