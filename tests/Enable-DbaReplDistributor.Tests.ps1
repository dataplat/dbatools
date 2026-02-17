#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplDistributor",
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
                "DistributionDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup: disable distribution if it was enabled during testing
        $replServer = Get-DbaReplServer -SqlInstance $TestConfig.InstanceMulti1
        if ($replServer.IsDistributor) {
            $null = Disable-DbaReplDistributor -SqlInstance $TestConfig.InstanceMulti1 -Force -Confirm:$false
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When enabling replication distribution" {
        BeforeAll {
            try {
                $results = Enable-DbaReplDistributor -SqlInstance $TestConfig.InstanceMulti1 -EnableException -OutVariable "global:dbatoolsciOutput"
            } catch {
                $global:dbatoolsciReplError = $PSItem.Exception.Message
            }
        }

        It "Should enable the distributor" {
            if ($global:dbatoolsciReplError) {
                Set-ItResult -Skipped -Because "replication not available: $($global:dbatoolsciReplError)"
                return
            }
            $results.IsDistributor | Should -BeTrue
        }

        It "Should have the default distribution database name" {
            if ($global:dbatoolsciReplError) {
                Set-ItResult -Skipped -Because "replication not available"
                return
            }
            $results.DistributionDatabases.Name | Should -Contain "distribution"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.ReplicationServer]
        }

        It "Should have the correct default display columns" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "IsDistributor",
                "IsPublisher",
                "DistributionServer",
                "DistributionDatabase"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.ReplicationServer"
        }
    }
}