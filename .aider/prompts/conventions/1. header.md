# Required Headers

## Core Requirements

### Required Header
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "StaticCommandName",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

## Must Use
- Static `$CommandName` parameter in param block

## Must Not Use
- Dynamic command name derivation from file paths
- Old knownParameters validation approach
- Assumed parameter names - match original tests exactly