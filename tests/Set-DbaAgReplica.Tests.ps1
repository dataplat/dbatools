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
            Primary      = $TestConfig.instance3
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
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Sets AG properties" {
        It "Returns modified results when setting BackupPriority" {
            $splatBackupPriority = @{
                SqlInstance       = $TestConfig.instance3
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
                SqlInstance       = $TestConfig.instance3
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
            $null = Get-DbaAgReplica -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName | Select-Object -First 1 | Set-DbaAgReplica @splatRoutingList
            $warn | Should -Match "does not exist. Only availability"
        }

        It "Sets simple ordered ReadOnlyRoutingList correctly (issue #9987)" -Skip:$env:appveyor {
            $splatSimpleRouting = @{
                SqlInstance         = $TestConfig.instance3
                AvailabilityGroup   = $agName
                Replica             = $replicaName
                ReadOnlyRoutingList = @($replicaName)
                WarningAction       = "SilentlyContinue"
            }
            $result = Set-DbaAgReplica @splatSimpleRouting
            $result.ReadonlyRoutingList | Should -Contain $replicaName
            $result.ReadonlyRoutingList.Count | Should -Be 1
        }

        It "Sets load-balanced ReadOnlyRoutingList correctly" -Skip:$env:appveyor {
            $splatLoadBalanced = @{
                SqlInstance         = $TestConfig.instance3
                AvailabilityGroup   = $agName
                Replica             = $replicaName
                ReadOnlyRoutingList = @(,($replicaName))
                WarningAction       = "SilentlyContinue"
            }
            $result = Set-DbaAgReplica @splatLoadBalanced
            # Load-balanced routing lists show as comma-separated groups in the property
            $result.ReadonlyRoutingList | Should -Not -BeNullOrEmpty
        }
    }
} #$TestConfig.instance2 for appveyor