#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaAgReplica",
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
                "Name",
                "ClusterType",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "Endpoint",
                "EndpointUrl",
                "Passthru",
                "ReadOnlyRoutingList",
                "ReadonlyRoutingConnectionUrl",
                "Certificate",
                "ConfigureXESession",
                "SessionTimeout",
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
        # To add an availability group replica, we need an availability group to work with.

        # Set variables. They are available in all the It blocks.
        $primaryAgName = "dbatoolsci_agroup"

        # Create the objects.
        $splatPrimary = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $primaryAgName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $primaryAg = New-DbaAvailabilityGroup @splatPrimary
        $replicaName = $primaryAg.PrimaryReplica

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $primaryAgName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding AG replicas" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary      = $TestConfig.InstanceHadr
                Name         = $replicaAgName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
                            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects.
            $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $replicaAgName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.InstanceHadr -OutVariable "global:dbatoolsciOutput"
            $results.AvailabilityGroup | Should -Contain $replicaAgName
            $results.Role | Should -Contain "Primary"
            $results.AvailabilityMode | Should -Contain "SynchronousCommit"
            $results.FailoverMode | Should -Contain "Manual"
        }

        It "Returns just one result for a specific replica" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.InstanceHadr -Replica $replicaName -AvailabilityGroup $replicaAgName
            $results.AvailabilityGroup | Should -Be $replicaAgName
            $results.Role | Should -Be "Primary"
            $results.AvailabilityMode | Should -Be "SynchronousCommit"
            $results.FailoverMode | Should -Be "Manual"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityReplica]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroup",
                "Name",
                "Role",
                "ConnectionState",
                "RollupSynchronizationState",
                "AvailabilityMode",
                "BackupPriority",
                "EndpointUrl",
                "SessionTimeout",
                "FailoverMode",
                "ReadonlyRoutingList"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.AvailabilityReplica"
        }
    }
}