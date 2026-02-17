#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAgFailover",
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
                "AvailabilityGroup",
                "InputObject",
                "Force",
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

        # Set variables. They are available in all the It blocks.
        $agName = "AG01"
        $primaryInstance = $TestConfig.InstanceSingle
        $secondaryInstance = $TestConfig.instance2

        # Record the current primary so we can restore it in AfterAll.
        $agBefore = Get-DbaAvailabilityGroup -SqlInstance $primaryInstance -AvailabilityGroup $agName
        $originalPrimary = $agBefore.PrimaryReplicaServerName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # Restore the original primary if it changed during the test.
        $agAfter = Get-DbaAvailabilityGroup -SqlInstance $primaryInstance -AvailabilityGroup $agName
        if ($agAfter.PrimaryReplicaServerName -ne $originalPrimary) {
            $splatRestore = @{
                SqlInstance       = $originalPrimary
                AvailabilityGroup = $agName
                Force             = $true
                Confirm           = $false
            }
            $null = Invoke-DbaAgFailover @splatRestore
        }
    }

    Context "When failing over an availability group" {
        It "Returns the availability group after failover" {
            # Force failover is needed because the replicas may not be fully synchronized.
            $splatFailover = @{
                SqlInstance       = $secondaryInstance
                AvailabilityGroup = $agName
                Force             = $true
                Confirm           = $false
            }
            $result = Invoke-DbaAgFailover @splatFailover -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $agName
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.AvailabilityGroup"
        }
    }
}
