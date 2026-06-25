# python-node-packages Specification

## Purpose
Define portable pip and npm package management requirements for the embedded Python and Node.js environments.
## Requirements
### Requirement: Pip from wheel

The bootstrap SHALL install pip from a PyPI wheel instead of `get-pip.py`.

#### Scenario: Python embeddable environment is prepared

- **WHEN** setup installs pip
- **THEN** it obtains a pip wheel from PyPI
- **AND** installs it into the embeddable Python site-packages

### Requirement: Python embeddable site support

The bootstrap SHALL adjust Python embeddable `_pth` files so pip and installed packages can be imported.

#### Scenario: Python package import path is needed

- **WHEN** pip and additional packages are installed
- **THEN** the `_pth` configuration enables `import site` and package imports

### Requirement: Pip command wrapper

The bootstrap SHALL create `Scripts\pip.cmd` that invokes `python -m pip`.

#### Scenario: User runs pip

- **WHEN** `pip` is invoked from the portable environment
- **THEN** it uses the portable Python interpreter

### Requirement: Pip configuration and cache

The bootstrap SHALL generate portable pip configuration and cache settings.

#### Scenario: Pip is configured

- **WHEN** setup writes `.config\pip\pip.ini`
- **THEN** `disable-pip-version-check = true` is set
- **AND** `PIP_CACHE_DIR` points to `$Root\.local\pkg\pip-cache`

### Requirement: Additional Python packages

The bootstrap SHALL install additional Python packages required by this repository.

#### Scenario: Python packages are installed

- **WHEN** setup completes
- **THEN** `setuptools`, `wheel`, `python-docx`, `pypdf`, and `Pillow` are installed

### Requirement: Npm portable cache and prefix

The bootstrap SHALL direct npm cache and prefix under the portable root.

#### Scenario: Npm package installation runs

- **WHEN** setup installs npm packages
- **THEN** npm cache and prefix do not rely on global user locations

### Requirement: Additional npm packages

The bootstrap SHALL install `npm` and `cowsay` as global npm packages in the portable environment.

#### Scenario: Npm packages are installed

- **WHEN** setup completes npm package installation
- **THEN** `npm` and `cowsay` are available through the portable Node.js environment
