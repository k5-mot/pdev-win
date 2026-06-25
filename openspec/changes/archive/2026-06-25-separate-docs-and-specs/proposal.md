## Why

The repository currently mixes development specifications and user-facing manuals under `docs/`, while OpenSpec has only one broad repository-documentation spec. This makes it unclear where future requirements should live and risks documentation drift between `docs/` and `openspec/`.

## What Changes

- Move development requirements from `docs/SPEC.md` into OpenSpec specs split by capability.
- Move coding and commit conventions from `docs/CODING_RULES.md` into OpenSpec.
- Remove maintainer/development-only docs from `docs/` so that `docs/` remains focused on user manuals and operational help.
- Replace the broad `repository-documentation` spec with more precise documentation-boundary and repository-maintenance specs.
- Update README links to reflect the docs/OpenSpec separation.

## Capabilities

### New Capabilities

- `documentation-boundary`: Defines the separation between user-facing docs and development specifications.
- `portable-environment-boundary`: Defines the portable environment purpose, constraints, installed tool scope, and external access requirements.
- `portable-layout`: Defines the required portable directory layout and path ownership rules.
- `bootstrap-toolchain`: Defines `setup.ps1` arguments, bootstrap sequence, tool download, cache, shim, and verification behavior.
- `python-node-packages`: Defines pip and npm package management requirements.
- `vscode-portable`: Defines VS Code portable mode, settings, extensions, and profile requirements.
- `cygwin-integration`: Defines optional Cygwin installation behavior.
- `launchers-terminal`: Defines launcher command behavior and Windows Terminal integration requirements.
- `logging-validation-automation`: Defines logging, runtime validation, and CI validation requirements.
- `repository-maintenance`: Defines tracked repository areas, archives, generated files, scripts, and agent skill responsibilities.
- `contribution-guidelines`: Defines coding, Markdown, shell, PowerShell, and commit conventions.

### Modified Capabilities

None. The previous broad `repository-documentation` main spec will be removed as obsolete after the split specs are archived.

## Impact

- `openspec/specs/*`: New split specifications after archive.
- `openspec/specs/repository-documentation/spec.md`: Removed after archive as obsolete.
- `docs/SPEC.md`: Removed because the content becomes OpenSpec development specification.
- `docs/CODING_RULES.md`: Removed because development conventions become OpenSpec.
- `docs/REPOSITORY_GUIDE.md`: Removed because maintainer content belongs in OpenSpec.
- `README.md`: Documentation links updated.
- `openspec/config.yaml`: Project context updated for future changes.
