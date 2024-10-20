param($ModuleName = 'dbatools')

Describe "Copy-DbaInstanceAuditSpecification Unit Tests" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaInstanceAuditSpecification
        }
        $paramCount = 10
        $knownParameters = [object[]]@(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'AuditSpecification',
            'ExcludeAuditSpecification',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should contain <paramCount> parameters" {
            $command.Parameters.Count - $defaultParamCount | Should -Be $paramCount
        }
        It "Should contain parameter: <_>" -ForEach $knownParameters {
            $command | Should -HaveParameter $_ 
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
