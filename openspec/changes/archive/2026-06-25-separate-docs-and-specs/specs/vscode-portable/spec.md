## ADDED Requirements

### Requirement: VS Code portable placement

The standard bootstrap SHALL install VS Code under `$Root\.local\opt\vscode`.

#### Scenario: VS Code is installed

- **WHEN** setup completes VS Code installation
- **THEN** `Code.exe` and `bin\code.cmd` exist under `$Root\.local\opt\vscode`

### Requirement: VS Code portable data

VS Code SHALL run in portable mode with user data and extensions under the portable VS Code directory.

#### Scenario: VS Code portable mode is configured

- **WHEN** setup configures VS Code
- **THEN** user data is stored under `$Root\.local\opt\vscode\data\user-data`
- **AND** extensions are stored under `$Root\.local\opt\vscode\data\extensions`

### Requirement: VS Code settings files

The bootstrap SHALL generate VS Code user settings and extension recommendations in the portable user data directory.

#### Scenario: Settings are generated

- **WHEN** setup writes VS Code configuration
- **THEN** `settings.json` and `extensions.json` exist under `$Root\.local\opt\vscode\data\user-data\User`

### Requirement: Default integrated terminal

VS Code settings SHALL use `PowerShell-Portable` as the default integrated terminal profile.

#### Scenario: User opens a terminal in portable VS Code

- **WHEN** VS Code uses generated settings
- **THEN** the default integrated terminal profile is `PowerShell-Portable`

### Requirement: Cygwin profile ownership

The standard setup SHALL NOT create a Cygwin terminal profile; `setup_cygwin.ps1` SHALL add it when VS Code portable settings already exist.

#### Scenario: Cygwin is installed after standard setup

- **WHEN** `setup_cygwin.ps1` runs and finds existing VS Code portable settings
- **THEN** it adds a `Cygwin` profile to `terminal.integrated.profiles.windows`

### Requirement: VS Code UI and AI settings

Generated VS Code settings SHALL set the theme and disable selected built-in AI sign-in features.

#### Scenario: Settings are inspected

- **WHEN** generated VS Code settings are read
- **THEN** `workbench.colorTheme` is `Visual Studio Dark`
- **AND** `window.commandCenter` is disabled
- **AND** `chat.titleBar.signIn.enabled` is disabled
- **AND** `chat.disableAIFeatures` is enabled

### Requirement: VS Code extension set

The bootstrap SHALL recommend and install the configured VS Code extensions into the portable extensions directory.

#### Scenario: Extensions are installed

- **WHEN** setup installs VS Code extensions
- **THEN** `ZooCodeOrganization.zoo-code`, `zhuangtongfa.Material-theme`, `openai.chatgpt`, and `pkief.material-icon-theme` are installed or attempted in the portable extensions directory
