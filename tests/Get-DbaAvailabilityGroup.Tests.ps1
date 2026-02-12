#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAvailabilityGroup",
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
                "IsPrimary",
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
        $agName = "dbatoolsci_agroup"

        # Create the objects.
        $splatAg = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When retrieving availability groups" {
        It "Returns results with proper data" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr
            $results.AvailabilityGroup | Should -Contain $agName
        }

        It "Returns a single result when specifying availability group name" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
            $results.AvailabilityGroup | Should -Be $agName
        }

        It "Returns output of the documented type" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityGroup"
        }

        It "Has the expected default display properties" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "LocalReplicaRole",
                "AvailabilityGroup",
                "PrimaryReplica",
                "ClusterType",
                "DtcSupportEnabled",
                "AutomatedBackupPreference",
                "AvailabilityReplicas",
                "AvailabilityDatabases",
                "AvailabilityGroupListeners"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.Properties["AvailabilityGroup"] | Should -Not -BeNullOrEmpty
            $results[0].psobject.Properties["AvailabilityGroup"].MemberType | Should -Be "AliasProperty"
            $results[0].psobject.Properties["PrimaryReplica"] | Should -Not -BeNullOrEmpty
            $results[0].psobject.Properties["PrimaryReplica"].MemberType | Should -Be "AliasProperty"
        }

        It "Has the expected default display properties with IsPrimary" {
            $resultIsPrimary = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -IsPrimary
            if (-not $resultIsPrimary) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $resultIsPrimary[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroup",
                "IsPrimary"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set with -IsPrimary"
            }
        }
    }
}