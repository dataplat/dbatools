# Implement - Execute Tasks from Specification

Implement a dbatools command following the specification and task list.

## Input Required

**Specification File**: --SPECFILE--
**Task List**: --TASKLIST-- (optional, will generate if not provided)

## Instructions

Execute the tasks sequentially, creating working code that:

1. **Follows dbatools coding standards** (CLAUDE.md)
2. **Matches the specification** exactly
3. **Passes all acceptance criteria**
4. **Includes tests**

## dbatools Code Standards Checklist

### MUST DO

- [x] Use `[Parameter(Mandatory)]` not `[Parameter(Mandatory = $true)]`
- [x] Use `New-Object` not `::new()`
- [x] Use splatting for 3+ parameters: `$splatPurpose = @{ ... }`
- [x] Align hashtable equals signs vertically
- [x] Use double quotes for strings
- [x] Emit objects immediately to pipeline
- [x] Use SMO first, T-SQL only when needed
- [x] Include proper error handling with Stop-Function

### MUST NOT DO

- [ ] Use backticks for line continuation
- [ ] Use `= $true` in parameter attributes
- [ ] Use `::new()` constructor syntax
- [ ] Collect output in ArrayList/arrays
- [ ] Add unnecessary comments or documentation
- [ ] Over-engineer with extra features

## Implementation Pattern

```powershell
function Verb-DbaNoun {
    <#
    .SYNOPSIS
        Brief description.

    .DESCRIPTION
        Detailed description.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login credential for SQL Server authentication.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: <Tags>
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Verb-DbaNoun

    .EXAMPLE
        PS C:\> Verb-DbaNoun -SqlInstance sql01

        Description of what this example does.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql01 | Verb-DbaNoun

        Description of pipeline example.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        # Initialization code
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }

            # Process items and emit immediately
            foreach ($item in $collection) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    # Additional properties
                }
            }
        }
    }
}
```

## Test Pattern

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }

Describe "Verb-DbaNoun" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Verb-DbaNoun
        }

        It "Should have SqlInstance as mandatory parameter" {
            $command | Should -HaveParameter SqlInstance -Mandatory
        }

        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Not -Mandatory
        }

        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Not -Mandatory
        }
    }
}

Describe "Verb-DbaNoun" -Tag "IntegrationTests" {
    Context "When querying single instance" {
        It "Should return results" {
            $result = Verb-DbaNoun -SqlInstance $TestConfig.instance1
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
```

## Commit Message Format

```
Verb-DbaNoun - Brief description of the command

<Optional longer description>

(do Verb-DbaNoun)
```

## Output

After implementation:
1. Command file created at `public/Verb-DbaNoun.ps1`
2. Test file created at `tests/Verb-DbaNoun.Tests.ps1`
3. Command registered in dbatools.psd1 and dbatools.psm1
4. All acceptance criteria from spec are met
