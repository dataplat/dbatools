# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
```powershell
# Run all tests
.\tests\appveyor.pester.ps1

# Run tests with code coverage
.\tests\appveyor.pester.ps1 -IncludeCoverage

# Run specific test file
Invoke-Pester ./tests/Get-DbaDatabase.Tests.ps1

# Finalize test results
.\tests\appveyor.pester.ps1 -Finalize
```

### Development Setup
```powershell
# Enable debugging mode before importing
$dbatools_dotsourcemodule = $true
Import-Module ./dbatools.psd1

# Format code to match project standards (OTBS)
Invoke-DbatoolsFormatter -Path ./public/YourFunction.ps1
```

### Module Dependencies
- Primary dependency: `dbatools.library` module (contains SMO and other libraries)
- Install with: `Install-Module dbatools.library -Scope CurrentUser`

## Architecture Overview

### Core Structure
- **public/**: All user-facing commands (600+ functions). Each command is in its own file.
- **private/**: Internal functions organized by purpose:
  - **functions/**: Core internal helpers like `Connect-DbaInstance`, `Stop-Function`
  - **configurations/**: Module settings organized by topic (sql.ps1, logging.ps1, etc.)
  - **dynamicparams/**: Dynamic parameter definitions for tab completion
  - **maintenance/**: Background tasks and runspace management
- **bin/**: Resources including XE templates, diagnostic queries, build references
- **tests/**: Pester tests matching public function names

### Key Patterns

#### Command Standards
- **Naming**: `Verb-DbaObjectType` (e.g., `Get-DbaDatabase`, `Set-DbaSpConfigure`)
- **Common Parameters**:
  - `-SqlInstance`: Always accepts array of instances
  - `-SqlCredential`: PSCredential for SQL authentication
  - `-EnableException`: Shows full exception details instead of warnings
  - Always implement `-WhatIf`/`-Confirm` for destructive operations

#### Coding Conventions
- **Parameters**: PascalCase, always singular (`$SqlInstance`, not `$SqlInstances`)
- **Variables**: camelCase for multi-word (`$currentLogin`)
- **Error Handling**: Use `Stop-Function` for consistent error management
- **Output**: Use `Select-DefaultView` to control default property display
- **Connections**: Always use `Connect-DbaInstance` for SQL connections

#### Internal Functions
- `Connect-DbaInstance`: Centralizes all SQL Server connections with retry logic
- `Stop-Function`: Standard error handling with `-EnableException` support
- `Write-ProgressHelper`: Consistent progress bar implementation
- `Test-FunctionInterrupt`: Checks for user cancellation in loops
- `Select-DefaultView`: Controls which properties are displayed by default

### Configuration System
- Get settings: `Get-DbatoolsConfigValue -Name 'sql.connection.timeout'`
- Set settings: `Set-DbatoolsConfig -Name 'sql.connection.timeout' -Value 30`
- Configuration files in `private/configurations/` define module-wide defaults

### Testing Approach
- Test files must match function names: `Get-DbaDatabase.ps1` → `Get-DbaDatabase.Tests.ps1`
- Tests use Pester 4/5 compatible syntax
- AppVeyor CI tests against SQL Server 2008R2, 2016, 2017, 2022
- Mock `Connect-DbaInstance` in unit tests to avoid SQL dependencies

### Module Loading
1. `dbatools.psd1` defines module manifest
2. `dbatools.psm1` handles initialization:
   - Loads dbatools.library dependency
   - Imports all public/private functions
   - Initializes configuration system
   - Starts maintenance runspaces
3. Use `$dbatools_dotsourcemodule = $true` before import for debugging