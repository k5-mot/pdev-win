## ADDED Requirements

### Requirement: Cygwin setup arguments

`setup_cygwin.ps1` SHALL expose `Root`, `CygwinPackages`, and `Force`.

#### Scenario: User runs optional Cygwin setup

- **WHEN** the user runs `setup_cygwin.ps1`
- **THEN** `Root` defaults to Desktop `pdev`
- **AND** `CygwinPackages` defaults to `bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux,jq`
- **AND** Cygwin installs under `$Root\.local\opt\cygwin`

### Requirement: Cygwin mirror selection

Optional Cygwin setup SHALL choose a reachable mirror from the configured candidate list with a fallback.

#### Scenario: Primary mirrors are unavailable

- **WHEN** the JAIST, Yamagata University, and IIJ mirrors are unavailable
- **THEN** setup falls back to `https://mirrors.kernel.org/sourceware/cygwin/`

### Requirement: Cygwin no-admin install

Optional Cygwin setup SHALL use official `setup-x86_64.exe` in no-admin mode.

#### Scenario: Cygwin setup launches

- **WHEN** setup invokes `setup-x86_64.exe`
- **THEN** it uses `--quiet-mode`, `--no-admin`, `--only-site`, `--root`, `--local-package-dir`, `--site`, and `--packages`
- **AND** Cygwin setup uses `IE5` net-method so system proxy settings can apply

### Requirement: Cygwin launcher

Optional Cygwin setup SHALL generate `$Root\Cygwin.cmd`.

#### Scenario: User starts Cygwin

- **WHEN** the user runs `Cygwin.cmd`
- **THEN** it changes to `$Root\.local\opt\cygwin\bin`
- **AND** starts `bash --login -i`
