# documentation-boundary Specification

## Purpose
Define the boundary between user-facing manuals and development specifications so `docs/` stays operational while OpenSpec remains the development source of truth.
## Requirements
### Requirement: Documentation scope separation

The repository SHALL use OpenSpec as the source of truth for development requirements, implementation contracts, contribution rules, and maintainer workflow requirements.

#### Scenario: Development requirement is added

- **WHEN** a requirement describes how the project must be implemented, maintained, validated, or contributed to
- **THEN** the requirement is recorded under `openspec/specs/`
- **AND** it is not duplicated as a standalone requirement document under `docs/`

### Requirement: User documentation scope

The repository SHALL keep `docs/` focused on user-facing manuals, troubleshooting, and operational instructions needed to use the project.

#### Scenario: User needs operational help

- **WHEN** a user needs help running setup scripts or diagnosing runtime setup problems
- **THEN** the relevant manual remains reachable from `README.md` or `docs/`
- **AND** it does not require reading OpenSpec development requirements

### Requirement: README separation

The README SHALL distinguish user documentation from development specifications.

#### Scenario: Reader starts from README

- **WHEN** a reader opens the README documentation section
- **THEN** user-facing docs are listed as manuals
- **AND** development specifications are linked to `openspec/specs/`
