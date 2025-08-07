## MANDATORY HEADER STRUCTURE

Insert this exact header block at the top of every test file:
```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "StaticCommandName",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
```

Replace "StaticCommandName" with the actual command name being tested.

## PARAMETER HANDLING

Define all `$CommandName` parameters as static strings in the param block.

Remove all dynamic command name derivation from file paths or directory structures.

Strip out all knownParameters validation code.

Preserve all original parameter names exactly as written in existing tests - make no assumptions about parameter naming.

Apply these header requirements to every test file without exception.