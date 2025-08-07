# Required Headers

## Core Requirements

### Required Header
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "StaticCommandName",  # Always use static command name, never derive from file
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```
The `$CommandName` must always be a static string matching the command being tested.

## Must Use
- Static `$CommandName` parameter in param block
- The approach shown for parameter validation with filtering out WhatIf/Confirm

## Must Not Use
- Dynamic command name derivation from file paths
- Old knownParameters validation approach
- Assumed parameter names - match original tests exactly