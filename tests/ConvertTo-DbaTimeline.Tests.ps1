param($ModuleName = 'dbatools')

Describe "ConvertTo-DbaTimeline Unit Tests" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command ConvertTo-DbaTimeline
        }
        $parms = @(
            'InputObject',
            'ExcludeRowLabel',
            'EnableException'
        )
        It "Should have parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
