#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgReplica",
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
                "Replica",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "SessionTimeout",
                "EndpointUrl",
                "ReadonlyRoutingConnectionUrl",
                "ReadOnlyRoutingList",
                "InputObject",
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

        # Explain what needs to be set up for the test:
        # To modify an availability group replica, we need an availability group with a primary replica.

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_arepgroup"

        # Create the availability group.
        $splatAvailabilityGroup = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $ag = New-DbaAvailabilityGroup @splatAvailabilityGroup
        $replicaName = $ag.PrimaryReplica

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

    Context "Sets AG properties" {
        It "Returns modified results when setting BackupPriority" {
            $splatBackupPriority = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Replica           = $replicaName
                BackupPriority    = 100
            }
            $results = Set-DbaAgReplica @splatBackupPriority
            $results.AvailabilityGroup | Should -Be $agName
            $results.BackupPriority | Should -Be 100
        }

        It "Returns modified results when setting SeedingMode" {
            $splatSeedingMode = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Replica           = $replicaName
                SeedingMode       = "Automatic"
            }
            $results = Set-DbaAgReplica @splatSeedingMode
            $results.AvailabilityGroup | Should -Be $agName
            $results.SeedingMode | Should -Be "Automatic"
        }

        It "Attempts to add a ReadOnlyRoutingList" {
            $splatRoutingList = @{
                ReadOnlyRoutingList = "nondockersql"
                WarningAction       = "SilentlyContinue"
                WarningVariable     = "warn"
            }
            $null = Get-DbaAgReplica -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName | Select-Object -First 1 | Set-DbaAgReplica @splatRoutingList
            $warn | Should -Match "does not exist. Only availability"
        }

        It "Accepts simple ordered ReadOnlyRoutingList (issue #9987)" {
            $splatSimpleRouting = @{
                SqlInstance         = $TestConfig.InstanceHadr
                AvailabilityGroup   = $agName
                Replica             = $replicaName
                ReadOnlyRoutingList = @($replicaName)
                WarningAction       = "SilentlyContinue"
            }
            { Set-DbaAgReplica @splatSimpleRouting } | Should -Not -Throw
        }

        It "Accepts load-balanced ReadOnlyRoutingList" {
            $splatLoadBalanced = @{
                SqlInstance         = $TestConfig.InstanceHadr
                AvailabilityGroup   = $agName
                Replica             = $replicaName
                ReadOnlyRoutingList = @(,($replicaName))
                WarningAction       = "SilentlyContinue"
            }
            { Set-DbaAgReplica @splatLoadBalanced } | Should -Not -Throw
        }
    }

}

Describe "$CommandName Output" -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $existingAg = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr | Select-Object -First 1
            if ($existingAg) {
                $existingReplica = Get-DbaAgReplica -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $existingAg.Name | Where-Object Role -eq "Primary" | Select-Object -First 1
                if ($existingReplica) {
                    $currentPriority = $existingReplica.BackupPriority
                    $splatOutputValidation = @{
                        SqlInstance       = $TestConfig.InstanceHadr
                        AvailabilityGroup = $existingAg.Name
                        Replica           = $existingReplica.Name
                        BackupPriority    = $currentPriority
                    }
                    $result = Set-DbaAgReplica @splatOutputValidation
                }
            }
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityReplica"
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties.Name | Should -Contain "Name"
            $result[0].psobject.Properties.Name | Should -Contain "AvailabilityMode"
            $result[0].psobject.Properties.Name | Should -Contain "FailoverMode"
            $result[0].psobject.Properties.Name | Should -Contain "BackupPriority"
            $result[0].psobject.Properties.Name | Should -Contain "ConnectionModeInPrimaryRole"
            $result[0].psobject.Properties.Name | Should -Contain "ConnectionModeInSecondaryRole"
            $result[0].psobject.Properties.Name | Should -Contain "EndpointUrl"
            $result[0].psobject.Properties.Name | Should -Contain "SeedingMode"
            $result[0].psobject.Properties.Name | Should -Contain "SessionTimeout"
        }
    }
}