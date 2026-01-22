#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobOwner",
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
                "Job",
                "ExcludeJob",
                "InputObject",
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $jobName = "dbatoolsci_outputtest_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $server -Job $jobName -OwnerLogin 'sa'
            $result = Set-DbaAgentJobOwner -SqlInstance $TestConfig.instance2 -Job $jobName -Login 'sa' -EnableException
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $null = Remove-DbaAgentJob -SqlInstance $server -Job $jobName -Confirm:$false
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Category',
                'OwnerLoginName',
                'Status',
                'Notes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Status property added by dbatools" {
            $result.Status | Should -BeIn @('Skipped', 'Failed', 'Successful')
        }

        It "Has Notes property added by dbatools" {
            $result.PSObject.Properties.Name | Should -Contain 'Notes'
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>