#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbMirrorFailover",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns the documented output type" {
            $command = Get-Command $CommandName
            $outputTypes = @($command.OutputType.Type.FullName)
            $outputTypes | Should -Contain "Microsoft.SqlServer.Management.Smo.Database" -Because "command should declare Database output type"
        }

        It "Has expected properties in output type" {
            $expectedProps = @(
                'Name',
                'Status',
                'RecoveryModel',
                'Owner',
                'LastBackupDate'
            )
            $props = ([Microsoft.SqlServer.Management.Smo.Database]).GetProperties().Name
            foreach ($prop in $expectedProps) {
                $props | Should -Contain $prop -Because "property '$prop' should exist in Database type"
            }
        }

        It "Output type has mirroring-specific properties" {
            $mirroringProps = @(
                'MirroringPartner',
                'MirroringStatus',
                'MirroringSafetyLevel'
            )
            $props = ([Microsoft.SqlServer.Management.Smo.Database]).GetProperties().Name
            foreach ($prop in $mirroringProps) {
                $props | Should -Contain $prop -Because "mirroring property '$prop' should exist in Database type"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>